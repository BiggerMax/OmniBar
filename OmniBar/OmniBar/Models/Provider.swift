//
//  Provider.swift
//  OmniBar
//
//  来自 GET /api/providers -> { connections: [Provider], total }
//  实际 omniroute 返回 connection 列表，每个 connection 表示一个上游 Provider 的一条连接（API Key / 配置）。
//

import Foundation
import SwiftUI

/// 来自 /api/providers 的 connection 健康度
/// 与 popover.html 的状态体系对齐：健康 / 冷却 / 离线 / 未知
enum ConnectionHealth: String, Codable {
    case active    // testStatus == "active"，且不在退避中
    case cooldown  // backoffLevel > 0：临时退避/冷却中（HTML: hourglass）
    case error     // testStatus == "error"：离线（HTML: cancel）
    case unknown   // 其它 testStatus

    init(testStatus: String?, backoffLevel: Int) {
        if backoffLevel > 0 {
            self = .cooldown
            return
        }
        switch (testStatus ?? "").lowercased() {
        case "active": self = .active
        case "error": self = .error
        default: self = .unknown
        }
    }

    /// 与 HTML 一致的中文标签
    var label: String {
        switch self {
        case .active: return "健康"
        case .cooldown: return "冷却"
        case .error: return "离线"
        case .unknown: return "未知"
        }
    }

    /// 与 HTML 图标语义对齐：
    /// 健康=check_circle，冷却=hourglass（退避中），离线=cancel，未知=questionmark
    var badge: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        case .cooldown: return "hourglass.circle.fill"
        case .error: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    /// HTML 中的状态色：健康=success 绿，冷却=warning 黄，离线=error 红
    var color: SwiftUI.Color {
        switch self {
        case .active: return DT.Color.success
        case .cooldown: return DT.Color.warning
        case .error: return DT.Color.danger
        case .unknown: return DT.Color.offline
        }
    }

    /// 离线（error）整行降透明度，与 HTML 的 .opacity-60 对齐
    var isDimmed: Bool { self == .error }
}

/// Connection = omniroute 中的一个 Provider 连接（一条 API Key/账号配置）
struct Provider: Codable, Identifiable, Hashable {
    var id: String
    /// Provider 类型（provider identifier，如 "siliconflow" / "command-code"）
    var providerType: String
    /// 连接显示名（如 "main" / "Key 1"）
    var name: String
    /// 是否当前激活
    var isActive: Bool
    /// 测试状态
    var health: ConnectionHealth
    /// 退避等级（>0 表示处于冷却/退避中）
    var backoffLevel: Int
    /// 优先级（数字越大优先级越高，null 表示未设置）
    var priority: Int?
    /// 上游 base URL（嵌套在 providerSpecificData.baseUrl）
    var baseURL: String?
    /// 最近一次测试时间
    var lastTested: Date?
    /// 脱敏 API Key（仅展示）
    var maskedAPIKey: String?
    /// 错误信息（health=error 时有值）
    var lastError: String?

    var healthLabel: String { health.label }
    var healthBadge: String { health.badge }
    var healthColor: SwiftUI.Color { health.color }
    var isDimmed: Bool { health.isDimmed }

    /// 行内主显示名：优先用连接 name（如 "Key 1" / "main"），无则退化到 provider 类型简称
    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? providerTypeShort : n
    }

    /// 简化的 Provider 类型展示：去掉 UUID 后缀（如 openai-compatible-chat-3d2a... → openai-compatible-chat）
    var providerTypeShort: String {
        // 匹配末尾的 UUID（8-4-4-4-12 模式）并去掉
        let pattern = "-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        if let range = providerType.range(of: pattern, options: .regularExpression) {
            return String(providerType[..<range.lowerBound])
        }
        return providerType
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case providerType = "provider"
        case name
        case isActive
        case testStatus
        case backoffLevel
        case priority
        case apiKey
        case lastTested
        case lastError
        case providerSpecificData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        providerType = try c.decodeIfPresent(String.self, forKey: .providerType) ?? "unknown"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? providerType
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        let testStatus = try c.decodeIfPresent(String.self, forKey: .testStatus)
        let backoff = try c.decodeIfPresent(Int.self, forKey: .backoffLevel) ?? 0
        backoffLevel = backoff
        health = ConnectionHealth(testStatus: testStatus, backoffLevel: backoff)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        apiKey_raw: do {
            maskedAPIKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        }
        lastTested = Provider.parseISO8601(try c.decodeIfPresent(String.self, forKey: .lastTested))
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)

        if let psd = try? c.nestedContainer(keyedBy: ProviderSpecificKeys.self, forKey: .providerSpecificData) {
            baseURL = try psd.decodeIfPresent(String.self, forKey: .baseUrl)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(providerType, forKey: .providerType)
        try c.encode(name, forKey: .name)
        try c.encode(isActive, forKey: .isActive)
        try c.encodeIfPresent(priority, forKey: .priority)
        try c.encodeIfPresent(maskedAPIKey, forKey: .apiKey)
        try c.encodeIfPresent(lastError, forKey: .lastError)
    }

    init(id: String, providerType: String, name: String, isActive: Bool, health: ConnectionHealth, priority: Int? = nil, baseURL: String? = nil, backoffLevel: Int = 0) {
        self.id = id
        self.providerType = providerType
        self.name = name
        self.isActive = isActive
        self.health = health
        self.backoffLevel = backoffLevel
        self.priority = priority
        self.baseURL = baseURL
    }

    private enum ProviderSpecificKeys: String, CodingKey {
        case baseUrl
    }

    private static func parseISO8601(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
