//
//  OmniBarTests.swift
//  OmniBarTests
//
//  单元测试：覆盖核心 Models 的解析与展示逻辑。
//

import XCTest
@testable import OmniBar

final class OmniBarTests: XCTestCase {

    // MARK: - ConnectionHealth

    func testConnectionHealthActive() {
        let health = ConnectionHealth(testStatus: "active", backoffLevel: 0)
        XCTAssertEqual(health, .active)
        XCTAssertEqual(health.label, "健康")
        XCTAssertEqual(health.badge, "checkmark.circle.fill")
        XCTAssertFalse(health.isDimmed)
    }

    func testConnectionHealthCooldownWhenBackoff() {
        // backoff > 0 时优先判定为冷却，即使 testStatus 为 active
        let health = ConnectionHealth(testStatus: "active", backoffLevel: 2)
        XCTAssertEqual(health, .cooldown)
        XCTAssertEqual(health.label, "冷却")
    }

    func testConnectionHealthError() {
        let health = ConnectionHealth(testStatus: "error", backoffLevel: 0)
        XCTAssertEqual(health, .error)
        XCTAssertEqual(health.badge, "xmark.circle.fill")
        XCTAssertTrue(health.isDimmed)
    }

    func testConnectionHealthCaseInsensitive() {
        // 大小写不敏感
        XCTAssertEqual(ConnectionHealth(testStatus: "ACTIVE", backoffLevel: 0), .active)
        XCTAssertEqual(ConnectionHealth(testStatus: "ERROR", backoffLevel: 0), .error)
    }

    func testConnectionHealthUnknownFallback() {
        XCTAssertEqual(ConnectionHealth(testStatus: nil, backoffLevel: 0), .unknown)
        XCTAssertEqual(ConnectionHealth(testStatus: "weird", backoffLevel: 0), .unknown)
    }

    // MARK: - Provider.providerTypeShort

    func testProviderTypeShortStripsUUIDSuffix() {
        let p = Provider(id: "1", providerType: "openai-compatible-chat-3d2a1b4c-9f10-4a2b-8c3d-5e6f7a8b9c0d",
                         name: "Key 1", isActive: true, health: .active)
        XCTAssertEqual(p.providerTypeShort, "openai-compatible-chat")
    }

    func testProviderTypeShortWithoutUUID() {
        let p = Provider(id: "1", providerType: "siliconflow", name: "main", isActive: true, health: .active)
        XCTAssertEqual(p.providerTypeShort, "siliconflow")
    }

    // MARK: - Provider.displayName

    func testDisplayNamePrefersName() {
        let p = Provider(id: "1", providerType: "siliconflow", name: "Key 1", isActive: true, health: .active)
        XCTAssertEqual(p.displayName, "Key 1")
    }

    func testDisplayNameFallsBackToShortType() {
        let p = Provider(id: "1", providerType: "openai-compatible-chat-3d2a1b4c-9f10-4a2b-8c3d-5e6f7a8b9c0d",
                         name: "   ", isActive: true, health: .active)
        XCTAssertEqual(p.displayName, "openai-compatible-chat")
    }

    // MARK: - Provider JSON decoding

    func testProviderDecodeFromRawJSON() throws {
        let json = """
        {
          "id": "conn-1",
          "provider": "siliconflow",
          "name": "main",
          "isActive": true,
          "testStatus": "active",
          "backoffLevel": 0,
          "lastError": null,
          "providerSpecificData": { "baseUrl": "https://api.siliconflow.cn" }
        }
        """.data(using: .utf8)!
        let provider = try JSONDecoder().decode(Provider.self, from: json)
        XCTAssertEqual(provider.id, "conn-1")
        XCTAssertEqual(provider.providerType, "siliconflow")
        XCTAssertEqual(provider.name, "main")
        XCTAssertTrue(provider.isActive)
        XCTAssertEqual(provider.health, .active)
        XCTAssertEqual(provider.baseURL, "https://api.siliconflow.cn")
        XCTAssertNil(provider.lastError)
    }

    // MARK: - Combo.strategyLabel

