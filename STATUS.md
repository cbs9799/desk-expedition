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
- **그래픽 리뉴얼 (v0.2 작업분, `ART.md`)**: 세계관을 "책상 위 미니어처 세계"로 바꿈. 영웅 단추(골무 투구 전사)·클립(포스트잇 궁수)·몽당(연필 모자 마법사), 지역 5곳(공책 들판 → 모니터 성채)과 몬스터 15종·보스 5종.
  - 아트: Codex CLI 이미지 생성(`scripts/art/gen.py`, 프롬프트는 `specs.py`) → `scripts/art/process.py`가 배경 제거·축소·팔레트 정리·발 기준 정렬 → `Resources/Art/`. 원본(`art/raw/`)은 커밋하지 않음.
  - 띠: 높이 100pt, SpriteKit으로 교체. 배경 2겹 패럴랙스 + 소품이 흐르고, 웨이브 사이 2.4초 동안 파티가 행군(걷기·점프), 적과 붙으면 멈춰 싸움. 몬스터는 엔진 위치를 부드럽게 따라감.
  - VFX(고해상도, 빛 더하기): 칼 궤적+섬광+불꽃, 화살 빛 꼬리+충격 고리, 화염구 충전→꼬리→폭발(링·불씨·연기), 스킬 오라, 치명타 금색 숫자, 히트스톱, 띠 안 흔들림, 처치 시 금빛이 HUD로 날아감, 전설 드롭 빛기둥, 레벨업 기둥.
  - 애착: 본부에서 이름 짓기, 머리 꾸미기 6종, 커서를 영웅 위에 올리면 손 흔들고 하트·이름 표시, 클릭 통과를 끄면 클릭해서 점프시키기.
  - 확인 도구: `--frames <dir>`로 띠를 0.1초 간격 PNG로 오프스크린 렌더링.
- **장기 목표 (0.2.2)**: 책상 도감 60칸(몬스터 20종 × 일반/반짝이 1/400/왕관 1/50, 보스는 일반·반짝이, 희귀 손님 5종), 칸마다 골드 +1%. 원정 일지 33장(영웅 이름이 들어간 짧은 일기). 서랍 심층(6번째 지역, 끝없는 층, 10층마다 보스의 메아리). 트로피 6종이 띠 풍경에 섞여 지나감. 이름 있는 전설 장비 20종(전설의 35%), 전설 무기 장착 시 손에 금빛. 이사(환생): 추억 조각 1개당 공격·골드 +5%, 책상 테마 4종(풍경 색조), 도감·일지·트로피·이름은 유지. 본부에 원정대/도감/일지/기록 탭.
- **배경 이음매**: 배경 띠를 반복할 때 양 끝을 가장 덜 달라지는 경로로 잇도록(이미지 퀼팅) 바꾸고, 공책·연필꽂이·서랍 배경은 가장자리에 큰 물체가 없도록 다시 생성.
- **공증 배포 준비**: `scripts/package.sh`가 `DEVELOPER_ID`와 공증 자격 증명(`NOTARY_PROFILE` 또는 API 키)이 있으면 서명→공증→스테이플링. GitHub Actions는 시크릿(MACOS_CERT_P12, MACOS_CERT_PASSWORD, DEVELOPER_ID, NOTARY_KEY_P8, NOTARY_KEY_ID, NOTARY_ISSUER)이 있으면 같은 경로로 감.
- **테스트** 11개(기존 6개 + 도감·변종, 희귀 손님 스폰, 심층 층 기록, 이사, 예전 세이브 호환)(전투 진행, 보스 처치·지역 해금, 오프라인 상한·속도, 가방 가득 참, 등급 스케일, 장착·일괄 판매): 모두 통과.
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

## 다운로드 / 배포
- 받는 곳: GitHub 저장소의 **Releases** 페이지 → `DeskExpedition-<버전>.dmg`(또는 `.zip`). 설치 안내는 `.github/release-notes.md`.
- 로컬에서 배포 파일 만들기: `scripts/package.sh [버전]` → `dist/`에 유니버설(arm64+x86_64) `.dmg`, `.zip`, `SHA256SUMS.txt`.
- 자동 릴리스: `git tag v0.1.0 && git push origin v0.1.0` 하면 `.github/workflows/release.yml`이 테스트 → 패키징 → Releases 업로드.
- 아직 ad-hoc 서명이라 받은 사람은 첫 실행 때 "그래도 열기"를 눌러야 합니다. Developer ID 서명과 공증을 붙이면 경고가 사라집니다.

## 남은 일
- **아트 다듬기**: AI 생성 시트라 프레임 사이 미세한 흔들림이 있음. 마음에 안 드는 시트는 `gen.py <키>`로 다시 뽑기. 스킬 전용 프레임(지금은 공격 프레임 재사용)과 달리기 전용 프레임 추가 후보.
- **실화면 확인**: 이번 작업은 오프스크린 렌더링으로만 확인함(작업 중 화면이 잠겨 실제 띠 캡처 불가). 실제 맥에서 투명도·커서 반응·CPU 사용량 확인 필요.
- **VFX 강도 설정**: 지금은 "화려함" 고정. 나중에 보통/차분함 옵션.
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
