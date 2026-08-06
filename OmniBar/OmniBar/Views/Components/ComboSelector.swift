//
//  ComboSelector.swift
//  OmniBar
//
//  Combo 选择器：自定义下拉 + 策略标签 + 模型芯片
//

import SwiftUI

struct ComboSelector: View {
    @ObservedObject var service: OmnirouteService
    @State private var isSwitching: Bool = false
    /// 内联切换下拉是否展开
    @State private var showingMenu: Bool = false
    /// 卡片是否被悬停（与 Provider 行 hover 描边一致）
    @State private var isHovering: Bool = false
    /// 路由策略区块是否折叠（点击标题切换）
    @State private var isCollapsed: Bool = false
    /// 点击卡片主体 → 打开大卡片详情
    var onSelect: (Combo) -> Void = { _ in }

    var body: some View {
        VStack(spacing: DT.Space.l) {
            sectionHeader
            if !isCollapsed {
                if service.combos.isEmpty {
                    emptyState
                } else {
                    comboCard
                }
            }
        }
    }

    /// 区块标题：点击折叠/展开整个「路由策略」区域；折叠时右侧显示当前策略名
    private var sectionHeader: some View {
        Button {
            if !isCollapsed { showingMenu = false }
            withAnimation(Motion.value) { isCollapsed.toggle() }
        } label: {
            HStack(spacing: DT.Space.s) {
                Text("路由策略 Combo")
                    .font(DT.Font.sectionLabel)
                    .foregroundStyle(DT.Color.textLabel)
                    .textCase(.uppercase)
                    .tracking(1.5)
                Spacer()
                if isCollapsed, let name = activeCombo?.name {
                    Text(name)
                        .font(DT.Font.micro)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DT.Color.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DT.Space.xs)
        .help(isCollapsed ? "展开路由策略" : "折叠路由策略")
    }

    /// 组合卡片主体（当前策略行 + 内联切换列表 + 模型芯片）
    private var comboCard: some View {
        // 对齐 HTML：Combo 卡片用 bg-white/5(surfaceElevated) + rounded-lg，
        // 与 Provider 行同一层级，而非 surfaceContainer 深色卡片
        VStack(alignment: .leading, spacing: DT.Space.l) {
            selectorRow
            // 内联切换下拉（替代系统 Menu，确保在 popover 内可点击）
            if showingMenu {
                Divider().foregroundStyle(DT.Color.stroke)
                menuList
            }
            if let active = activeCombo, !active.models.isEmpty {
                modelsRow(active)
            }
        }
        .padding(DT.Space.l)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                .fill(DT.Color.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                .strokeBorder(isHovering ? DT.Color.accent.opacity(0.28) : DT.Color.strokeVariant, lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(Motion.hover) { isHovering = hovering }
        }
        .hoverLift(scale: 1.01, glow: DT.Color.accent, radius: 6, liftDistance: 2)
        .animation(Motion.value, value: showingMenu)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var emptyState: some View {
        Text("暂无 Combo")
            .font(DT.Font.body)
            .foregroundStyle(DT.Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, DT.Space.xl)
    }

    // MARK: Combo 行：点击主体打开详情，chevron 内联展开切换列表
    private var selectorRow: some View {
        HStack(spacing: DT.Space.s) {
            // 主体：点击 → 大卡片详情
            Button(action: {
                if let combo = activeCombo { onSelect(combo) }
            }) {
                HStack(spacing: DT.Space.s) {
                    Text(activeCombo?.name ?? "选择策略")
                        .font(DT.Font.bodySemibold)
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let strategy = activeCombo?.strategyLabel {
                        // ClashMac 实心 accent 胶囊（白字）
                        DPill(text: strategy, color: DT.Color.accent)
                            .layoutPriority(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isHovering ? DT.Color.accent : DT.Color.textTertiary)
                        .offset(x: isHovering ? 2 : 0)
                        .animation(Motion.hover, value: isHovering)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 2)

            // 切换策略：点击展开内联列表
            Button(action: { withAnimation(.easeOut(duration: 0.2)) { showingMenu.toggle() } }) {
                if isSwitching {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: showingMenu ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .help("切换路由策略")
            .accessibilityLabel("切换路由策略")
        }
    }

    // MARK: 内联切换列表
    private var menuList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(sortedCombos) { combo in
                Button(action: {
                    Task {
                        isSwitching = true
                        showingMenu = false
                        _ = await service.switchCombo(to: combo.id)
                        isSwitching = false
                    }
                }) {
                    HStack(spacing: DT.Space.s) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(combo.id == service.activeComboID ? Color.white : .clear)
                            .frame(width: 14)
                        Text(combo.name)
                            .font(DT.Font.bodyMedium)
                            .foregroundStyle(combo.id == service.activeComboID ? Color.white : DT.Color.textSecondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, DT.Space.s)
                    .padding(.vertical, DT.Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(combo.id == service.activeComboID ? DT.Color.accent : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 模型芯片（带缩略图）
    private func modelsRow(_ combo: Combo) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.s) {
            FlowLayout(spacing: DT.Space.s) {
                ForEach(combo.models) { model in
                    HStack(spacing: 6) {
                        ModelThumbnail(model: model.model, size: 18)
                        Text(model.model)
                            .font(DT.Font.monoSmall)
                            .foregroundStyle(DT.Color.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DT.Space.m)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                }
            }
        }
    }

    private var sortedCombos: [Combo] {
        service.combos.sorted { (a, b) in
            (a.sortOrder ?? Int.max) < (b.sortOrder ?? Int.max)
        }
    }

    private var activeCombo: Combo? {
        service.combos.first(where: { $0.id == service.activeComboID })
        ?? sortedCombos.first
    }
}

/// 模型缩略图：根据模型名生成稳定的彩色圆形徽标（首字母）
struct ModelThumbnail: View {
    let model: String
    var size: CGFloat = 22

    /// 依模型名推断品牌色（稳定映射）
    private var tint: Color {
        let lower = model.lowercased()
        if lower.contains("gpt") || lower.contains("openai") { return Color(red: 0.10, green: 0.66, blue: 0.46) }
        if lower.contains("claude") { return Color(red: 0.85, green: 0.52, blue: 0.30) }
        if lower.contains("gemini") || lower.contains("gemma") { return Color(red: 0.26, green: 0.45, blue: 0.95) }
        if lower.contains("deepseek") { return Color(red: 0.18, green: 0.55, blue: 0.95) }
        if lower.contains("qwen") || lower.contains("tongyi") { return Color(red: 0.71, green: 0.11, blue: 0.16) }
        if lower.contains("llama") || lower.contains("meta") { return Color(red: 0.23, green: 0.55, blue: 0.95) }
        if lower.contains("mistral") { return Color(red: 0.95, green: 0.45, blue: 0.20) }
        if lower.contains("yi") || lower.contains("01") { return Color(red: 0.45, green: 0.32, blue: 0.85) }
        // 哈希兜底，保证同一模型颜色稳定
        let letters = model.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        let hue = Double(abs(letters) % 360) / 360.0
        return Color(hue: hue, saturation: 0.45, brightness: 0.62)
    }

    private var initial: String {
        let trimmed = model.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "?"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
            Text(initial)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 0.75))
    }
}


// MARK: - FlowLayout（流式布局）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 280
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = itemSize(subview, limit: maxWidth)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        // 绝不超过父级给的宽度，避免把 ScrollView 横向撑爆
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    /// 单个子项尺寸，宽度上限为容器宽度
    private func itemSize(_ subview: LayoutSubview, limit: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > limit else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: limit, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = itemSize(subview, limit: bounds.width)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
