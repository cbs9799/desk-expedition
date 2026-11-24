## 설치

1. 아래 **Assets**에서 `DeskExpedition-<버전>.dmg`를 받아 열고, 앱을 `Applications` 폴더로 끌어다 놓습니다. (`.zip`을 받아 풀어도 됩니다.)
2. 처음 열 때 "확인되지 않은 개발자" 경고가 뜨면:
   - **시스템 설정 → 개인정보 보호 및 보안** 맨 아래의 **"그래도 열기"**를 누릅니다.
   - 또는 터미널에서 `xattr -dr com.apple.quarantine /Applications/DeskExpedition.app` 실행 후 다시 엽니다.
3. 실행하면 메뉴바에 방패 아이콘이 생기고 화면 아래(Dock 위)에 원정 띠가 나타납니다.

- 요구 사항: macOS 14 이상, Apple Silicon·Intel 모두 지원(유니버설)
- 아직 Apple 공증(notarization)을 받지 않은 개발 빌드입니다. `SHA256SUMS.txt`로 파일 무결성을 확인할 수 있습니다.
