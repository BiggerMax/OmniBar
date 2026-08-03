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
    var service: OmnirouteService? = nil
    var onSelect: (Provider) -> Void = { _ in }

    /// 编辑模式（多选批量删除）
    @State private var isEditing = false
    @State private var selected = Set<String>()
    @State private var isDeleting = false
    @State private var pendingConfirm = false

    /// 折叠模式：默认展示前 3 个 provider，多余折叠
    private static let collapsedLimit = 3
    @State private var isExpanded = false

    var body: some View {
        // 对齐 HTML：Provider 区块无外层容器卡片，行本身是 bg-white/5 独立卡片
        // section 间距 space-3(12px)，行间距 space-2(8px)
        VStack(spacing: DT.Space.l) {
            sectionHeader
            if providers.isEmpty {
                emptyView
            } else {
                LazyVStack(alignment: .leading, spacing: DT.Space.l) {
                    ForEach(visibleRows) { row in
                        rowView(row)
                    }
                    if providers.count > Self.collapsedLimit {
                        showMoreButton
                    }
                }
            }
        }
    }

    /// 折叠模式：扁平化为「分组标题 / provider 行」序列；折叠时仅保留前 3 个 provider 行
    private var visibleRows: [Row] {
        let all = flattenedRows
        if isExpanded || providers.count <= Self.collapsedLimit {
            return all
        }
        var result: [Row] = []
        var shown = 0
        for row in all {
            switch row {
            case .header:
                result.append(row)
            case .provider:
                if shown < Self.collapsedLimit {
                    shown += 1
                    result.append(row)
                } else {
                    return result
                }
            }
        }
        return result
    }

    private var flattenedRows: [Row] {
        var rows: [Row] = []
        for group in groups {
            rows.append(.header(group.title, group.isConnectionName, activeCount(in: group.providers), group.providers.count))
            for p in group.providers {
                rows.append(.provider(p))
            }
        }
        return rows
    }

    /// 折叠切换按钮：显示剩余数量 / 收起
    private var showMoreButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: DT.Space.xs) {
                Text(isExpanded ? "收起" : "显示全部 \(providers.count - Self.collapsedLimit) 个")
                    .font(DT.Font.micro)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(DT.Color.accent)
            .padding(.horizontal, DT.Space.xs)
            .padding(.vertical, DT.Space.xs)
        }
        .buttonStyle(.borderless)
    }

    private enum Row: Identifiable {
        case header(String, Bool, Int, Int)
        case provider(Provider)

        var id: String {
            switch self {
            case .header(let title, let isRaw, _, _): return "h-\(isRaw ? "raw" : "type")-\(title)"
            case .provider(let p): return "p-\(p.id)"
            }
        }
    }

    // MARK: - 按服务商分组
    private var groups: [(title: String, isConnectionName: Bool, providers: [Provider])] {
        // 保持原始顺序：合并相同服务商类型的连接，避免打乱展示次序。
        // 通用类型（openai-compatible-chat 等）连接的真实厂商由其上游 baseURL 决定，
        // 因此按 baseURL 主机名单独成组（如 api.deepseek.com → deepseek.com）；
        // 特定类型（siliconflow / command-code 等）则按 provider 类型归并。
        var result: [(title: String, isConnectionName: Bool, providers: [Provider])] = []
        var indexById: [String: Int] = [:]
        for p in providers {
            let key = groupKey(for: p)
            // 通用类型使用「原始标题」（主机名或连接名），不做类型 slug 的标题化转换
            let isRaw = key != p.providerTypeShort
            if let i = indexById[key] {
                result[i].providers.append(p)
            } else {
                indexById[key] = result.count
                result.append((key, isRaw, [p]))
            }
        }
        return result
    }

    /// 通用类型（openai-compatible-chat 等）连接的真实厂商由其上游 baseURL 决定，
    /// 因此按 baseURL 主机名分组（如 https://api.deepseek.com/v1 → deepseek.com）；
    /// baseURL 缺失时回退到连接名（name）。特定类型按 provider 类型归并。
    private func groupKey(for p: Provider) -> String {
        guard p.providerTypeShort.lowercased().contains("openai-compatible") else {
            return p.providerTypeShort
        }
        guard let base = p.baseURL, let host = URL(string: base)?.host, !host.isEmpty else {
            return p.displayName
        }
        var h = host
        if h.hasPrefix("api.") { h = String(h.dropFirst(4)) }
        else if h.hasPrefix("www.") { h = String(h.dropFirst(5)) }
        return h
    }

    /// 单行渲染：分组标题 或 provider 行
    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .header(let title, let isConnectionName, let active, let total):
            groupHeader(title: title, isConnectionName: isConnectionName, active: active, total: total)
        case .provider(let provider):
            providerRow(provider)
        }
    }

    /// 单组：服务商标题（可读名 + 活跃/总数）+ 组内连接行
    private func groupHeader(title: String, isConnectionName: Bool, active: Int, total: Int) -> some View {
        HStack(spacing: DT.Space.s) {
            Text(isConnectionName ? title : displayName(title))
                .font(DT.Font.micro)
                .foregroundStyle(DT.Color.textLabel)
                .lineLimit(1)
            Spacer()
            Text("\(active)/\(total)")
                .font(DT.Font.monoSmall)
                .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(.horizontal, DT.Space.xs)
        .padding(.top, DT.Space.s)
    }

    /// 把 "siliconflow" / "openai-compatible-chat" 转成可读名
    private func displayName(_ type: String) -> String {
        type
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func activeCount(in list: [Provider]) -> Int {
        list.filter { $0.health == .active }.count
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
            if isEditing {
                // 编辑模式：显示已选数量 + 删除/完成
                Text("已选 \(selected.count)")
                    .font(DT.Font.monoSmall)
                    .foregroundStyle(DT.Color.textSecondary)
                Button("删除") {
                    pendingConfirm = !selected.isEmpty
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DT.Color.danger)
                .disabled(selected.isEmpty || isDeleting)
                Button("完成") {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isEditing = false
                        selected.removeAll()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(DT.Color.accent)
            } else {
                Text("\(activeCount)/\(providers.count)")
                    .font(DT.Font.monoSmall)
                    .foregroundStyle(DT.Color.textSecondary)
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(DT.Color.textTertiary)
                // 管理入口：进入多选模式
                if service != nil {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { isEditing = true }
                    } label: {
                        Image(systemName: "checklist")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    .buttonStyle(.borderless)
                    .help("批量管理")
                }
            }
        }
        .padding(.horizontal, DT.Space.xs)
        .confirmationDialog(
            "确认删除选中的 \(selected.count) 个连接？",
            isPresented: $pendingConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { performBatchDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后这些连接的 API Key 配置将永久移除，无法恢复。")
        }
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

    // MARK: - 批量删除

    private func performBatchDelete() {
        guard let service, !selected.isEmpty else { return }
        let targets = providers.filter { selected.contains($0.id) }
        isDeleting = true
        Task {
            _ = await service.deleteProviders(targets)
            isDeleting = false
            withAnimation(.easeOut(duration: 0.18)) {
                isEditing = false
                selected.removeAll()
            }
        }
    }

    // MARK: - Row
    // 对齐 HTML .provider-row：[状态图标 gap-3 名称] | [延迟 gap-3 状态胶囊]
    private func providerRow(_ provider: Provider) -> some View {
        ProviderRowView(
            provider: provider,
            isEditing: isEditing,
            isSelected: selected.contains(provider.id),
            onToggleSelect: { id in
                if selected.contains(id) {
                    selected.remove(id)
                } else {
                    selected.insert(id)
                }
            },
            onSelect: onSelect
        )
    }
}

/// 单行 Provider：封装 hover 描边状态，对齐 HTML hover:border-outline-variant/30
private struct ProviderRowView: View {
    let provider: Provider
    var isEditing: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: ((String) -> Void)? = nil
    var onSelect: (Provider) -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: {
            if isEditing {
                onToggleSelect?(provider.id)
            } else {
                onSelect(provider)
            }
        }) {
            HStack(spacing: DT.Space.l) {
                // 编辑模式：行首选择框
                if isEditing {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? DT.Color.accent : DT.Color.textTertiary)
                        .frame(width: 18)
                        .transition(.opacity)
                }

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
                            .font(DT.Font.bodySemibold)
                            .foregroundStyle(DT.Color.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(1)
                        Text(provider.providerTypeShort)
                            .font(DT.Font.monoSmall)
                            .foregroundStyle(DT.Color.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: DT.Space.s)

                // 右侧：健康圆点 + 状态文字 + 进入指示（ClashMac 低对比行样式）
                HStack(spacing: DT.Space.s) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(provider.healthColor)
                            .frame(width: 6, height: 6)
                        Text(provider.healthLabel)
                            .font(DT.Font.micro)
                            .foregroundStyle(provider.healthColor)
                    }
                    if !isEditing {
                        // 进入指示
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DT.Color.textTertiary)
                    }
                }
            }
            .padding(.horizontal, DT.Space.l - 2) // 对齐 HTML p-2.5 (10px)
            .padding(.vertical, DT.Space.m)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .fill(isSelected ? DT.Color.accent.opacity(0.18)
                          : (isHovering ? Color.white.opacity(0.10) : DT.Color.surfaceElevated))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .strokeBorder(isSelected ? DT.Color.accent.opacity(0.5)
                                   : (isHovering ? DT.Color.stroke : DT.Color.strokeVariant), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainRowButtonStyle())
        // 离线（error）整行降透明度，对齐 HTML 的 .opacity-60
        .opacity(provider.isDimmed && !isSelected ? 0.75 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
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
