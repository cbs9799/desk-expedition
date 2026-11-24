#!/usr/bin/env bash
# Release 빌드 → Developer ID 서명 → Apple 공증 → 스테이플링 → dist/에 dmg·zip.
# 사용법: scripts/package.sh [버전]   (버전을 빼면 project.yml의 MARKETING_VERSION)
#
# 서명·공증 설정 (기본값은 집서버 Mac Studio 기준, 환경 변수로 바꿀 수 있음)
#   SIGNING_KEYCHAIN  서명용 키체인            기본 ~/Library/Keychains/signing.keychain-db
#   KEYCHAIN_PASS_FILE 키체인 비밀번호 파일     기본 ~/.signing/keychain-pass
#   DEVELOPER_ID      서명 인증서 이름          기본 "Developer ID Application: Beomseok Jang (E88HH68953)"
#   NOTARY_PROFILE    notarytool 키체인 프로필  기본 weekwrap-notary
#   NOTARIZE=0        서명·공증 없이 ad-hoc으로만 빌드(CI·다른 맥용)
# 키체인이 없으면 자동으로 ad-hoc 빌드로 떨어진다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(awk -F'"' '/MARKETING_VERSION/{print $2; exit}' project.yml)}"
VERSION="${VERSION#v}"
APP_NAME="DeskExpedition"
VOL_NAME="책상 원정대"
DERIVED="$ROOT/build/release"
DIST="$ROOT/dist"
APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
ENTITLEMENTS="$ROOT/Sources/DeskExpedition.entitlements"

KC="${SIGNING_KEYCHAIN:-$HOME/Library/Keychains/signing.keychain-db}"
KC_PASS_FILE="${KEYCHAIN_PASS_FILE:-$HOME/.signing/keychain-pass}"
DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: Beomseok Jang (E88HH68953)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-weekwrap-notary}"

NOTARIZE="${NOTARIZE:-1}"
if [[ "$NOTARIZE" == 1 && ( ! -f "$KC" || ! -f "$KC_PASS_FILE" ) ]]; then
  echo "==> 서명용 키체인이 없어 ad-hoc으로 빌드합니다 ($KC)"
  NOTARIZE=0
fi

echo "==> 버전 $VERSION"
xcodegen generate >/dev/null

xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' \
  MARKETING_VERSION="$VERSION" ONLY_ACTIVE_ARCH=NO \
  clean build | tail -3
lipo -archs "$APP/Contents/MacOS/$APP_NAME"

notary() {   # notary <file>
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --keychain "$KC" --wait | tee "$DIST/notary.log"
  grep -q "status: Accepted" "$DIST/notary.log" || { echo "공증 실패"; exit 1; }
}

rm -rf "$DIST" && mkdir -p "$DIST"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

if [[ "$NOTARIZE" == 1 ]]; then
  echo "==> Developer ID 서명: $DEVELOPER_ID"
  security unlock-keychain -p "$(cat "$KC_PASS_FILE")" "$KC"
  # The app has no nested frameworks, so signing the bundle itself is enough.
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" \
    --keychain "$KC" --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  echo "==> 앱 공증 (몇 분 걸릴 수 있음)"
  ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
  notary "$DIST/notarize.zip"
  rm "$DIST/notarize.zip"
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
else
  codesign --verify --deep --strict "$APP"
fi

echo "==> zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ "$NOTARIZE" == 1 ]]; then
  echo "==> dmg 서명·공증"
  codesign --force --timestamp --keychain "$KC" --sign "$DEVELOPER_ID" "$DMG"
  notary "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  rm -f "$DIST/notary.log"
fi

(cd "$DIST" && shasum -a 256 *.zip *.dmg > SHA256SUMS.txt)
echo "==> 완료 ($([[ "$NOTARIZE" == 1 ]] && echo "공증됨" || echo "ad-hoc"))"
ls -lh "$DIST"
