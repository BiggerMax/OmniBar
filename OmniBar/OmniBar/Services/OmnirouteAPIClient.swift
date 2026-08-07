//
//  OmnirouteAPIClient.swift
//  OmniBar
//
//  与 Omniroute REST API 通信的客户端
//

import Foundation
import CryptoKit

enum OmnirouteAPIError: Error, LocalizedError {
    /// HTTP 401 / 403 鉴权失败
    case unauthorized
    case httpError(Int)
    case transport(Error)
    /// 网关没有对应的端点
    case endpointUnavailable

    /// 提供可读描述，避免默认的 "The operation couldn't be completed…" 掩盖真实原因
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "API 鉴权失败（401/403）"
        case .httpError(let code):
            return "网关返回错误状态码 \(code)"
        case .transport(let error):
            return "无法连接到网关：\(error.localizedDescription)"
        case .endpointUnavailable:
            return "网关不支持该数据接口"
        }
    }
}

final class OmnirouteAPIClient {
    private var settings: AppSettings
    private let session: URLSession
    private var port: Int {
        settings.omniroutePort
    }
    private var apiKey: String {
        settings.omnirouteAPIKey
    }

    convenience init(settings: AppSettings) {
        // 本地 API 轮询需要实时数据，且默认配置会挂载进程级 URLCache.shared（内存+磁盘常驻数 MB）。
        // 用 ephemeral 完全禁用缓存：语义更正确（每次拉最新），也避免轮询响应滞留内存。
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        self.init(settings: settings, session: URLSession(configuration: config))
    }

    /// 可注入自定义 URLSession（供测试注入 mock session 使用）。
    init(settings: AppSettings, session: URLSession) {
        self.settings = settings
        self.session = session
    }

    func refreshSettings() {
        // 端口或 API Key 变化后由调用方传入
    }

