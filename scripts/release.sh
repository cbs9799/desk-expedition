#!/usr/bin/env bash
# 공증된 릴리스를 GitHub에 올린다. 집서버(서명용 키체인이 있는 맥)에서 실행.
# 사용법: scripts/release.sh            (project.yml의 MARKETING_VERSION으로 v<버전> 릴리스)
# 순서: 테스트 → package.sh(서명·공증·스테이플) → 태그 푸시 → gh release 생성·업로드 → 내려받아 검증
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(awk -F'"' '/MARKETING_VERSION/{print $2; exit}' project.yml)"
TAG="v$VERSION"

[[ -z "$(git status --porcelain)" ]] || { echo "커밋 안 된 변경이 있습니다"; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "$TAG 태그가 이미 있습니다 (project.yml 버전을 올리세요)"; exit 1; }

echo "==> 테스트"
xcodegen generate >/dev/null
xcodebuild -project DeskExpedition.xcodeproj -scheme DeskExpedition -derivedDataPath build/test test 2>&1 | grep -E "Executed|error:" | tail -2

scripts/package.sh "$VERSION"
grep -q . dist/SHA256SUMS.txt
spctl --assess --type open --context context:primary-signature dist/*.dmg   # 공증 안 된 결과물은 올리지 않음

echo "==> 태그·릴리스 $TAG"
git push -q origin HEAD
git tag "$TAG"
git push -q origin "$TAG"
gh release create "$TAG" dist/*.dmg dist/*.zip dist/SHA256SUMS.txt \
  --title "책상 원정대 $TAG" --notes-file .github/release-notes.md

echo "==> 내려받아 검증"
TMP="$(mktemp -d)"
gh release download "$TAG" -D "$TMP"
(cd "$TMP" && shasum -a 256 -c SHA256SUMS.txt)
xcrun stapler validate "$TMP"/*.dmg
ditto -x -k "$TMP"/*.zip "$TMP/x"
spctl --assess --type execute --verbose=2 "$TMP/x/DeskExpedition.app"
echo "==> 완료: $(gh release view "$TAG" --json url --jq .url)"
