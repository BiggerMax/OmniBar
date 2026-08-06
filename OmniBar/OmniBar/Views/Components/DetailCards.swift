//
//  DetailCards.swift
//  OmniBar
//
//  Provider / Combo 的「大卡片」详情视图。
//  由 PopoverPanel 的路由驱动：点击列表中的小卡片后展示。
//

import SwiftUI
import AppKit

// MARK: - NSScrollView 内省辅助
// 纯原生方式：找到 SwiftUI ScrollView 底层的 NSScrollView 并强制关闭滚动条。
// macOS 上 showsIndicators: false / .scrollIndicators(.hidden) 在通过 NSHostingView
// 嵌入 NSPanel 时偶发失效，此为兜底。
//
// 关键点 1：introspect 视图是 ScrollView 的「兄弟节点」，NSScrollView 位于其祖先的子树中，
// 因此必须沿祖先链逐层向下搜索（只向上查或只搜自身子树都会漏掉，导致配置永不生效）。
//
// 关键点 2：路由切换（列表 <-> 详情）时 SwiftUI 会同时保留新旧两个 ScrollView，且会
// 在自己的 layout 周期里重置滚动条状态。因此这里遍历整棵窗口子树，对「所有」
// NSScrollView 一律强制隐藏，并在挂载初期用短定时器持续压制，直到稳定。

private final class ScrollViewIntrospectView: NSView {
    var configure: ((NSScrollView) -> Void)?

    private var isApplying = false
    private var retryTimer: Timer?

    /// 挂载进窗口时立即尝试，并延迟重试数次（挂载初期兄弟 NSScrollView 可能尚未构建）
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        applyConfiguration()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.applyConfiguration() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.applyConfiguration() }
        // 路由过渡动画约 0.22s；在过渡期间持续压制，确保新挂载的 ScrollView 也被覆盖
        startRetryTimer()
    }

    deinit {
        retryTimer?.invalidate()
    }

    /// 挂载后短暂定时重试：SwiftUI 在 layout 周期里可能重置滚动条，这里在动画窗口内反复压制
    private func startRetryTimer() {
        retryTimer?.invalidate()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.applyConfiguration()
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
        // 动画结束后自动停止，避免常驻定时器
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.retryTimer?.invalidate()
            self?.retryTimer = nil
        }
    }

    // 注意：不要在这里 override layout() 去 applyConfiguration()。
    // ScrollView 内容滚动/重排会持续触发本视图的 layout()，每次全窗口遍历
    // 并重置 contentInsets，会造成内容在滚动中跳动偏移。隐藏滚动条只需在
    // 挂载 + 路由过渡窗口内（viewDidMoveToWindow + retry timer）配置一次。

    func applyConfiguration() {
        guard !isApplying, let configure, let window else { return }
        isApplying = true
        // 遍历窗口整棵子树，对「所有」NSScrollView 强制应用（幂等）。
        // 只配最近的一个会在路由过渡期间配到错误的旧实例，导致详情页滚动条复活。
        if let contentView = window.contentView {
            Self.applyToAllScrollViews(in: contentView, configure: configure)
        }
        isApplying = false
    }

    private static func applyToAllScrollViews(in view: NSView?, configure: (NSScrollView) -> Void) {
        guard let view else { return }
        if let sv = view as? NSScrollView {
            configure(sv)
        }
        for sub in view.subviews {
            applyToAllScrollViews(in: sub, configure: configure)
        }
    }
}

private struct ScrollViewIntrospect: NSViewRepresentable {
    let configure: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollViewIntrospectView()
        view.configure = configure
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ScrollViewIntrospectView else { return }
        view.configure = configure
        view.applyConfiguration()
    }
}

extension View {
    /// 拿到 SwiftUI ScrollView 底层的 NSScrollView 进行自定义配置
    func introspectScrollView(_ configure: @escaping (NSScrollView) -> Void) -> some View {
        overlay(ScrollViewIntrospect(configure: configure).frame(width: 0, height: 0).allowsHitTesting(false))
    }
}