    // MARK: - Generic Request

    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil, includeCliToken: Bool = false) async throws -> T {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "localhost"
        components.port = port
        // 拆分 path 与 query：path 含 "?" 时必须放到 queryItems，
        // 否则 URLComponents 会把 "?" 百分号编码（%3F），导致 404。
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components.path = String(parts[0])
        if parts.count > 1 {
            let query = parts[1]
            components.queryItems = query
                .split(separator: "&", omittingEmptySubsequences: false)
                .compactMap { pair in
                    let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard let key = kv.first.map(String.init) else { return nil }
                    let value = kv.count > 1 ? String(kv[1]) : ""
                    return URLQueryItem(name: key, value: value)
                }
        }

        guard let url = components.url else {
            throw OmnirouteAPIError.transport(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if includeCliToken, let token = cliToken {
            request.setValue(token, forHTTPHeaderField: "x-omniroute-cli-token")
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OmnirouteAPIError.transport(URLError(.badServerResponse))
        }
        // 401 未提供 token；403 token 无效（omniroute 对无效 token 返回 403）
        if http.statusCode == 401 || http.statusCode == 403 {
            throw OmnirouteAPIError.unauthorized
        }
        if http.statusCode == 404 || http.statusCode == 405 {
            throw OmnirouteAPIError.endpointUnavailable
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OmnirouteAPIError.httpError(http.statusCode)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    /// 发送请求并验证 2xx，不解析响应体（用于 PATCH/DELETE 等 204 端点）。
    @discardableResult
    func requestVoid(_ path: String, method: String = "GET", body: Data? = nil, includeCliToken: Bool = false) async throws -> Void {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "localhost"
        components.port = port
        components.path = path

        guard let url = components.url else {
            throw OmnirouteAPIError.transport(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if includeCliToken, let token = cliToken {
            request.setValue(token, forHTTPHeaderField: "x-omniroute-cli-token")
        }
        request.httpBody = body

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OmnirouteAPIError.transport(URLError(.badServerResponse))
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw OmnirouteAPIError.unauthorized
        }
        if http.statusCode == 404 || http.statusCode == 405 {
            throw OmnirouteAPIError.endpointUnavailable
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OmnirouteAPIError.httpError(http.statusCode)
        }
    }

    // MARK: - CLI Token (machine-id derived, mirrors omniroute CLI)

    /// omniroute 的 CLI 通过 machine-id + 固定 salt 派生一个本地 cli-token，
    /// 服务端用它来授权本地管理操作（如切换 active combo）。
    /// 这里用 IOPlatformUUID 复刻同样的逻辑，避免每次都 fork 出 Node 进程。
    private var cliToken: String? {
        guard let uuid = Self.ioregPlatformUUID() else { return nil }
        let salted = uuid + "omniroute-cli-auth-v1"
        if let data = salted.data(using: .utf8) {
            let hash = SHA256.hash(data: data)
            return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
        }
        return nil
    }

    private static func ioregPlatformUUID() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        task.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            // 形如: "IOPlatformUUID" = "34097627-B9E1-5B74-8AC0-AADB164E3A98"
            let pattern = "\"IOPlatformUUID\"\\s*=\\s*\"([^\"]+)\""
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(output.startIndex..., in: output)
            if let match = regex.firstMatch(in: output, range: range),
               let r = Range(match.range(at: 1), in: output) {
                return String(output[r])
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Endpoints

    /// /api/providers -> { connections: [Provider], total }
    struct ProvidersResponse: Codable {
        let connections: [Provider]
        let total: Int?
    }

    func fetchProviders() async throws -> [Provider] {
        let resp: ProvidersResponse = try await request("/api/providers")
        return resp.connections
    }

    /// /api/combos -> { combos: [Combo], total }
    struct CombosResponse: Codable {
        let combos: [Combo]
        let total: Int?
    }

    func fetchCombos() async throws -> [Combo] {
        let resp: CombosResponse = try await request("/api/combos")
        return resp.combos
    }

    /// GET /v1/models -> { object, data: [GatewayModel] }（OpenAI 兼容接口，供「AI 接入」模型选择）
    struct ModelsResponse: Codable {
        let data: [GatewayModel]
    }

    func fetchModels() async throws -> [GatewayModel] {
        let resp: ModelsResponse = try await request("/v1/models")
        return resp.data
    }

    // MARK: - Prompt Compression

    /// /api/settings/compression -> { enabled, defaultMode, ... }
    /// enabled 为总开关；defaultMode 为压缩模式（off/lite/standard/aggressive/ultra）。
    struct CompressionSettings: Codable {
        let enabled: Bool
        let defaultMode: String
    }

    /// 读取当前提示词压缩配置（只取 UI 需要的 enabled / defaultMode，其余字段忽略）。
    func fetchCompressionSettings() async throws -> CompressionSettings {
        try await request("/api/settings/compression")
    }

    /// 写入提示词压缩配置，返回网关确认后的最新状态。
    /// - Parameters:
    ///   - enabled: 是否启用压缩
    ///   - defaultMode: 压缩模式（off/lite/standard/aggressive/ultra）
    func setCompressionSettings(enabled: Bool, defaultMode: String) async throws -> CompressionSettings {
        struct Body: Codable { let enabled: Bool; let defaultMode: String }
        let body = try JSONEncoder().encode(Body(enabled: enabled, defaultMode: defaultMode))
        return try await request("/api/settings/compression", method: "PATCH", body: body)
    }

    /// 切换当前激活的 combo。
    /// omniroute 把"当前激活 combo"存在本地 SQLite 的 key_value 表
    /// (namespace='settings', key='activeCombo', value='"<name>"')，
    /// 服务端实时读取它来决定路由。这与 `omniroute combo switch` 的本地 DB 分支完全一致。
    /// 由于 omniroute 的 HTTP 分支（PATCH /api/settings）不回写该状态，
    /// 这里直接通过本地 sqlite3 写入，确保与 CLI 行为一致且立即生效。
    /// - Parameter nameOrId: combo 的 name 或 id
    /// - Returns: 是否成功
    func setActiveCombo(nameOrId: String) async throws -> Bool {
        // 优先用本地 sqlite3 写 key_value；若失败则回退到 HTTP PATCH（带 cli-token）。
        if Self.writeActiveComboToSqlite(nameOrId) {
            return true
        }
        struct Body: Codable { let activeCombo: String }
        let body = try JSONEncoder().encode(Body(activeCombo: nameOrId))
        struct Empty: Codable {}
        let _: Empty = try await request("/api/settings", method: "PATCH", body: body, includeCliToken: true)
        return true
    }

    private static func writeActiveComboToSqlite(_ nameOrId: String) -> Bool {
        let dbPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".omniroute/storage.sqlite")
        guard FileManager.default.fileExists(atPath: dbPath) else { return false }
        let sql = "INSERT OR REPLACE INTO key_value (namespace, key, value) VALUES ('settings', 'activeCombo', '\"\(nameOrId.replacingOccurrences(of: "\"", with: ""))\"');"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [dbPath, sql]
        task.standardError = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 读取服务端当前激活的 combo（name 或 id）。
    /// omniroute 会在 GET /api/settings 中回写 activeCombo（来自 key_value 表）。
    func fetchActiveCombo() async throws -> String? {
        struct Settings: Codable { let activeCombo: String? }
        let s: Settings = try await request("/api/settings")
        return s.activeCombo
    }

    /// /api/usage/analytics?period=1d|7d|30d|90d|ytd|all
    /// 返回 summary + dailyTrend；这里只需今日与 30 天汇总，映射到 UsageStats。
    func fetchUsageStats() async throws -> UsageStats {
        struct DailyEntry: Codable {
            let date: String?
            let requests: Int?
            let promptTokens: Int?
            let completionTokens: Int?
            let totalTokens: Int?
            let cost: Double?
            let flexSavings: Double?
            let flexUsageSavingsTokens: Int?
        }
        struct Summary: Codable {
            let totalCost: Double?
            let totalTokens: Int?
            let promptTokens: Int?
            let completionTokens: Int?
            let flexSavings: Double?
            let flexUsageSavingsTokens: Int?
            let totalRequests: Int?
        }
        struct Analytics: Codable {
            let summary: Summary?
            let dailyTrend: [DailyEntry]?
        }

        // 今日：取 dailyTrend 中与今天日期匹配的条目；若无匹配则用最后一条
        let today: Analytics = try await request("/api/usage/analytics?period=1d")
        // 30 天：从中筛选出「本月」的条目累加，避免把近 30 天全部算成本月开销
        let month: Analytics = try await request("/api/usage/analytics?period=30d")

        let cal = Calendar(identifier: .gregorian)
        let todayStr = Self.isoDateFormatter.string(for: cal.startOfDay(for: Date())) ?? ""

        let todayEntry = (today.dailyTrend ?? [])
            .first(where: { $0.date == todayStr })
            ?? (today.dailyTrend ?? []).last

        let todayTokens = todayEntry?.totalTokens ?? 0
        let todayCost = Decimal(string: String(todayEntry?.cost ?? 0)) ?? 0

        // 本月 = dailyTrend 中月份与当前月一致的条目累加
        let monthPrefix = todayStr.prefix(7) // "2026-08"
        let monthEntries = (month.dailyTrend ?? []).filter { ($0.date ?? "").hasPrefix(monthPrefix) }
        let monthTokens = monthEntries.reduce(0) { $0 + ($1.totalTokens ?? 0) }
        let monthCost = monthEntries.reduce(Decimal(0)) { $0 + (Decimal(string: String($1.cost ?? 0)) ?? 0) }
        let savedTokens = monthEntries.reduce(0) { $0 + ($1.flexUsageSavingsTokens ?? 0) }
        let savedCost = monthEntries.reduce(Decimal(0)) { $0 + (Decimal(string: String($1.flexSavings ?? 0)) ?? 0) }
        // 预算：omniroute 的 budget 需 apiKeyId，HTTP 不可得；暂用 0 表示未设置
        let budget: Decimal = 0

        return UsageStats(
            todayTokens: todayTokens,
            todayCost: todayCost,
            monthTokens: monthTokens,
            monthBudget: budget,
            monthCost: monthCost,
            savedTokens: savedTokens,
            savedCost: savedCost
        )
    }

    // MARK: - System Version & Provider Operations

    /// /api/system/version -> { current, latest, updateAvailable, ... }
    struct SystemVersion: Codable {
        let current: String?
        let latest: String?
        let updateAvailable: Bool?
    }

    func fetchSystemVersion() async throws -> SystemVersion {
        try await request("/api/system/version")
    }

    /// /api/usage/call-logs?limit=N -> [CallLog] 最近调用记录（按时间倒序）
    func fetchRecentCalls(limit: Int = 1) async throws -> [CallLog] {
        try await request("/api/usage/call-logs?limit=\(limit)")
    }

    /// /api/providers/{id}/test -> { valid, error, latencyMs, ... } 重新检测单一连接健康度
    struct ProviderTestResult: Codable {
        let valid: Bool?
        let error: String?
    }

    func testProvider(id: String) async throws -> ProviderTestResult {
        try await request("/api/providers/\(id)/test", method: "POST")
    }

    /// PATCH /api/providers/{id} 更新连接（isActive 启用/停用，priority 优先级），返回 204
    func updateProvider(id: String, isActive: Bool? = nil, priority: Int? = nil) async throws {
        struct Body: Codable {
            var isActive: Bool?
            var priority: Int?
        }
        var body = Body()
        body.isActive = isActive
        body.priority = priority
        let data = try JSONEncoder().encode(body)
        try await requestVoid("/api/providers/\(id)", method: "PATCH", body: data)
    }

    /// DELETE /api/providers/{id} 删除连接
    func deleteProvider(id: String) async throws {
        try await requestVoid("/api/providers/\(id)", method: "DELETE")
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        // 关键：API 的 dailyTrend 日期按本地时区（如 2026-08-02）。
        // ISO8601DateFormatter 默认用 UTC，导致 todayStr/monthPrefix 与 API 错位一天，
        // 使「今日」匹配到旧条目甚至全 0。必须显式用本地时区。
        f.timeZone = .current
        return f
    }()
}
