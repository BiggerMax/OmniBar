//
//  UsageSummary.swift
//  OmniBar
//
//  用量速览：ClashMac bento 2×2 网格 + 全宽预算进度条
//

import SwiftUI

struct UsageSummary: View {
    let usage: UsageStats
    /// 最近一次真实模型调用（合并到网格中的小卡片）
    var call: CallLog? = nil
    var isRunning: Bool = true

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
                currentCallCard
            }
            // 全宽 6pt 预算进度条（有预算才显示）
            if usage.hasBudget {
                progressBar
            }
        }
    }

    /// 当前调用小卡片：模型 + 提供商/连接 + 耗时/状态
    private var currentCallCard: some View {
        VStack(alignment: .leading, spacing: DT.Space.xs) {
            HStack(spacing: DT.Space.xs) {
                Image(systemName: call?.isSuccess == true ? "checkmark.circle.fill" : "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(call?.isSuccess == true ? DT.Color.success : DT.Color.textLabel)
                Text("当前调用")
                    .font(DT.Font.statLabel)
                    .foregroundStyle(DT.Color.textLabel)
                    .tracking(1)
            }
            if let call {
                Text(call.displayModel)
                    .font(DT.Font.statNumber)
                    .foregroundStyle(call.isSuccess ? DT.Color.textPrimary : DT.Color.danger)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.5)
                Text("\(call.displayProvider) · \(call.durationText)")
                    .font(DT.Font.micro)
                    .foregroundStyle(DT.Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(isRunning ? "暂无调用" : "服务未运行")
                    .font(DT.Font.statNumber)
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("—")
                    .font(DT.Font.micro)
                    .foregroundStyle(DT.Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
