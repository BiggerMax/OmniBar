//
//  ServiceStatus.swift
//  OmniBar
//
//  服务状态枚举与展示辅助
//

import SwiftUI

enum ServiceStatus: String, Codable {
    case running
    case stopped
    case error
    case unknown

    var label: String {
        switch self {
        case .running: return "运行中"
        case .stopped: return "已停止"
        case .error: return "错误"
        case .unknown: return "未知"
        }
    }

    var color: Color {
        switch self {
        case .running: return .green
        case .stopped: return .gray
        case .error: return .red
        case .unknown: return .yellow
        }
    }

    var dotSymbol: String {
        switch self {
        case .running: return "circle.fill"
        case .stopped: return "circle.dashed"
        case .error: return "exclamationmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

enum ProviderStatus: String, Codable {
    case healthy
    case cooldown
    case locked
    case offline

    var label: String {
        switch self {
        case .healthy: return "健康"
        case .cooldown: return "冷却"
        case .locked: return "锁定"
        case .offline: return "离线"
        }
    }

    var color: Color {
        switch self {
        case .healthy: return .green
        case .cooldown: return .yellow
        case .locked: return .orange
        case .offline: return .red
        }
    }

    var badge: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .cooldown: return "hourglass.circle.fill"
        case .locked: return "lock.circle.fill"
        case .offline: return "xmark.circle.fill"
        }
    }
}
