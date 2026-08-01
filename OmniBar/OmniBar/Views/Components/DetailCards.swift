//
//  DetailCards.swift
//  OmniBar
//
//  Provider / Combo 的「大卡片」详情视图。
//  由 PopoverPanel 的路由驱动：点击列表中的小卡片后展示。
//

import SwiftUI

// MARK: - 通用明细行

/// 一行 [标签] ........ [值]，用于大卡片中的字段展示
private struct DetailRow: View {
    let label: String
    var value: String? = nil
    var valueContent: (AnyView)? = nil
    var valueColor: Color = DT.Color.textPrimary
    var monospaced: Bool = false

    init(label: String, value: String? = nil, valueColor: Color = DT.Color.textPrimary, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
        self.monospaced = monospaced
    }

    init(label: String, @ViewBuilder content: @escaping () -> some View) {
        self.label = label
        self.valueContent = AnyView(content())
    }

    var body: some View {
        HStack(alignment: .top, spacing: DT.Space.m) {
            Text(label)
                .font(DT.Font.caption)
                .foregroundStyle(DT.Color.textSecondary)
                .frame(width: 88, alignment: .leading)
            Group {
                if let valueContent {
                    valueContent
                } else {
                    Text(value ?? "—")
                        .font(monospaced ? DT.Font.monoSmall : DT.Font.bodyMedium)
                        .foregroundStyle(valueColor)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 详情小标题（icon + 文本），沿用 DSectionLabel 视觉但可带图标
private struct DetailSectionLabel: View {
    let title: String
    let icon: String
    var body: some View {
        HStack(spacing: DT.Space.xs) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(DT.Color.textLabel)
            Text(title.uppercased())
                .font(DT.Font.sectionLabel)
                .foregroundStyle(DT.Color.textLabel)
                .tracking(1.5)
        }
    }
}

/// 详情大卡片容器：统一头部（图标 + 名称 + 关闭）
private struct DetailCardShell<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let onClose: () -> Void
    let content: () -> Content

    init(icon: String, iconColor: Color, title: String, subtitle: String? = nil,
         onClose: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.m) {
                headerRow
                content()
            }
            .padding(DT.Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var headerRow: some View {
        HStack(spacing: DT.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DT.Font.headline)
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DT.Space.s)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DT.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .help("返回")
        }
    }
}

// MARK: - Provider 大卡片

struct ProviderDetailCard: View {
    let provider: Provider
    let onClose: () -> Void

    var body: some View {
        DetailCardShell(
            icon: provider.healthBadge,
            iconColor: provider.healthColor,
            title: provider.providerTypeShort,
            subtitle: provider.name,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: DT.Space.m) {
                statusSection
                connectionSection
                diagnosticSection
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.s) {
            DetailSectionLabel(title: "状态", icon: "heart.circle")
            DCard(padding: DT.Space.l) {
                VStack(alignment: .leading, spacing: DT.Space.m) {
                    DetailRow(label: "健康度") { StatusPill(text: provider.healthLabel, color: provider.healthColor) }
                    DetailRow(label: "启用", value: provider.isActive ? "已启用" : "未启用",
                              valueColor: provider.isActive ? DT.Color.success : DT.Color.textSecondary)
                    if let prio = provider.priority {
                        DetailRow(label: "优先级", value: "\(prio)", monospaced: true)
                    } else {
                        DetailRow(label: "优先级", value: "默认", valueColor: DT.Color.textSecondary)
                    }
                    if provider.backoffLevel > 0 {
                        DetailRow(label: "退避等级", value: "L\(provider.backoffLevel)",
                                  valueColor: DT.Color.warning, monospaced: true)
                    }
                }
            }
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.s) {
            DetailSectionLabel(title: "连接信息", icon: "link")
            DCard(padding: DT.Space.l) {
                VStack(alignment: .leading, spacing: DT.Space.m) {
                    DetailRow(label: "类型", value: provider.providerType, monospaced: true)
                    DetailRow(label: "Base URL", value: provider.baseURL, monospaced: true)
                    if let key = provider.maskedAPIKey, !key.isEmpty {
                        DetailRow(label: "API Key") {
                            HStack(spacing: DT.Space.xs) {
                                Text(ProviderDetailCard.maskKey(key))
                                    .font(DT.Font.monoSmall)
                                    .foregroundStyle(DT.Color.textPrimary)
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DT.Color.success)
                            }
                        }
                    } else {
                        DetailRow(label: "API Key", value: "未配置", valueColor: DT.Color.textTertiary)
                    }
                }
            }
        }
    }

    private var diagnosticSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.s) {
            DetailSectionLabel(title: "诊断", icon: "stethoscope")
            DCard(padding: DT.Space.l) {
                VStack(alignment: .leading, spacing: DT.Space.m) {
                    if let last = provider.lastTested {
                        DetailRow(label: "最后测试", value: ProviderDetailCard.formatDate(last), monospaced: true)
                    } else {
                        DetailRow(label: "最后测试", value: "无", valueColor: DT.Color.textTertiary)
                    }
                    if let err = provider.lastError, !err.isEmpty {
                        DetailRow(label: "错误信息", value: err, valueColor: DT.Color.danger)
                    } else {
                        DetailRow(label: "错误信息", value: "无", valueColor: DT.Color.textTertiary)
                    }
                }
            }
        }
    }

    /// 脱敏：保留前 4 后 4，中间用 • 替代
    static func maskKey(_ key: String) -> String {
        if key.count <= 8 { return String(repeating: "•", count: key.count) }
        let head = key.prefix(4)
        let tail = key.suffix(4)
        return "\(head)••••••\(tail)"
    }

    static func formatDate(_ date: Date) -> String {
        let out = DateFormatter()
        out.dateFormat = "MM-dd HH:mm"
        return out.string(from: date)
    }
}

