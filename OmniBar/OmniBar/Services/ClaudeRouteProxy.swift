//
//  ClaudeRouteProxy.swift
//  OmniBar
//
//  v2.1：Claude Desktop 3P 本地路由代理（模型映射模式）。
//  桌面端 3P 模式要求模型名为 claude-sonnet-*/claude-opus-*/claude-haiku-*/claude-fable-* 角色 ID，
//  而 omniroute 网关只认真实模型。本代理监听 127.0.0.1:16931：
//  - POST /v1/messages：把请求体 model 从角色 ID 重写为真实网关模型后转发到 omniroute；
//  - GET  /v1/models ：返回 Anthropic 原生格式 {"data":[...]}（含 4 个角色模型）；
//  - 其余请求透明转发。SSE 流式响应逐块透传。
//

import Foundation
import Network

/// Claude Desktop 3P 路由代理：NWListener 起本地 HTTP 服务，模型重写 + 透明转发。
final class ClaudeRouteProxy {
    static let defaultPort: UInt16 = 16931

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data?
    }

    /// 上游请求需跳过的逐跳头（URLSession 自行管理这些）。
    private static let hopByHopHeaders: Set<String> = [
        "host", "connection", "keep-alive", "content-length", "transfer-encoding",
        "accept-encoding", "proxy-connection", "te", "trailer", "upgrade",
    ]

    private let settings: AppSettings
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.omnibar.claude-route-proxy")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    /// SSE 长连接：不设请求超时，禁用缓存。
    private let streamingSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0
        config.timeoutIntervalForResource = 0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    var isRunning: Bool { listener != nil }

    init(settings: AppSettings, port: UInt16 = ClaudeRouteProxy.defaultPort) {
        self.settings = settings
        self.port = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(integerLiteral: UInt16(ClaudeRouteProxy.defaultPort))
    }

    // MARK: - Lifecycle

    func start() throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.listener = nil
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handleNewConnection(conn)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for conn in connections.values { conn.cancel() }
        connections.removeAll()
    }

    // MARK: - Connection handling

    private func handleNewConnection(_ conn: NWConnection) {
        connections[ObjectIdentifier(conn)] = conn
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.close(conn)
                return
            }
            var buf = buffer
            if let data { buf.append(data) }
            if isComplete {
                if let req = self.parseRequest(buf) {
                    self.dispatch(req, on: conn)
                } else {
                    self.close(conn)
                }
                return
            }
            if let req = self.parseRequest(buf) {
                self.dispatch(req, on: conn)
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private func close(_ conn: NWConnection) {
        queue.async {
            self.connections.removeValue(forKey: ObjectIdentifier(conn))
            conn.cancel()
        }
    }

    // MARK: - HTTP parsing

    /// 从累积缓冲解析一个完整 HTTP/1.1 请求；不完整返回 nil。
    private func parseRequest(_ buffer: Data) -> HTTPRequest? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer[..<headerEnd.lowerBound]
        guard let headerText = String(data: Data(headerData), encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let bodyStart = headerEnd.upperBound
        if let lenText = headers["Content-Length"] ?? headers["content-length"],
           let len = Int(lenText) {
            let lower = bodyStart + len
            guard buffer.count >= lower else { return nil }
            let body = Data(buffer[bodyStart..<lower])
            return HTTPRequest(method: method, path: path, headers: headers, body: body.isEmpty ? nil : body)
        }
        return HTTPRequest(method: method, path: path, headers: headers, body: nil)
    }

    // MARK: - Routing

    private func dispatch(_ request: HTTPRequest, on conn: NWConnection) {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        if request.method.uppercased() == "GET", path == "/v1/models" {
            handleModels(on: conn)
        } else {
            let rewrite = request.method.uppercased() == "POST" && path == "/v1/messages"
            forward(request, on: conn, rewriteModel: rewrite)
        }
    }

    // MARK: - /v1/models → Anthropic 原生格式

    private func handleModels(on conn: NWConnection) {
        let payload = anthropicModelsPayload()
        queue.async {
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
            conn.send(content: Data(head.utf8) + payload, completion: .contentProcessed { [weak self] _ in
                self?.close(conn)
            })
        }
    }

    /// 构造 Anthropic 原生 /v1/models 响应体（含 4 个角色模型）。
    private func anthropicModelsPayload() -> Data {
        var data: [[String: Any]] = []
        for role in ClaudeRole.allCases {
            let real = resolvedModel(for: role)
            let displayName = role.title + (real.isEmpty ? "" : " · \(shortID(real))")
            data.append([
                "type": "model",
                "id": role.roleModelID,
                "display_name": displayName,
                "created_at": "2025-01-01T00:00:00Z",
            ])
        }
        let obj: [String: Any] = ["data": data, "has_more": false]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{\"data\":[]}".utf8)
    }

    // MARK: - Forwarding (透明转发 + 模型重写)

    private func forward(_ request: HTTPRequest, on conn: NWConnection, rewriteModel: Bool) {
        guard let url = buildUpstreamURL(request.path) else {
            sendError(conn, 500)
            return
        }
        var upstream = URLRequest(url: url)
        upstream.httpMethod = request.method
        for (key, value) in request.headers where !Self.hopByHopHeaders.contains(key.lowercased()) {
            upstream.setValue(value, forHTTPHeaderField: key)
        }
        // 兜底注入网关 API Key（桌面端可能不带 Authorization 请求 /v1/models）
        if upstream.value(forHTTPHeaderField: "Authorization") == nil, !settings.omnirouteAPIKey.isEmpty {
            upstream.setValue("Bearer \(settings.omnirouteAPIKey)", forHTTPHeaderField: "Authorization")
        }
        if let body = request.body {
            upstream.httpBody = rewriteModel ? Self.rewrittenBody(body, resolver: { [weak self] role in
                self?.resolvedModel(for: role) ?? ""
            }) : body
        }

        let session = streamingSession
        let queue = self.queue
        queue.async {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let (bytes, response) = try await session.bytes(for: upstream)
                    guard let http = response as? HTTPURLResponse else {
                        self.sendError(conn, 502)
                        return
                    }
                    self.sendHead(http, on: conn)
                    var buffer = Data()
                    buffer.reserveCapacity(32 * 1024)
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 32 * 1024 {
                            let chunk = buffer
                            buffer = Data()
                            queue.async {
                                conn.send(content: chunk, completion: .contentProcessed { _ in })
                            }
                        }
                    }
                    if !buffer.isEmpty {
                        let chunk = buffer
                        queue.async {
                            conn.send(content: chunk, completion: .contentProcessed { _ in })
                        }
                    }
                    queue.async { self.close(conn) }
                } catch {
                    self.sendError(conn, 502)
                }
            }
        }
    }

    /// 请求体重写：model 字段命中角色前缀时替换为真实网关模型。未命中/非角色模型原样返回。
    static func rewrittenBody(_ body: Data, resolver: (ClaudeRole) -> String) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let model = json["model"] as? String,
              let role = ClaudeRole.allCases.first(where: { model.hasPrefix($0.modelPrefix) }) else {
            return body
        }
        let real = resolver(role)
        guard real != model, !real.isEmpty else { return body }
        var newJSON = json
        newJSON["model"] = real
        return (try? JSONSerialization.data(withJSONObject: newJSON)) ?? body
    }

    /// 角色的真实网关模型：优先逐角色设置，其次跟随 linkClaudeModel，最后兜底。
    private func resolvedModel(for role: ClaudeRole) -> String {
        let stored: String
        switch role {
        case .sonnet: stored = settings.claudeDesktopSonnetModel
        case .opus: stored = settings.claudeDesktopOpusModel
        case .haiku: stored = settings.claudeDesktopHaikuModel
        case .fable: stored = settings.claudeDesktopFableModel
        }
        if !stored.isEmpty { return stored }
        if !settings.linkClaudeModel.isEmpty { return settings.linkClaudeModel }
        return "auto/best-fast"
    }

    private func shortID(_ id: String) -> String {
        guard let slash = id.lastIndex(of: "/") else { return id }
        return String(id[id.index(after: slash)...])
    }

    private func buildUpstreamURL(_ path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = settings.omniroutePort
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components.path = String(parts[0])
        if parts.count > 1 {
            let queryItems = parts[1].split(separator: "&", omittingEmptySubsequences: false).compactMap { pair -> URLQueryItem? in
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let key = kv.first.map(String.init) else { return nil }
                let value = kv.count > 1 ? String(kv[1]) : ""
                return URLQueryItem(name: key, value: value)
            }
            components.queryItems = queryItems
        }
        return components.url
    }

    // MARK: - Response writer

    private func sendHead(_ http: HTTPURLResponse, on conn: NWConnection) {
        queue.async {
            var head = "HTTP/1.1 \(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))\r\n"
            for (key, value) in http.allHeaderFields {
                guard let k = key as? String, let v = value as? String else { continue }
                let lower = k.lowercased()
                if ["content-length", "transfer-encoding", "connection", "keep-alive", "content-encoding"].contains(lower) { continue }
                head += "\(k): \(v)\r\n"
            }
            head += "Connection: close\r\n\r\n"
            conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        }
    }

    private func sendError(_ conn: NWConnection, _ code: Int) {
        let body = Data("proxy error (\(code))".utf8)
        queue.async {
            let head = "HTTP/1.1 \(code) \(HTTPURLResponse.localizedString(forStatusCode: code))\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
            conn.send(content: body, completion: .contentProcessed { [weak self] _ in
                self?.close(conn)
            })
        }
    }
}
