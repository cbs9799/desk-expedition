# 출시·수익 준비 (0.2.7)

## 수익 모델 (결정)
- **유료 본편 1회 구매**: $4.99 / ₩6,600. 광고, 뽑기, 장터, 편의 과금(가방·창고 슬롯 판매)은 하지 않는다. 경쟁작 리뷰 불만 1순위가 이것이다(`docs/COMPETITORS-2026-11.md`).
- **추가 상품은 외형만**: 책상 테마 팩(풍경 색조와 소품 세트), 모자·펫 꾸미기 팩. 게임 성능에 영향을 주지 않는다.
  - **구현 완료(0.2.8)**: `Sources/App/CosmeticShop.swift`(StoreKit 2)에 비소모성 상품 2개를 넣었다.
    - `club.lemongrove.deskexpedition.themes`: 책상 테마 팩 $2.99. 테마를 언제든 고를 수 있다.
    - `club.lemongrove.deskexpedition.supporter`: 후원 팩 $1.99. 금빛 이름과 후원 배지.
  - 본부 → 기록 탭에 "꾸미기 상점"이 있다. 구매, 복원, 테마 선택을 지원한다.
  - 테스트: `Config/Products.storekit` 테스트 설정과 `Tests/ShopTests.swift`(SKTestSession으로 구매하면 테마가 해금되는지 확인). 통과했다.
  - 직접 배포(Developer ID) 빌드는 StoreKit 상품이 열리지 않는다. 그래서 상점에 "앱스토어 버전에서 구매할 수 있어요"라고 안내하고, 게임 내용은 모두 열려 있다.

## 배포 경로
1. **지금**: Developer ID 서명·공증 dmg를 GitHub Releases에서 배포한다(`scripts/release.sh`).
2. **Mac App Store**: 이미 샌드박스를 켰고 네트워크 권한은 로컬 MCP 서버용으로만 쓴다. 남은 일은 사람이 해야 한다.
   - App Store Connect에 앱 등록
   - "Apple Distribution" 인증서와 프로비저닝
   - 스크린샷(`docs/screenshot.png` 기반)
   - 심사 메모
3. **Steam(Mac)**: 경쟁작 대부분이 Steam에 있다. 앱스토어 다음 단계로 검토한다.

## 심사 메모 초안
- 화면 아래에 떠 있는 패널(NSPanel)이다. 클릭 통과가 기본이고, 전체화면 앱 위와 화면 공유·캡처에서는 보이지 않는다.
- 127.0.0.1에서만 여는 MCP 서버는 사용자가 직접 연결한 AI 도구가 게임 상태를 읽고 조작하는 데만 쓴다. 외부 네트워크로는 아무것도 보내지 않는다.
- 데이터를 수집하지 않는다. 진행은 샌드박스 컨테이너 안 `save.json`에만 저장한다.

## 스토어 문구 (한국어)
> 일하는 동안엔 손이 안 가고, 쉬는 시간엔 한 번 들여다볼 맛이 있는 픽셀 원정대.
> 화면 아래 띠에서 단추·클립·몽당이 책상 위 미니어처 세계를 여행해요. 반짝이 몬스터와 희귀 손님을 도감에 모으고, 영웅 특성과 원정 전술을 고르고, 서랍 심층 끝까지 내려가 보세요.
> 맥 네이티브: 클릭 통과, 전체화면·화면 공유 자동 숨김, 저전력(행군 중 30fps, 가려지면 정지), 잠자기·부재 시간 정산.
> AI 원정대장: Claude·Codex 같은 AI를 연결하면 대신 돌봐 줘요.
> 1회 구매, 광고·뽑기·장터 없음.

## 사람이 해야 하는 남은 단계 (Apple 계정 작업)
이 맥에는 App Store Connect API 키(`~/.appstoreconnect/private_keys`)가 있다. 하지만 아래 작업은 사용자 계정에 기록을 만드는 일이라 확인을 받은 뒤에만 한다.
1. App Store Connect에서 새 앱을 만든다(macOS, 번들 ID `club.lemongrove.deskexpedition`, SKU). 앱 레코드 생성은 API로 할 수 없어서 웹에서 해야 한다.
2. 위 두 상품 ID로 비소모성 인앱 구매를 등록한다(API로 가능).
3. "Apple Distribution" 인증서, Mac App Store 프로비저닝 프로필, 내보내기 설정을 준비한다(API로 가능).
4. 스크린샷, 설명(위 초안), 개인정보 "수집 안 함", 연령 등급을 입력하고 심사를 제출한다.

## 샌드박스 주의 (0.2.16~)
직접 배포판은 앱 안 AI 채팅(구독 CLI 실행) 때문에 App Sandbox를 끈다. 맥 앱스토어 빌드는 샌드박스가 필수다. 그래서 앱스토어용 빌드 설정이 따로 필요하다.
- `com.apple.security.app-sandbox: true`
- 채팅은 API 키 방식 같은 다른 경로로 바꾸거나, 앱스토어판에서 숨긴다.
