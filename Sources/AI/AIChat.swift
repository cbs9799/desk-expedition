import Foundation
import Observation

/// In-app chat with the player's own subscription AI (Claude Code or Codex CLI), run headless.
/// The CLI is started through a login shell so it sees the same PATH and login as Terminal,
/// and it gets this app's MCP server (`DeskExpedition --mcp`) so it can read and play the game.
@MainActor
@Observable
final class AIChat {
    static let shared = AIChat()

    enum Provider: String, CaseIterable, Identifiable {
        case claude, codex
        var id: String { rawValue }
        var title: String { self == .claude ? "Claude" : "Codex" }
        var command: String { rawValue }
    }

    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant, tool, error, note }
        let id = UUID()
        var role: Role
        var text: String
    }

    var provider: Provider = .claude
    private(set) var available: [Provider: Bool] = [:]
    private(set) var messages: [Message] = []
    private(set) var running = false
    private(set) var detecting = false
    @ObservationIgnored private var sessions: [Provider: String] = [:]
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var errBuffer = Data()
    @ObservationIgnored private var gotAnswer = false

    private init() {
        if let raw = UserDefaults.standard.string(forKey: "chat.provider"), let p = Provider(rawValue: raw) { provider = p }
    }

    // MARK: Detection

    func detect() {
        guard !detecting else { return }
        detecting = true
        Task.detached {
            var found: [Provider: Bool] = [:]
            for p in Provider.allCases {
                found[p] = AIChat.shell(["-lc", "command -v \(p.command) >/dev/null 2>&1"]) == 0
            }
            await MainActor.run {
                self.available = found
                self.detecting = false
                if found[self.provider] != true, let other = Provider.allCases.first(where: { found[$0] == true }) {
                    self.provider = other
                }
            }
        }
    }

    nonisolated private static func shell(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    func select(_ p: Provider) {
        provider = p
        UserDefaults.standard.set(p.rawValue, forKey: "chat.provider")
    }

    // MARK: Conversation

    func newConversation() {
        stop()
        messages = []
        sessions = [:]
    }

    func stop() {
        process?.terminate()
        process = nil
        running = false
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !running else { return }
        guard available[provider] == true else {
            messages.append(Message(role: .error, text: L10n.t("\(provider.title) CLI를 찾지 못했어요. 설치하고 로그인한 뒤 다시 시도해 주세요.")))
            return
        }
        messages.append(Message(role: .user, text: text))
        run(prompt: text)
    }

    private var workDir: URL {
        let d = AppPaths.support.appendingPathComponent("ai-chat", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private var executable: String { Bundle.main.executablePath ?? "/Applications/DeskExpedition.app/Contents/MacOS/DeskExpedition" }

    private var systemPrompt: String {
        let style = AIStyle(rawValue: GameStore.shared.settings.aiStyle) ?? .steady
        return """
        너는 macOS 게임 '책상 원정대'의 AI 원정대장이야. 사용자는 게임 창 안의 채팅으로 너와 이야기해.
        desk-expedition MCP 도구로 게임 상태를 보고(get_status 등) 사용자가 원하면 행동해(레벨업·장비·판매·지역·전술·특성·이사).
        행동할 때마다 reason에 짧은 한국어 이유를 적어. 이사(move_desk)처럼 되돌릴 수 없는 일은 사용자가 분명히 원할 때만.
        대장 성향: \(style.name) — \(style.guide)
        답은 짧고 친근하게, 한국어로(사용자가 다른 언어를 쓰면 그 언어로). 파일이나 셸은 다루지 마.
        """
    }

    private func arguments(prompt: String) -> [String] {
        let resume = sessions[provider]
        switch provider {
        case .claude:
            let cfg = workDir.appendingPathComponent("mcp.json")
            let json = #"{"mcpServers":{"desk-expedition":{"command":"\#(executable)","args":["--mcp"]}}}"#
            try? json.write(to: cfg, atomically: true, encoding: .utf8)
            var a = ["claude", "-p", prompt, "--output-format", "stream-json", "--verbose",
                     "--mcp-config", cfg.path, "--strict-mcp-config",
                     "--allowedTools", "mcp__desk-expedition__*",
                     "--append-system-prompt", systemPrompt]
            if let resume { a += ["--resume", resume] }
            return a
        case .codex:
            let mcp = ["-c", "mcp_servers.desk-expedition.command=\"\(executable)\"",
                       "-c", "mcp_servers.desk-expedition.args=[\"--mcp\"]"]
            if let resume {
                return ["codex", "exec", "--json", "--skip-git-repo-check"] + mcp + ["resume", resume, prompt]
            }
            return ["codex", "exec", "--json", "--skip-git-repo-check", "-s", "read-only"] + mcp
                + [systemPrompt + "\n\n사용자: " + prompt]
        }
    }

    private func run(prompt: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // `exec "$0" "$@"` in a login shell: the user's PATH/env, arguments passed without re-quoting.
        p.arguments = ["-lc", "exec \"$0\" \"$@\""] + arguments(prompt: prompt)
        p.currentDirectoryURL = workDir
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        buffer = Data(); errBuffer = Data(); gotAnswer = false
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.ingest(data) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.errBuffer.append(data) }
        }
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in self?.finished(status: status) }
        }
        do {
            try p.run()
            process = p
            running = true
        } catch {
            messages.append(Message(role: .error, text: error.localizedDescription))
        }
    }

    private func ingest(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(obj)
        }
    }

    private func handle(_ e: [String: Any]) {
        let type = e["type"] as? String ?? ""
        switch provider {
        case .claude:
            if let sid = e["session_id"] as? String { sessions[.claude] = sid }
            if type == "assistant", let msg = e["message"] as? [String: Any], let content = msg["content"] as? [[String: Any]] {
                for c in content {
                    if c["type"] as? String == "text", let t = c["text"] as? String, !t.isEmpty {
                        gotAnswer = true
                        messages.append(Message(role: .assistant, text: t))
                    } else if c["type"] as? String == "tool_use", let name = c["name"] as? String, name.hasPrefix("mcp__desk-expedition__") {
                        messages.append(Message(role: .tool, text: Self.toolLabel(name)))
                    }
                }
            } else if type == "result", e["is_error"] as? Bool == true {
                messages.append(Message(role: .error, text: e["result"] as? String ?? "error"))
            }
        case .codex:
            if type == "thread.started", let tid = e["thread_id"] as? String { sessions[.codex] = tid }
            if let item = e["item"] as? [String: Any] {
                let itype = item["type"] as? String ?? ""
                if type == "item.completed", itype == "agent_message", let t = item["text"] as? String, !t.isEmpty {
                    gotAnswer = true
                    messages.append(Message(role: .assistant, text: t))
                } else if type == "item.started", itype.contains("tool"), (item["server"] as? String) == "desk-expedition" {
                    let name = (item["tool"] as? String) ?? (item["name"] as? String) ?? itype
                    messages.append(Message(role: .tool, text: Self.toolLabel(name)))
                }
            }
            if type == "error" || type == "turn.failed" {
                let msg = (e["message"] as? String) ?? ((e["error"] as? [String: Any])?["message"] as? String) ?? "error"
                messages.append(Message(role: .error, text: msg))
            }
        }
    }

    private func finished(status: Int32) {
        running = false
        process = nil
        if !buffer.isEmpty { ingest(Data([0x0A])) }
        if !gotAnswer {
            let err = String(decoding: errBuffer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = err.isEmpty ? L10n.t("답을 받지 못했어요 (종료 코드 \(status)). CLI 로그인 상태를 확인해 주세요.") : String(err.suffix(400))
            if status != 15 { messages.append(Message(role: .error, text: hint)) }
        }
    }

    /// "mcp__desk-expedition__level_up" → "레벨업" etc.
    static func toolLabel(_ raw: String) -> String {
        let name = raw.components(separatedBy: "__").last ?? raw
        let ko: [String: String] = [
            "get_status": "상태 확인", "get_bag": "가방 보기", "get_dex": "도감 보기", "get_journal": "일지 보기",
            "level_up": "레벨업", "equip": "장착", "auto_equip": "최적 장착", "sell_item": "판매", "sell_all": "일괄 판매",
            "select_region": "지역 이동", "move_desk": "이사", "set_nickname": "이름 변경", "set_accessory": "꾸미기",
            "choose_trait": "특성 선택", "set_tactic": "전술 변경", "exchange_shards": "조각 교환", "say": "한마디",
            "upgrade_all": "한 번에 정비", "set_auto_tidy": "자동 정리 설정",
        ]
        return L10n.t(ko[name] ?? name)
    }
}
