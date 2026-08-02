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
        VStack(spacing: DT.Space.l) {
            DSectionLabel(title: "用量速览")
                .padding(.horizontal, DT.Space.xs)
            // 与 Provider 行 / Combo 卡片一致的容器：surfaceElevated + strokeVariant 描边
            VStack(spacing: DT.Space.xl) {
                metricsGrid
                progressBar
            }
            .padding(DT.Space.l)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .fill(DT.Color.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .strokeBorder(DT.Color.strokeVariant, lineWidth: 0.5)
            )
        }
    }

    private var metricsGrid: some View {
        HStack(alignment: .top, spacing: DT.Space.xl) {
            metric(label: "今日", primary: usage.todayCostText, secondary: usage.todayTokensText + " tok")
            metric(label: "本月", primary: usage.monthCostText, secondary: usage.monthTokensText + " tok")
            metric(label: "预估节省", primary: usage.savedCostText, secondary: usage.savedTokensText + " tok", accent: true)
            if usage.hasBudget {
                metric(label: "预算", primary: usage.monthBudgetText, secondary: budgetRemainingText, budget: true)
            }
        }
    }

    private var budgetRemainingText: String {
        let remaining = usage.monthBudget - usage.monthCost
        let ns = NSDecimalNumber(decimal: remaining)
        let sign = remaining < 0 ? "-" : ""
        return sign + "余 " + String(format: "$%.2f", abs(ns.doubleValue))
    }

    private func metric(label: String, primary: String, secondary: String, accent: Bool = false, budget: Bool = false) -> some View {
        let overBudget = budget && usage.monthCost > usage.monthBudget
        return VStack(alignment: .center, spacing: DT.Space.xxs) {
            Text(label)
                .font(DT.Font.micro)
                .foregroundStyle(DT.Color.textSecondary)
                .tracking(1.0)
            Text(primary)
                .font(DT.Font.monoMedium)
                .foregroundStyle(accent ? DT.Color.accent : (overBudget ? DT.Color.danger : DT.Color.textPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(secondary)
                .font(DT.Font.monoSmall)
                .foregroundStyle(overBudget ? DT.Color.danger : DT.Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: 进度条（4px + 蓝光阴影；有预算才显示）
    @ViewBuilder
    private var progressBar: some View {
        if usage.hasBudget {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DT.Color.surfaceElevated)
                        .frame(height: 4)
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(2, geo.size.width * budgetProgress), height: 4)
                        .shadow(color: barColor.opacity(0.5), radius: 4, x: 0, y: 0)
                }
            }
            .frame(height: 4)
        }
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
