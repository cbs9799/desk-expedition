#!/usr/bin/env bash
# Release 빌드 후 배포용 zip과 dmg를 dist/에 만든다.
# 사용법: scripts/package.sh [버전]   (버전을 빼면 project.yml의 MARKETING_VERSION)
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

echo "==> 버전 $VERSION"
xcodegen generate >/dev/null

xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' \
  MARKETING_VERSION="$VERSION" ONLY_ACTIVE_ARCH=NO \
  clean build | tail -3

echo "==> 서명 확인"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/$APP_NAME"

rm -rf "$DIST" && mkdir -p "$DIST"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

echo "==> zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

(cd "$DIST" && shasum -a 256 *.zip *.dmg > SHA256SUMS.txt)
echo "==> 완료"
ls -lh "$DIST"