/// 统一隐藏滚动条：全部页面共用，避免各页面配置漂移。
/// 关键点：仅 hasVerticalScroller = false 不够——系统「始终显示滚动条」模式下
/// NSScrollView 使用 legacy 滚动条并预留约 15px 宽度，隐藏后 clip view 仍按预留
/// 宽度布局，导致内容整体偏左、右侧留出空缺。因此必须：
/// 1. scrollerStyle = .overlay（overlay 不占位）
/// 2. 关闭 automaticallyAdjustsContentInsets 并清零 contentInsets
extension NSScrollView {
    static func omnibarHideScrollbars(_ sv: NSScrollView) {
        sv.hasVerticalScroller = false
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = false
        // overlay 风格滚动条不占用内容宽度
        sv.scrollerStyle = .overlay
        // 关闭系统自动 content insets，内容重新占满全宽（修复隐藏滚动条后内容偏左）
        sv.automaticallyAdjustsContentInsets = false
        sv.contentInsets = NSEdgeInsets()
    }
}

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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DT.Space.m) {
                headerRow
                content()
            }
            .padding(DT.Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.hidden)
        .introspectScrollView { nssv in
            NSScrollView.omnibarHideScrollbars(nssv)
        }
    }

    private var headerRow: some View {
        HStack(spacing: DT.Space.s) {
            // 返回按钮居左
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(DT.Color.accentSoft))
            }
            .buttonStyle(.plain)
            .help("返回列表")
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
        }
    }
}

// MARK: - Provider 大卡片

struct ProviderDetailCard: View {
    let provider: Provider
    var service: OmnirouteService? = nil
    let onClose: () -> Void

