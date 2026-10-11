import Foundation
import Network

/// A tiny HTTP API on 127.0.0.1:8742 for the `hodl` CLI, `hodl-run` heartbeats, and agent hooks.
/// Loopback only. Requests that change anything need an `X-HODL` header, which browsers can’t send
/// cross-site without a preflight HODL never approves.
@MainActor
final class ControlServer {
    static let shared = ControlServer()
    static let port: UInt16 = 8742

    private var listener: NWListener?
    private(set) var isListening = false

    private init() {}

    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.stateUpdateHandler = { state in
            let ready: Bool
            if case .ready = state { ready = true } else { ready = false }
            Task { @MainActor in ControlServer.shared.isListening = ready }
        }
        listener.newConnectionHandler = { connection in
            ControlServer.serve(connection)
        }
        listener.start(queue: .global(qos: .utility))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
    }

    nonisolated private static func serve(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
            guard let data, let request = Request(data) else {
                return reply(connection, status: 400, body: ["error": "bad request"])
            }
            Task { @MainActor in
                let (status, body) = route(request)
                reply(connection, status: status, body: body)
            }
        }
    }

    private static func route(_ request: Request) -> (Int, [String: Any]) {
        let host = request.headers["host"]?.split(separator: ":").first.map(String.init) ?? "127.0.0.1"
        guard ["127.0.0.1", "localhost"].contains(host) else { return (403, ["error": "loopback only"]) }
        let name = request.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let command = name.isEmpty ? "status" : name.replacingOccurrences(of: "/", with: "-")
        if command != "status" {
            guard request.method == "POST", request.headers["x-hodl"] != nil else {
                return (403, ["error": "send POST with an X-HODL header"])
            }
        }
        guard let result = Commands.run(command, request.query, source: request.query["source"] ?? "cli") else {
            return (404, ["error": "unknown command \(command)"])
        }
        return (200, result)
    }

    nonisolated private static func reply(_ connection: NWConnection, status: Int, body: [String: Any]) {
        let json = (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        let phrase = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found"][status] ?? "OK"
        var response = Data("HTTP/1.1 \(status) \(phrase)\r\nContent-Type: application/json\r\nContent-Length: \(json.count + 1)\r\nConnection: close\r\n\r\n".utf8)
        response.append(json)
        response.append(0x0A)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

private struct Request: Sendable {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]

    init?(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2, let components = URLComponents(string: String(parts[1])) else { return nil }
        method = String(parts[0]).uppercased()
        path = components.path
        query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        self.headers = headers
    }
}
