import AppKit
import Foundation

/// `DeskExpedition --mcp`: a stdio MCP server for AI clients (Claude Desktop, Claude Code, Codex CLI, Cursor…).
/// It relays newline-delimited JSON-RPC between stdin/stdout and the running app's local endpoint,
/// launching the app first if it isn't running. No UI is created in this mode.
enum MCPBridge {
    static func run() -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        let session = URLSession(configuration: .ephemeral)
        var launched = false

        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            var attempt = 0
            while true {
                switch post(Data(trimmed.utf8), session: session) {
                case .ok(let body):
                    if let body, !body.isEmpty { emit(body) }
                case .unreachable:
                    if !launched { launchApp(); launched = true }
                    if attempt < 40 { attempt += 1; Thread.sleep(forTimeInterval: 0.25); continue }
                    replyError(to: trimmed, "책상 원정대 앱에 연결할 수 없어요. 앱을 실행해 주세요.")
                case .failed(let msg):
                    replyError(to: trimmed, msg)
                }
                break
            }
        }
        exit(0)
    }

    private enum Outcome { case ok(Data?), unreachable, failed(String) }

    private static func post(_ body: Data, session: URLSession) -> Outcome {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(MCPConfig.port())/mcp")!)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(MCPConfig.token())", forHTTPHeaderField: "Authorization")
        let sem = DispatchSemaphore(value: 0)
        var outcome = Outcome.unreachable
        session.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if err != nil { outcome = .unreachable; return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200: outcome = .ok(data)
            case 202: outcome = .ok(nil)
            default: outcome = .failed("앱이 요청을 거절했어요 (HTTP \(code))")
            }
        }.resume()
        sem.wait()
        return outcome
    }

    private static func emit(_ data: Data) {
        // Keep one JSON message per line.
        let flat = (try? JSONSerialization.jsonObject(with: data))
            .flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? data
        FileHandle.standardOutput.write(flat + Data("\n".utf8))
    }

    private static func replyError(to line: String, _ message: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let id = obj["id"] else { return }   // notifications get no reply
        let err: [String: Any] = ["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": message]]
        if let d = try? JSONSerialization.data(withJSONObject: err) { emit(d) }
    }

    private static func launchApp() {
        // The bridge runs from inside the app bundle: …/DeskExpedition.app/Contents/MacOS/DeskExpedition
        let bundle = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        // The completion handler is delivered on the main queue, so spin the run loop instead of
        // blocking it (a semaphore here deadlocks).
        var done = false
        NSWorkspace.shared.openApplication(at: bundle, configuration: config) { _, _ in done = true }
        let deadline = Date().addingTimeInterval(8)
        while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }
}
