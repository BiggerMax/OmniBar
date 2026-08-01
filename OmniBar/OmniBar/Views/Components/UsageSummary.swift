//
//  UsageSummary.swift
//  OmniBar
//
//  用量速览：三列指标 + 蓝光进度条
//

import SwiftUI

struct UsageSummary: View {
    let usage: UsageStats

    var body: some View {
        VStack(spacing: DT.Space.m) {
            DSectionLabel(title: "用量速览")
                .padding(.horizontal, DT.Space.xs)
            VStack(spacing: DT.Space.xl) {
                metricsGrid
                progressBar
            }
        }
    }

    private var metricsGrid: some View {
        HStack(alignment: .top, spacing: DT.Space.xl) {
            metric(label: "今日", primary: usage.todayCostText, secondary: usage.todayTokensText + " tok")
            metric(label: "本月", primary: usage.monthCostText, secondary: usage.monthTokensText + " tok")
            metric(label: "预估节省", primary: usage.savedCostText, secondary: usage.savedTokensText + " tok", accent: true)
        }
    }

    private func metric(label: String, primary: String, secondary: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.xxs) {
            Text(label)
                .font(DT.Font.micro)
                .foregroundStyle(DT.Color.textSecondary)
            Text(primary)
                .font(DT.Font.monoSmall)
                .foregroundStyle(accent ? DT.Color.accent : DT.Color.textPrimary)
            Text(secondary)
                .font(DT.Font.monoTiny)
                .foregroundStyle(DT.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 进度条（4px + 蓝光阴影）
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DT.Color.surfaceElevated)
                    .frame(height: 4)
                Capsule()
                    .fill(DT.Color.accent)
                    .frame(width: max(2, geo.size.width * budgetProgress), height: 4)
                    .shadow(color: DT.Color.accent.opacity(0.5), radius: 4, x: 0, y: 0)
            }
        }
        .frame(height: 4)
    }

    private var budgetProgress: Double {
        let budget = NSDecimalNumber(decimal: usage.monthBudget).doubleValue
        let monthCost = NSDecimalNumber(decimal: usage.monthCost).doubleValue
        // 无预算：进度条用今日成本占月成本的占比示意，至少 8% 占位避免空白
        guard budget > 0 else {
            guard monthCost > 0 else { return 0.084 }
            return min(1.0, max(0.05, NSDecimalNumber(decimal: usage.todayCost).doubleValue / monthCost))
        }
        return min(1.0, max(0.0, monthCost / budget))
    }
}
