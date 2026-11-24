#!/bin/bash
# 책상 원정대 — 구독 중인 AI(Claude Code 또는 Codex CLI)가 주기적으로 원정대를 돌보게 한다.
#   ai-autoplay.sh run [claude|codex]                 지금 한 번 돌보기
#   ai-autoplay.sh install [claude|codex] [분=30]      로그인 동안 N분마다 자동 실행 (launchd)
#   ai-autoplay.sh uninstall                          자동 실행 끄기
#   ai-autoplay.sh status                             설치 상태와 최근 로그
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
EXE="$(cd "$HERE/../MacOS" 2>/dev/null && pwd)/DeskExpedition"
[[ -x "$EXE" ]] || EXE="/Applications/DeskExpedition.app/Contents/MacOS/DeskExpedition"
LABEL="club.lemongrove.deskexpedition.autoplay"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/DeskExpedition-autoplay.log"
PROMPT="책상 원정대 MCP 서버(desk-expedition)의 play 프롬프트 지침대로 원정대를 돌봐 줘: get_status로 확인하고, 필요한 레벨업·장비·가방 정리·지역 이동을 하고(행동마다 짧은 한국어 reason), 이사(move_desk)는 최고층이 한참 정체됐을 때만. 마지막에 한두 문장으로 요약."

run() {
  local ai="${1:-claude}"
  echo "=== $(date '+%F %T') $ai ==="
  case "$ai" in
    claude)
      local cfg; cfg="$(mktemp -t de-mcp)"
      printf '{"mcpServers":{"desk-expedition":{"command":"%s","args":["--mcp"]}}}' "$EXE" > "$cfg"
      claude -p "$PROMPT" --mcp-config "$cfg" --strict-mcp-config \
        --allowedTools "mcp__desk-expedition__*" --max-turns 30 < /dev/null
      rm -f "$cfg" ;;
    codex)
      codex exec --skip-git-repo-check \
        -c "mcp_servers.desk-expedition.command=\"$EXE\"" -c 'mcp_servers.desk-expedition.args=["--mcp"]' \
        "$PROMPT" < /dev/null ;;
    *) echo "claude 또는 codex"; exit 2 ;;
  esac
}

case "${1:-}" in
  run) run "${2:-claude}" ;;
  install)
    ai="${2:-claude}"; minutes="${3:-30}"
    command -v "$ai" >/dev/null || { echo "$ai CLI가 없어요. 먼저 설치·로그인하세요."; exit 1; }
    mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
    cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$HERE/ai-autoplay.sh</string><string>run</string><string>$ai</string></array>
  <key>StartInterval</key><integer>$((minutes * 60))</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
PL
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "자동 플레이 켜짐: $ai, ${minutes}분마다. 로그: $LOG" ;;
  uninstall)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"; echo "자동 플레이 꺼짐" ;;
  status)
    [[ -f "$PLIST" ]] && echo "설치됨: $PLIST" || echo "설치 안 됨"
    [[ -f "$LOG" ]] && tail -n 20 "$LOG" || true ;;
  *) sed -n '2,7p' "$0"; exit 2 ;;
esac
