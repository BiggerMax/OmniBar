//
//  Combo.swift
//  OmniBar
//
//  来自 GET /api/combos -> { combos: [Combo], total }
//  实际 omniroute combo 含 name/strategy/sortOrder/models[]（每个 model 元素是结构体而非字符串）。
//

import Foundation

/// Combo 内部的一个模型项（来自 models[] 元素）
struct ComboModel: Codable, Identifiable, Hashable {
    var id: String
    /// 模型显示标签（有时缺省）
    var label: String?
    /// 模型路径，如 "command-code/deepseek/deepseek-v4-pro"
    var model: String
    /// Provider id（连接类型）
    var providerId: String?
    /// 关联的 Connection id（可能有）
    var connectionId: String?
    var weight: Int?
    var kind: String?

    enum CodingKeys: String, CodingKey {
        case id, label, model, providerId, connectionId, weight, kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        label = try c.decodeIfPresent(String.self, forKey: .label)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? id
        providerId = try c.decodeIfPresent(String.self, forKey: .providerId)
        connectionId = try c.decodeIfPresent(String.self, forKey: .connectionId)
        weight = try c.decodeIfPresent(Int.self, forKey: .weight)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
    }

    init(id: String, model: String, label: String? = nil, providerId: String? = nil, connectionId: String? = nil, weight: Int? = nil) {
        self.id = id
        self.model = model
        self.label = label
        self.providerId = providerId
        self.connectionId = connectionId
        self.weight = weight
        self.kind = "model"
    }
}

struct Combo: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var strategy: String
    var sortOrder: Int?
    var isHidden: Bool?
    var models: [ComboModel]
    var contextLength: Int?

    var strategyLabel: String {
        switch strategy.lowercased() {
        case "priority": return "优先级"
        case "auto": return "自动"
        case "cost-optimized", "cost_optimized": return "成本优化"
        case "latency-optimized", "latency_optimized": return "低延迟"
        default: return strategy
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, strategy, sortOrder, isHidden, models
        case contextLength = "computed_context_length"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Combo"
        strategy = try c.decodeIfPresent(String.self, forKey: .strategy) ?? "auto"
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder)
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden)
        models = try c.decodeIfPresent([ComboModel].self, forKey: .models) ?? []
        contextLength = try c.decodeIfPresent(Int.self, forKey: .contextLength)
    }

    init(id: String, name: String, strategy: String, models: [ComboModel] = [], sortOrder: Int? = nil) {
        self.id = id
        self.name = name
        self.strategy = strategy
        self.models = models
        self.sortOrder = sortOrder
    }
}