    func testStrategyLabel() {
        XCTAssertEqual(Combo(id: "1", name: "c1", strategy: "priority").strategyLabel, "优先级")
        XCTAssertEqual(Combo(id: "1", name: "c1", strategy: "auto").strategyLabel, "自动")
        XCTAssertEqual(Combo(id: "1", name: "c1", strategy: "cost-optimized").strategyLabel, "成本优化")
        XCTAssertEqual(Combo(id: "1", name: "c1", strategy: "cost_optimized").strategyLabel, "成本优化")
        XCTAssertEqual(Combo(id: "1", name: "c1", strategy: "latency_optimized").strategyLabel, "低延迟")
    }

    func testStrategyLabelUnknownReturnsRaw() {
        XCTAssertEqual(Combo(id: "1", name: "c1", strategy: "custom").strategyLabel, "custom")
    }

    // MARK: - Combo JSON decoding

    func testComboDecode() throws {
        let json = """
        {
          "id": "c1",
          "name": "coding",
          "strategy": "priority",
          "sortOrder": 1,
          "models": [{"id": "m1", "model": "command-code/deepseek/deepseek-v4-pro", "weight": 1}]
        }
        """.data(using: .utf8)!
        let combo = try JSONDecoder().decode(Combo.self, from: json)
        XCTAssertEqual(combo.name, "coding")
        XCTAssertEqual(combo.strategy, "priority")
        XCTAssertEqual(combo.models.count, 1)
        XCTAssertEqual(combo.models.first?.model, "command-code/deepseek/deepseek-v4-pro")
    }

    // MARK: - ServiceStatus / ProviderStatus

    func testServiceStatusLabels() {
        XCTAssertEqual(ServiceStatus.running.label, "运行中")
        XCTAssertEqual(ServiceStatus.stopped.label, "已停止")
        XCTAssertEqual(ServiceStatus.error.label, "错误")
        XCTAssertEqual(ServiceStatus.unknown.label, "未知")
    }

    func testProviderStatusLabels() {
        XCTAssertEqual(ProviderStatus.healthy.label, "健康")
        XCTAssertEqual(ProviderStatus.cooldown.label, "冷却")
        XCTAssertEqual(ProviderStatus.locked.label, "锁定")
        XCTAssertEqual(ProviderStatus.offline.label, "离线")
    }

    // MARK: - UsageStats formatting

    func testFormatTokenCount() {
        XCTAssertEqual(UsageStats.formatTokenCount(0), "0")
        XCTAssertEqual(UsageStats.formatTokenCount(999), "999")
        XCTAssertEqual(UsageStats.formatTokenCount(1_500), "1.5K")
        XCTAssertEqual(UsageStats.formatTokenCount(12_500), "12.5K")
        XCTAssertEqual(UsageStats.formatTokenCount(1_000_000), "1.0M")
        XCTAssertEqual(UsageStats.formatTokenCount(2_500_000), "2.5M")
    }

    func testUsageStatsCostText() {
        let stats = UsageStats(todayTokens: 12_500,
                               todayCost: 0.42,
                               monthTokens: 1_000_000,
                               monthBudget: 20.0,
                               monthCost: 8.5,
                               savedTokens: 25_000,
                               savedCost: 3.75)
        XCTAssertEqual(stats.todayCostText, "$0.42")
        XCTAssertEqual(stats.todayTokensText, "12.5K")
        XCTAssertEqual(stats.monthCostText, "$8.50")
        XCTAssertEqual(stats.monthTokensText, "1.0M")
        XCTAssertEqual(stats.savedCostText, "$3.75")
        XCTAssertEqual(stats.savedTokensText, "25.0K")
        XCTAssertTrue(stats.hasBudget)
    }

    func testUsageStatsNoBudget() {
        let stats = UsageStats(todayTokens: 0, todayCost: 0, monthTokens: 0,
                               monthBudget: 0, monthCost: 0, savedTokens: 0, savedCost: 0)
        XCTAssertFalse(stats.hasBudget)
        XCTAssertEqual(stats.budgetUsagePercent, 0)
    }

    func testUsageStatsDecodeMissingFieldsFallback() throws {
        let json = "{\"today_tokens\": 500}".data(using: .utf8)!
        let stats = try JSONDecoder().decode(UsageStats.self, from: json)
        XCTAssertEqual(stats.todayTokens, 500)
        XCTAssertEqual(stats.monthTokens, 0)
        XCTAssertEqual(stats.todayCost, 0)
    }
}


