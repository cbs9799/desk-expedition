# STATUS — 책상 원정대 (DeskExpedition) MVP

![screenshot](docs/screenshot.png)

## 완료한 것
- **MVP.md**: 기회 한 줄, 핵심 기능 5개, 이번에 뺀 것, 화면 목록, 수익 모델.
- **macOS 앱** (SwiftUI + AppKit, macOS 14+, 서드파티 의존성 없음, 번들 ID `club.lemongrove.deskexpedition`, App Sandbox 켬)
  - **원정 띠**: Dock 바로 위에 뜨는 투명 패널(920×80). 모든 데스크톱 공간에 표시되고 전체화면 앱 위에는 뜨지 않음. 클릭 통과 토글, 왼쪽/가운데/오른쪽 위치, 모니터 선택(2대 이상일 때).
  - **자동 전투**: 전사(방패 강타)·궁수(연사)·마법사(화염 폭발). 웨이브 10개마다 보스가 나오고, 보스를 잡으면 다음 지역이 열림(지역 5곳). 전멸하면 3웨이브 후퇴. 피해 숫자, 투사체, 피격 깜빡임 연출.
  - **장비**: 4등급(일반/고급/희귀/전설) 무기·방어구 드롭, 가방 24칸, 장착/교체/해제, 판매, 등급별 일괄 판매(업그레이드 장비는 남김), 최적 장착, 골드로 레벨업.
  - **메뉴바 팝오버**: 지역·웨이브, 파티 체력, 골드, 가방, 띠 설정, 원정 본부 열기.
  - **오프라인 정산**: 2분 넘게 자리를 비우면 최대 12시간을 0.5초 단위로 시뮬레이션하고 본부 배너와 띠 배너로 결과를 알림.
  - **알림**: 가방이 가득 차면 로컬 알림 1회(이후 새 전리품은 절반 값에 자동 판매).
  - **저전력**: 띠가 보일 때 10Hz, 가려지거나 숨겨지면 2Hz로 돌고 이펙트 계산을 생략.
  - **저장**: Application Support/DeskExpedition/save.json(샌드박스 컨테이너 안). 30초마다, 종료할 때 저장.
- **테스트** 6개(전투 진행, 보스 처치·지역 해금, 오프라인 상한·속도, 가방 가득 참, 등급 스케일, 장착·일괄 판매): 모두 통과.
- **docs/screenshot.png**: 앱의 `--snapshot` 모드로 실제 SwiftUI 화면(띠·메뉴·본부)을 정해진 게임 상태로 렌더링한 합성 이미지.

## 실행 방법
```bash
xcodegen generate
xcodebuild -project DeskExpedition.xcodeproj -scheme DeskExpedition -derivedDataPath build build
open build/Build/Products/Debug/DeskExpedition.app          # 메뉴바 방패 아이콘 + 화면 아래 띠
xcodebuild -project DeskExpedition.xcodeproj -scheme DeskExpedition -derivedDataPath build test
# 스크린샷 다시 찍기 (샌드박스 때문에 컨테이너 tmp에 저장되고 그 경로를 출력)
build/Build/Products/Debug/DeskExpedition.app/Contents/MacOS/DeskExpedition --snapshot "$PWD/docs/screenshot.png"
```
- 실행 인자 `--open-hq`를 주면 시작할 때 원정 본부 창을 엽니다.
- 진행 초기화: `~/Library/Containers/club.lemongrove.deskexpedition/Data/Library/Application Support/DeskExpedition/save.json` 삭제.
- iOS가 아니라 macOS 앱이라 시뮬레이터 대신 macOS 빌드로 확인했습니다.

## 남은 일
- **아트**: 지금은 코드로 그린 임시 픽셀 스프라이트입니다. 상업 라이선스 픽셀 에셋(영웅 3종 애니메이션, 지역 배경, 몬스터 15종, 보스 5종)으로 바꿔야 합니다.
- **밸런스**: 레벨·골드·지역 배율을 실제 플레이로 조정해야 합니다(현재: 지역마다 적 체력 ×2.6, 레벨마다 스탯 ×1.1, 레벨업 비용 ×1.17).
- **빠진 기능(MVP.md 참고)**: 스킬 트리, 오늘의 던전과 주간 보스, 화면 공유 중 자동 숨김(ScreenCaptureKit 또는 CGWindow 감지), 사운드(기본 끔), 업적.
- **UX**: 첫 실행 안내, 영어 현지화(지금은 한국어만), 로그인할 때 자동 실행(SMAppService), 마우스를 올리면 띠를 흐리게 하는 옵션.
- **품질**: 장시간 실행 CPU·메모리 측정(Instruments), 멀티 모니터와 Dock 위치(왼쪽/오른쪽/자동 숨김) 대응 검증.

## 출시 전에 사람이 해야 할 것
- Apple Developer 팀 서명 설정(지금은 ad-hoc `-` 서명), App Store Connect 앱 등록, 유료 앱 가격($4.99 / ₩6,600) 설정.
- 최종 이름과 상표 확인(“책상 원정대” 가칭), 레몬 데스크와 시리즈로 묶을지 결정.
- 상업 라이선스 에셋 구매와 교체, 앱 아이콘 제작(지금은 없음).
- 앱 심사용 스크린샷·설명·개인정보 처리 방침(수집 없음) 작성, 연령 등급 12+ 설문.
- Traymon World(11/25 출시)와 Desktop Heroes를 직접 해 보고 차별점(맥 네이티브·한국어·1회 구매)을 스토어 문구에 반영.
- 실제 맥 여러 대에서 전체화면 숨김, 알림 권한, 샌드박스 저장 동작 확인.
