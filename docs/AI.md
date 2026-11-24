# AI 원정대장 — 구독 AI가 책상 원정대를 플레이하게 하기

책상 원정대는 앱 안에 **MCP(Model Context Protocol) 서버**를 갖고 있습니다. Claude·Codex처럼 이미 구독 중인 AI를
연결하면, AI가 게임 상태를 읽고 레벨업·장비·가방 정리·지역 이동·이사를 직접 합니다. AI가 한 일과 이유는
원정 띠에 `🤖`로, 메뉴바의 "AI 원정대장" 칸에 기록으로 남습니다.

## 연결 (한 번만)
메뉴바 방패 아이콘 → **AI 원정대장** → 쓰는 AI 이름의 버튼을 누르면 설정이 복사됩니다.

| AI | 붙여 넣을 곳 |
|---|---|
| Claude Code | 터미널에 그대로 실행 (`claude mcp add … -- …/DeskExpedition --mcp`) |
| Claude Desktop | 설정 → 개발자 → 설정 편집 → `claude_desktop_config.json`의 `"mcpServers": { … }` 안 |
| Codex CLI | `~/.codex/config.toml` 맨 아래 |
| Cursor 등 | stdio MCP: 명령 `…/DeskExpedition.app/Contents/MacOS/DeskExpedition`, 인자 `--mcp` |

그다음 AI에게 **"책상 원정대 돌봐 줘"** 라고 하거나, MCP 프롬프트 **play**를 고르면 됩니다.

## 알아서 계속 플레이하게 하기
메뉴의 **자동 플레이** 버튼이 복사하는 명령을 터미널에서 한 번 실행하면, 로그인해 있는 동안 30분마다 AI가 원정대를 돌봅니다.
```bash
bash "/Applications/DeskExpedition.app/Contents/Resources/ai-autoplay.sh" install claude 30   # 또는 codex
bash "/Applications/DeskExpedition.app/Contents/Resources/ai-autoplay.sh" status
bash "/Applications/DeskExpedition.app/Contents/Resources/ai-autoplay.sh" uninstall
```
- 실행할 때마다 구독 AI 사용량을 조금 씁니다. 간격(분)을 늘리면 덜 씁니다.
- 로그: `~/Library/Logs/DeskExpedition-autoplay.log`

## 도구
| 도구 | 하는 일 |
|---|---|
| `get_status` | 골드, 영웅(레벨·체력·공격력·장비·레벨업 비용), 지역·웨이브, 가방 요약, 도감·일지·기록, 최근 사건 |
| `get_bag` / `get_dex` / `get_journal` | 가방 장비 목록(업그레이드 대상 포함) / 도감 / 일지 |
| `level_up` | 영웅 레벨업(여러 번) |
| `equip`, `auto_equip` | 장비 장착 / 최적 장착 |
| `sell_item`, `sell_all` | 판매 / 등급 이하 일괄 판매(업그레이드는 남김) |
| `select_region` | 열린 지역으로 이동(5 = 서랍 심층) |
| `move_desk` | 이사(환생), `confirm: true` 필요 |
| `set_nickname`, `set_accessory` | 이름·꾸미기 (사용자가 원할 때만) |
| `say` | 띠에 한마디 |

모든 행동 도구는 `reason`(짧은 한국어 이유)을 받아 띠에 보여 줍니다.

## 보안
- 서버는 `127.0.0.1`(이 맥 안)에서만 열리고, 앱 컨테이너에 저장된 무작위 토큰이 있어야 응답합니다. stdio 브리지(`--mcp`)는 같은 앱이라 토큰을 자동으로 씁니다.
- 브라우저에서 오는 요청(다른 Origin)은 거절합니다.
- AI가 할 수 있는 일은 게임 안 행동뿐입니다. 파일·네트워크 등 맥의 다른 것에는 접근하지 않습니다.
