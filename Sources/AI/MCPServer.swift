import Foundation
import Network

/// Shared connection details, written into the app's sandbox container so the stdio bridge
/// (the same executable run with `--mcp`, hence the same container) can find the running app.
enum MCPConfig {
    static let defaultPort: UInt16 = 47213

    static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeskExpedition", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static var tokenURL: URL { dir.appendingPathComponent("mcp-token") }
    static var portURL: URL { dir.appendingPathComponent("mcp-port") }

    /// Random bearer token, created once and kept private to this user (0600).
    static func token() -> String {
        if let t = try? String(contentsOf: tokenURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           t.count >= 32 { return t }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let t = bytes.map { String(format: "%02x", $0) }.joined()
        try? t.write(to: tokenURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
        return t
    }

    static func port() -> UInt16 {
        (try? String(contentsOf: portURL, encoding: .utf8)).flatMap { UInt16($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            ?? defaultPort
    }
}

/// Minimal MCP "Streamable HTTP" endpoint on 127.0.0.1 (POST /mcp, JSON responses).
/// Loopback only, bearer-token protected, and browser Origins are rejected (DNS-rebinding guard).
@MainActor
final class MCPServer {
    private var listener: NWListener?
    private let handler: MCPHandler
    private let token = MCPConfig.token()
    private(set) var port: UInt16 = 0

    init(store: GameStore) { handler = MCPHandler(store: store) }

    func start() {
        for candidate in [MCPConfig.defaultPort, MCPConfig.defaultPort + 1, MCPConfig.defaultPort + 2] {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: candidate)!)
            params.allowLocalEndpointReuse = true
            guard let l = try? NWListener(using: params) else { continue }
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            l.start(queue: .main)
            listener = l
            port = candidate
            try? String(candidate).write(to: MCPConfig.portURL, atomically: true, encoding: .utf8)
            return
        }
        NSLog("DeskExpedition MCP: no free port")
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, err in
            Task { @MainActor in
                guard let self else { return }
                var buf = buffer
                if let data { buf.append(data) }
                if let req = HTTPRequest(buf) {
                    self.respond(conn, req)
                } else if done || err != nil || buf.count > 4 << 20 {
                    conn.cancel()
                } else {
                    self.receive(conn, buffer: buf)
                }
            }
        }
    }

    private func respond(_ conn: NWConnection, _ req: HTTPRequest) {
        func send(_ status: String, _ body: Data = Data(), type: String = "application/json") {
            var head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            if body.isEmpty && !status.hasPrefix("2") { head = head.replacingOccurrences(of: type, with: "text/plain") }
            conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
        }
        if let origin = req.headers["origin"], !(origin.contains("127.0.0.1") || origin.contains("localhost")) {
            return send("403 Forbidden")
        }
        if req.method == "GET" && req.path == "/health" {
            return send("200 OK", Data(#"{"ok":true,"app":"desk-expedition"}"#.utf8))
        }
        guard req.path.hasPrefix("/mcp") else { return send("404 Not Found") }
        guard req.headers["authorization"] == "Bearer \(token)" else { return send("401 Unauthorized") }
        guard req.method == "POST" else { return send("405 Method Not Allowed") }

        guard let obj = try? JSONSerialization.jsonObject(with: req.body) else {
            let err: [String: Any] = ["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]]
            return send("400 Bad Request", (try? JSONSerialization.data(withJSONObject: err)) ?? Data())
        }
        if let batch = obj as? [[String: Any]] {
            let out = batch.compactMap { handler.handle($0) }
            if out.isEmpty { return send("202 Accepted") }
            return send("200 OK", (try? JSONSerialization.data(withJSONObject: out)) ?? Data())
        }
        guard let msg = obj as? [String: Any] else { return send("400 Bad Request") }
        guard let out = handler.handle(msg) else { return send("202 Accepted") }
        send("200 OK", (try? JSONSerialization.data(withJSONObject: out)) ?? Data())
    }
}

/// Just enough HTTP/1.1 parsing for one request per connection.
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(_ data: Data) {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<sep.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return nil }
        var h: [String: String] = [:]
        for l in lines {
            guard let c = l.firstIndex(of: ":") else { continue }
            h[l[..<c].lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(h["content-length"] ?? "0") ?? 0
        let body = data[sep.upperBound...]
        guard body.count >= length else { return nil }
        method = String(first[0]); path = String(first[1]); headers = h
        self.body = Data(body.prefix(length))
    }
}
