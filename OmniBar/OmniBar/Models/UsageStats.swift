//
//  UsageStats.swift
//  OmniBar
//
//  来自 API 聚合
//

import Foundation

struct UsageStats: Codable {
    var todayTokens: Int
    var todayCost: Decimal
    var monthTokens: Int
    var monthBudget: Decimal
    var monthCost: Decimal
    var savedTokens: Int
    var savedCost: Decimal

    var todayCostText: String {
        let nsNumber = NSDecimalNumber(decimal: todayCost)
        return String(format: "$%.2f", nsNumber.doubleValue)
    }

    var savedCostText: String {
        let nsNumber = NSDecimalNumber(decimal: savedCost)
        return String(format: "$%.2f", nsNumber.doubleValue)
    }

    var monthBudgetText: String {
        let nsNumber = NSDecimalNumber(decimal: monthBudget)
        return String(format: "$%.2f", nsNumber.doubleValue)
    }

    var monthCostText: String {
        let nsNumber = NSDecimalNumber(decimal: monthCost)
        return String(format: "$%.2f", nsNumber.doubleValue)
    }

    var todayTokensText: String {
        return Self.formatTokenCount(todayTokens)
    }

    var monthTokensText: String {
        return Self.formatTokenCount(monthTokens)
    }

    var savedTokensText: String {
        return Self.formatTokenCount(savedTokens)
    }

    var budgetUsagePercent: Double {
        let budget = NSDecimalNumber(decimal: monthBudget).doubleValue
        guard budget > 0 else { return 0 }
        // monthCost 不可得时以今日开销推算比例的占位符
        return min(1.0, max(0.0, 0))
    }

    static func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    enum CodingKeys: String, CodingKey {
        case todayTokens = "today_tokens"
        case todayCost = "today_cost"
        case monthTokens = "month_tokens"
        case monthBudget = "month_budget"
        case monthCost = "month_cost"
        case savedTokens = "saved_tokens"
        case savedCost = "saved_cost"
    }

    init() {
        self.todayTokens = 0
        self.todayCost = 0
        self.monthTokens = 0
        self.monthBudget = 0
        self.monthCost = 0
        self.savedTokens = 0
        self.savedCost = 0
    }

    init(todayTokens: Int, todayCost: Decimal, monthTokens: Int, monthBudget: Decimal, monthCost: Decimal, savedTokens: Int, savedCost: Decimal) {
        self.todayTokens = todayTokens
        self.todayCost = todayCost
        self.monthTokens = monthTokens
        self.monthBudget = monthBudget
        self.monthCost = monthCost
        self.savedTokens = savedTokens
        self.savedCost = savedCost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        todayTokens = try container.decodeIfPresent(Int.self, forKey: .todayTokens) ?? 0
        if let v = try? container.decodeIfPresent(Decimal.self, forKey: .todayCost) { todayCost = v } else { todayCost = 0 }
        monthTokens = try container.decodeIfPresent(Int.self, forKey: .monthTokens) ?? 0
        if let v = try? container.decodeIfPresent(Decimal.self, forKey: .monthBudget) { monthBudget = v } else { monthBudget = 0 }
        if let v = try? container.decodeIfPresent(Decimal.self, forKey: .monthCost) { monthCost = v } else { monthCost = 0 }
        savedTokens = try container.decodeIfPresent(Int.self, forKey: .savedTokens) ?? 0
        if let v = try? container.decodeIfPresent(Decimal.self, forKey: .savedCost) { savedCost = v } else { savedCost = 0 }
    }
}
