//
//  CallLog.swift
//  OmniBar
//
//  来自 GET /api/usage/call-logs 的单条调用记录。
//  展示「当前调用」：路由到哪个模型、哪个提供商/连接、耗时与状态。
//

import Foundation

/// 一次 LLM 调用记录（call-log）
struct CallLog: Codable, Identifiable, Equatable {
    var id: String
    var timestamp: Date?
    var method: String?
    var path: String?
    var status: Int?
    var model: String?
    var requestedModel: String?
    var provider: String?
    var providerDisplay: String?
    var account: String?
    var connectionId: String?
    var comboName: String?
    var duration: Int?
    var error: String?
    var tokens: Tokens?

    struct Tokens: Codable, Equatable {
        var inTok: Int?
        var outTok: Int?

        enum CodingKeys: String, CodingKey {
            case inTok = "in"
            case outTok = "out"
        }
    }

    /// 调用是否成功（HTTP 2xx）
    var isSuccess: Bool {
        guard let status else { return false }
        return (200..<300).contains(status)
    }

    /// 展示用提供商名：优先 providerDisplay，其次 provider，缺失回退 "未知"
    var displayProvider: String {
        if let d = providerDisplay, !d.isEmpty { return d }
        if let p = provider, !p.isEmpty { return p }
        return "未知"
    }

    /// 展示用模型名：实际路由模型优先，回退到请求模型
    var displayModel: String {
        if let m = model, !m.isEmpty, m != "connection-test" { return m }
        return requestedModel ?? "—"
    }

    /// 连接/账号（main-2 / Key 1 等），无则显示 "—"
    var displayAccount: String {
        account?.trimmingCharacters(in: .whitespaces).isEmpty == false ? account! : "—"
    }

    /// 耗时文本（毫秒）
    var durationText: String {
        guard let duration else { return "—" }
        return "\(duration) ms"
    }

    /// 时间文本（HH:mm:ss）
    var timeText: String {
        guard let timestamp else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: timestamp)
    }

    /// 是否属于「连接健康测试」等非真实模型调用（用于列表过滤）
    var isTestCall: Bool {
        (model == "connection-test")
            || (path?.contains("providers/test") == true)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case method
        case path
        case status
        case model
        case requestedModel
        case provider
        case providerDisplay
        case account
        case connectionId
        case comboName
        case duration
        case error
        case tokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        timestamp = CallLog.parseISO8601(try c.decodeIfPresent(String.self, forKey: .timestamp))
        method = try c.decodeIfPresent(String.self, forKey: .method)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        status = try c.decodeIfPresent(Int.self, forKey: .status)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        requestedModel = try c.decodeIfPresent(String.self, forKey: .requestedModel)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        providerDisplay = try c.decodeIfPresent(String.self, forKey: .providerDisplay)
        account = try c.decodeIfPresent(String.self, forKey: .account)
        connectionId = try c.decodeIfPresent(String.self, forKey: .connectionId)
        comboName = try c.decodeIfPresent(String.self, forKey: .comboName)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        tokens = try c.decodeIfPresent(Tokens.self, forKey: .tokens)
    }

    private static func parseISO8601(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
