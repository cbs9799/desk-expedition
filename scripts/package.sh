#!/usr/bin/env bash
# Release 빌드 후 배포용 zip과 dmg를 dist/에 만든다.
# 사용법: scripts/package.sh [버전]   (버전을 빼면 project.yml의 MARKETING_VERSION)
#
# 공증 배포(선택): 아래 환경 변수가 있으면 Developer ID로 서명하고 Apple 공증 후 스테이플링한다.
#   DEVELOPER_ID      서명 인증서 이름, 예) "Developer ID Application: Name (TEAMID)"
#   DEVELOPMENT_TEAM  팀 ID (생략하면 DEVELOPER_ID 괄호 안에서 읽음)
#   공증 자격 증명 — 둘 중 하나:
#     NOTARY_PROFILE                         `xcrun notarytool store-credentials`로 저장한 키체인 프로필 이름
#     NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER   App Store Connect API 키(.p8 경로)와 ID들
# 없으면 지금처럼 ad-hoc 서명(공증 없음)으로 만든다.
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

SIGN_ARGS=()
NOTARIZE=0
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  TEAM="${DEVELOPMENT_TEAM:-$(sed -E 's/.*\(([A-Z0-9]+)\).*/\1/' <<<"$DEVELOPER_ID")}"
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$DEVELOPER_ID" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM"
             OTHER_CODE_SIGN_FLAGS="--timestamp" ENABLE_HARDENED_RUNTIME=YES)
  NOTARIZE=1
  echo "==> Developer ID 서명: $DEVELOPER_ID (팀 $TEAM)"
else
  echo "==> ad-hoc 서명 (DEVELOPER_ID 없음 → 공증 생략)"
fi

notary() {   # notary <file>
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    xcrun notarytool submit "$1" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  fi
}

echo "==> 버전 $VERSION"
xcodegen generate >/dev/null

xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' \
  MARKETING_VERSION="$VERSION" ONLY_ACTIVE_ARCH=NO ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
  clean build | tail -3

echo "==> 서명 확인"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Signature" | head -3 || true
lipo -archs "$APP/Contents/MacOS/$APP_NAME"

rm -rf "$DIST" && mkdir -p "$DIST"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

if [[ $NOTARIZE == 1 ]]; then
  echo "==> 앱 공증"
  ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
  notary "$DIST/notarize.zip"
  rm "$DIST/notarize.zip"
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose "$APP"
fi

echo "==> zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ $NOTARIZE == 1 ]]; then
  echo "==> dmg 서명·공증"
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
  notary "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

(cd "$DIST" && shasum -a 256 *.zip *.dmg > SHA256SUMS.txt)
echo "==> 완료"
ls -lh "$DIST"
