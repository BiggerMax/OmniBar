//
//  UsageSummary.swift
//  OmniBar
//
//  用量速览：ClashMac bento 2×2 网格 + 全宽预算进度条
//

import SwiftUI

struct UsageSummary: View {
    let usage: UsageStats

    private let columns = [GridItem(.flexible(), spacing: DT.Space.l), GridItem(.flexible(), spacing: DT.Space.l)]

    var body: some View {
        VStack(spacing: DT.Space.l) {
            DSectionLabel(title: "用量速览")
                .padding(.horizontal, DT.Space.xs)
            LazyVGrid(columns: columns, spacing: DT.Space.l) {
                DStatCard(icon: "dollarsign.circle", iconColor: DT.Color.accent,
                          label: "今日", value: usage.todayCostText,
                          subtitle: usage.todayTokensText + " tok")
                DStatCard(icon: "number", iconColor: DT.Color.accentBlue,
                          label: "本月", value: usage.monthCostText,
                          subtitle: usage.monthTokensText + " tok")
                DStatCard(icon: "bolt.fill", iconColor: DT.Color.success,
                          label: "预估节省", value: usage.savedCostText,
                          subtitle: usage.savedTokensText + " tok")
                if usage.hasBudget {
                    let overBudget = usage.monthCost > usage.monthBudget
                    DStatCard(icon: "chart.pie.fill", iconColor: overBudget ? DT.Color.danger : DT.Color.warning,
                              label: "预算", value: usage.monthBudgetText,
                              subtitle: budgetRemainingText,
                              valueColor: overBudget ? DT.Color.danger : nil)
                }
            }
            // 全宽 6pt 预算进度条（有预算才显示）
            if usage.hasBudget {
                progressBar
            }
        }
    }

    private var budgetRemainingText: String {
        let remaining = usage.monthBudget - usage.monthCost
        let ns = NSDecimalNumber(decimal: remaining)
        let sign = remaining < 0 ? "-" : ""
        return sign + "余 " + String(format: "$%.2f", abs(ns.doubleValue))
    }

    // MARK: 进度条（6pt + 暗色细描边轨道；有预算才显示）
    @ViewBuilder
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DT.Color.surfaceElevated)
                    .frame(height: 6)
                    .overlay(Capsule().strokeBorder(DT.Color.strokeVariant, lineWidth: 0.5))
                Capsule()
                    .fill(barColor)
                    .frame(width: max(3, geo.size.width * budgetProgress), height: 6)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, DT.Space.xs)
    }

    private var barColor: Color {
        usage.monthCost > usage.monthBudget ? DT.Color.danger : DT.Color.accent
    }

    private var budgetProgress: Double {
        let budget = NSDecimalNumber(decimal: usage.monthBudget).doubleValue
        guard budget > 0 else { return 0 }
        return min(1.0, max(0.0, NSDecimalNumber(decimal: usage.monthCost).doubleValue / budget))
    }
}