    @State private var pendingDelete = false
    /// API Key 是否明文显示
    @State private var showAPIKey = false
    /// 复制成功反馈
    @State private var keyCopied = false

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
                if service != nil { actionsSection }
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
                    // 只展示真实上游地址；连接未配置上游时不虚构（不用网关地址冒充）
                    if let base = provider.baseURL, !base.isEmpty {
                        DetailRow(label: "Base URL", value: base, monospaced: true)
                    } else {
                        DetailRow(label: "Base URL", value: "未配置", valueColor: DT.Color.textTertiary, monospaced: true)
                    }
                    if let key = provider.maskedAPIKey, !key.isEmpty {
                        DetailRow(label: "API Key") { apiKeyRow(key) }
                    } else {
                        DetailRow(label: "API Key", value: "未配置", valueColor: DT.Color.textTertiary)
                    }
                }
            }
        }
    }

    /// API Key 行：默认脱敏，可切换显示 + 复制。
    /// 注意：omniroute 接口只返回脱敏 Key（本地存储亦加密），完整 Key 无法通过接口获取，
    /// 此处展示的是 omniroute 实际返回的值。
    private func apiKeyRow(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DT.Space.xs) {
                // 始终可选中：脱敏态选中的是脱敏值，显示态选中服务器返回的值
                Text(showAPIKey ? key : ProviderDetailCard.maskKey(key))
                    .font(DT.Font.monoSmall)
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: DT.Space.s)
                // 复制（自动切到显示态后复制服务器返回值）
                Button {
                    copyAPIKey(key)
                } label: {
                    Image(systemName: keyCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(keyCopied ? DT.Color.success : DT.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .help("复制 API Key")
                // 显示 / 隐藏切换
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { showAPIKey.toggle() }
                } label: {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(DT.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .help(showAPIKey ? "隐藏 API Key" : "显示 API Key")
            }
            if showAPIKey {
                Text("omniroute 仅提供脱敏 Key（完整 Key 不通过接口返回）")
                    .font(DT.Font.micro)
                    .foregroundStyle(DT.Color.textTertiary)
            }
        }
    }

    private func copyAPIKey(_ key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        showAPIKey = true
        keyCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { keyCopied = false }
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

    // MARK: - 操作区

    @ViewBuilder
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.s) {
            DetailSectionLabel(title: "操作", icon: "slider.horizontal.3")
            if pendingDelete {
                deleteConfirm
            } else {
                primaryActions
            }
            if let msg = service?.providerOperationMessage {
                Text(msg)
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DT.Space.xs)
                    .transition(.opacity)
            }
        }
    }

    private var primaryActions: some View {
        VStack(spacing: DT.Space.m) {
            actionButton(icon: "wave.3.right", title: "测试连接", tint: DT.Color.accent) {
                guard let s = service else { return }
                Task { _ = await s.testProvider(provider) }
            }
            if provider.isActive {
                actionButton(icon: "pause.circle", title: "停用连接", tint: DT.Color.warning) {
                    guard let s = service else { return }
                    Task { _ = await s.setProviderActive(provider, active: false) }
                }
            } else {
                actionButton(icon: "play.circle", title: "启用连接", tint: DT.Color.success) {
                    guard let s = service else { return }
                    Task { _ = await s.setProviderActive(provider, active: true) }
                }
            }
            priorityRow
            actionButton(icon: "trash", title: "删除连接", tint: DT.Color.danger) {
                pendingDelete = true
            }
        }
    }

    private var priorityRow: some View {
        HStack(spacing: DT.Space.s) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 13))
                .foregroundStyle(DT.Color.textSecondary)
            Text("优先级")
                .font(DT.Font.bodyMedium)
                .foregroundStyle(DT.Color.textPrimary)
            Spacer()
            Button { adjustPriority(by: -1) } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .semibold)).frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(service?.providerOperationInProgress ?? true)
            Text("\(provider.priority ?? 0)")
                .font(DT.Font.monoMedium)
                .foregroundStyle(DT.Color.textPrimary)
                .frame(width: 24)
            Button { adjustPriority(by: 1) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(service?.providerOperationInProgress ?? true)
        }
        .padding(.horizontal, DT.Space.l)
        .padding(.vertical, DT.Space.m)
        .background(RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous).fill(DT.Color.surfaceElevated))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous).strokeBorder(DT.Color.strokeVariant, lineWidth: 0.5))
    }

    private func adjustPriority(by delta: Int) {
        guard let s = service else { return }
        let current = provider.priority ?? 0
        let next = max(0, current + delta)
        Task { _ = await s.setProviderPriority(provider, priority: next) }
    }

    /// 删除二次确认
    private var deleteConfirm: some View {
        VStack(spacing: DT.Space.m) {
            HStack(spacing: DT.Space.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DT.Color.danger)
                Text("确认删除「\(provider.displayName)」？")
                    .font(DT.Font.bodyMedium)
                    .foregroundStyle(DT.Color.textPrimary)
            }
            Text("删除后该连接的 API Key 配置将永久移除，无法恢复。")
                .font(DT.Font.caption)
                .foregroundStyle(DT.Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DT.Space.m) {
                Button("取消") { pendingDelete = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Button("删除") {
                    pendingDelete = false
                    guard let s = service else { return }
                    Task {
                        let ok = await s.deleteProvider(provider)
                        if ok { onClose() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DT.Color.danger)
                .controlSize(.small)
            }
        }
        .padding(DT.Space.l)
        .background(RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous).fill(DT.Color.danger.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous).strokeBorder(DT.Color.danger.opacity(0.3), lineWidth: 0.5))
    }

    /// 通用操作按钮（全宽）
    private func actionButton(icon: String, title: String, tint: SwiftUI.Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DT.Space.s) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(tint)
                Text(title)
                    .font(DT.Font.bodyMedium)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DT.Space.l)
            .padding(.vertical, DT.Space.m)
            .background(RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous).fill(DT.Color.surfaceElevated))
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous).strokeBorder(DT.Color.strokeVariant, lineWidth: 0.5))
        }
        .buttonStyle(.borderless)
        .disabled(service?.providerOperationInProgress ?? true)
        .opacity((service?.providerOperationInProgress ?? false) ? 0.5 : 1.0)
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
