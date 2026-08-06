//
//  ProviderLink.swift
//  OmniBar
//
//  v2.0「AI 接入」：把 omniroute 网关接进本机 CLI 客户端的领域模型。
//

import Foundation

// MARK: - GatewayModel

/// 网关暴露的一个可路由模型 / Combo 别名（来自 GET /v1/models）。
struct GatewayModel: Codable, Identifiable, Hashable {
    let id: String
    var object: String?
    var ownedBy: String?
    var contextLength: Int?
    var capabilities: Capabilities?

    struct Capabilities: Codable, Hashable {
        var toolCalling: Bool?
        var reasoning: Bool?
        var vision: Bool?
        var thinking: Bool?

        enum CodingKeys: String, CodingKey {
            case toolCalling = "tool_calling"
            case reasoning
            case vision
            case thinking
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case ownedBy = "owned_by"
        case contextLength = "context_length"
        case capabilities
    }

    /// 去掉 "auto/" 之类的命名空间前缀后的短名（如 "auto/best-fast" → "best-fast"）。
    var shortID: String {
        guard let slash = id.lastIndex(of: "/") else { return id }
        return String(id[id.index(after: slash)...])
    }

    /// provider 依据：id 首个 "/" 前的命名空间段（如 "auto/best-fast" → "auto"、"PY/deepseek-x" → "PY"）。
    /// 无 "/" 的模型归入「其他」分组。
    var provider: String {
        guard let slash = id.firstIndex(of: "/") else { return "其他" }
        return String(id[..<slash])
    }

    var displayName: String { shortID }
}

// MARK: - ClaudeRole

/// Claude Desktop 3P 部署的角色模型：桌面端要求模型名为 claude-sonnet-*/claude-opus-*/claude-haiku-*/claude-fable-*。
/// 本地路由代理把这些角色 ID 重写为真实网关模型，实现免登录接入。
enum ClaudeRole: String, CaseIterable, Identifiable {
    case sonnet
    case opus
    case haiku
    case fable

    var id: String { rawValue }

    /// 桌面端识别的角色模型 ID（与 cc-switch 示例一致）。
    var roleModelID: String {
        switch self {
        case .sonnet: return "claude-sonnet-5"
        case .opus: return "claude-opus-4-8"
        case .haiku: return "claude-haiku-4-5"
        case .fable: return "claude-fable-5"
        }
    }

    /// 模型名匹配前缀（代理用它识别请求里带角色的模型）。
    var modelPrefix: String {
        switch self {
        case .sonnet: return "claude-sonnet"
        case .opus: return "claude-opus"
        case .haiku: return "claude-haiku"
        case .fable: return "claude-fable"
        }
    }

    var title: String {
        switch self {
        case .sonnet: return "Sonnet"
        case .opus: return "Opus"
        case .haiku: return "Haiku"
        case .fable: return "Fable"
        }
    }
}

// MARK: - LinkTarget

/// 需要被「接入 / 接管」本地配置的 CLI 客户端。
enum LinkTarget: String, CaseIterable, Identifiable {
    case claudeCode
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var subtitle: String {
        switch self {
        case .claudeCode: return "Anthropic CLI · Claude Desktop"
        case .codex: return "OpenAI CLI · ChatGPT Desktop"
        }
    }

    var icon: String {
        switch self {
        case .claudeCode: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// 配置文件中使用的哨兵标记 / 备份命名前缀。
    var marker: String { "omnibar:" + rawValue }
}

// MARK: - 文件快照（备份 / 回滚）

/// 记录某个 live 配置文件在「接入前」的原始内容，用于关闭时回滚。
/// 备份存放在 ~/Library/Application Support/OmniBar/backups/ 下，按目标分文件。
struct FileSnapshot {
    let liveURL: URL
    let backupURL: URL
}

extension FileSnapshot {
    /// 以字节为单位读取备份内容；不存在返回 nil。
    func readBackup() -> Data? {
        try? Data(contentsOf: backupURL)
    }
}
