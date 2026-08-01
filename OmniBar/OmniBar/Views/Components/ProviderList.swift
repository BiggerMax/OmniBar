//
//  ProviderList.swift
//  OmniBar
//
//  Provider 健康列表：1:1 对齐 popover.html 的「Provider 健康」区域
//  布局：状态图标 | 名称 | 状态胶囊（右对齐）
//  离线行整体降透明度（opacity 0.6），与 HTML 的 .opacity-60 一致。
//

import SwiftUI

struct ProviderList: View {
    let providers: [Provider]
    var onSelect: (Provider) -> Void = { _ in }
    var body: some View {
        // 对齐 HTML：Provider 区块无外层容器卡片，行本身是 bg-white/5 独立卡片
        // section 间距 space-3(12px)，行间距 space-2(8px)
        VStack(spacing: DT.Space.l) {
            sectionHeader
            if providers.isEmpty {
                emptyView
            } else {
                LazyVStack(spacing: DT.Space.m) {
                    ForEach(providers) { provider in
                        providerRow(provider)
                    }
                }
            }
        }
    }

    // MARK: - Section Header
    // 对齐 HTML：标题在左（uppercase tracking），info 图标在最右；保留计数置于 info 左侧
    private var sectionHeader: some View {
        HStack(spacing: DT.Space.s) {
            Text("Provider 健康")
                .font(DT.Font.sectionLabel)
                .foregroundStyle(DT.Color.textLabel)
                .textCase(.uppercase)
                .tracking(1.5)
            Spacer()
            Text("\(activeCount)/\(providers.count)")
                .font(DT.Font.monoSmall)
                .foregroundStyle(DT.Color.textSecondary)
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(DT.Color.textTertiary)
        }
        .padding(.horizontal, DT.Space.xs)
    }

    private var activeCount: Int {
        providers.filter { $0.health == .active }.count
    }

    private var emptyView: some View {
        Text("暂无 Provider 连接")
            .font(DT.Font.body)
            .foregroundStyle(DT.Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DT.Space.m)
    }

    // MARK: - Row
    // 对齐 HTML .provider-row：[状态图标 gap-3 名称] | [延迟 gap-3 状态胶囊]
    private func providerRow(_ provider: Provider) -> some View {
        Button(action: { onSelect(provider) }) {
            HStack(spacing: DT.Space.l) {
                // 左侧：状态图标（check_circle / hourglass / cancel / questionmark）+ 名称，gap-3
                HStack(spacing: DT.Space.l) {
                    Image(systemName: provider.healthBadge)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(provider.healthColor)
                        .frame(width: 18, alignment: .leading)

                    // 名称：用连接名（Key 1 / main 等）作主显示，provider 类型作副标签，
                    // 避免多个同类型连接去掉 UUID 后同名、却因状态不同造成"颜色不匹配"的混淆
                    VStack(alignment: .leading, spacing: 1) {
                        Text(provider.displayName)
                            .font(DT.Font.bodyMedium)
                            .foregroundStyle(DT.Color.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(1)
                        Text(provider.providerTypeShort)
                            .font(DT.Font.monoTiny)
                            .foregroundStyle(DT.Color.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: DT.Space.s)

                // 右侧：延迟（mono）+ 状态胶囊，gap-3；chevron 用于进入大卡片
                HStack(spacing: DT.Space.l) {
                    Text(provider.latencyText + " ms")
                        .font(DT.Font.monoSmall)
                        .foregroundStyle(DT.Color.textSecondary)
                    // 状态胶囊：对齐 HTML .health-badge，颜色随状态（绿/黄/红）
                    StatusPill(text: provider.healthLabel, color: provider.healthColor)
                    // 进入指示
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DT.Color.textTertiary)
                }
            }
            .padding(.horizontal, DT.Space.l - 2) // 对齐 HTML p-2.5 (10px)
            .padding(.vertical, DT.Space.m)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .fill(DT.Color.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .strokeBorder(DT.Color.strokeVariant, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainRowButtonStyle())
        // 离线（error）整行降透明度，对齐 HTML 的 .opacity-60
        .opacity(provider.isDimmed ? 0.6 : 1.0)
        .animation(.easeOut(duration: 0.25), value: provider.health)
    }
}

/// 行内按钮：无默认高亮，hover 时轻微提亮
private struct PlainRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .fill(configuration.isPressed ? DT.Color.accent.opacity(0.12) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