// MARK: - Combo 大卡片

struct ComboDetailCard: View {
    let combo: Combo
    let isActive: Bool
    let onClose: () -> Void
    let onActivate: () -> Void

    var body: some View {
        DetailCardShell(
            icon: "shuffle",
            iconColor: DT.Color.accent,
            title: combo.name,
            subtitle: "路由策略",
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: DT.Space.m) {
                overviewSection
                if !combo.models.isEmpty { modelsSection }
                if !isActive { activateButton }
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.s) {
            DetailSectionLabel(title: "概览", icon: "sparkles")
            DCard(padding: DT.Space.l) {
                VStack(alignment: .leading, spacing: DT.Space.m) {
                    DetailRow(label: "策略", value: combo.strategy, monospaced: true)
                    if let ctx = combo.contextLength {
                        DetailRow(label: "上下文", value: "\(ctx)", valueColor: DT.Color.textSecondary, monospaced: true)
                    }
                    DetailRow(label: "模型数", value: "\(combo.models.count)", monospaced: true)
                    DetailRow(label: "状态") {
                        StatusPill(text: isActive ? "已启用" : "已停用",
                                  color: isActive ? DT.Color.success : DT.Color.textSecondary)
                    }
                }
            }
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.s) {
            DetailSectionLabel(title: "模型列表", icon: "cpu")
            DCard(padding: DT.Space.l) {
                VStack(alignment: .leading, spacing: DT.Space.xs) {
                    ForEach(combo.models) { model in
                        modelRow(model)
                    }
                }
            }
        }
    }

    private func modelRow(_ model: ComboModel) -> some View {
        HStack(spacing: DT.Space.s) {
            ModelThumbnail(model: model.model, size: 22)
            Text(model.model)
                .font(DT.Font.monoSmall)
                .foregroundStyle(DT.Color.textPrimary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activateButton: some View {
        Button(action: onActivate) {
            HStack(spacing: DT.Space.s) {
                Image(systemName: "checkmark.seal.fill")
                Text("启用此策略")
                    .font(DT.Font.bodySemibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DT.Space.m)
        }
        .buttonStyle(.borderedProminent)
        .tint(DT.Color.accent)
        .controlSize(.regular)
    }
}
