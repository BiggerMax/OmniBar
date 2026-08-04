//
//  PopoverPanel.swift
//  OmniBar
//
//  主面板：顶栏 / 内容 / 底部 Action Bar
//  ClashMac 27 暗色玻璃风格：340 宽深炭面板
//

import SwiftUI

struct PopoverPanel: View {
    @ObservedObject var service: OmnirouteService
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    /// 路由：列表 <-> 详情大卡片
    enum Route: Equatable {
        case list
        case provider(Provider)
        case combo(Combo)
    }
    @State private var route: Route = .list

    /// 面板总宽（统一从 DT.Layout 读取）
    private let panelWidth: CGFloat = DT.Layout.panelWidth
    private let panelHeight: CGFloat = DT.Layout.panelHeight
    /// 内容区实际可用宽度 = 面板宽 - 左右 padding(16*2)
    private var contentWidth: CGFloat { panelWidth - DT.Space.xl * 2 }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏：OmniBar + 设置图标
            header
            // 内容区：根据路由在「列表」与「详情大卡片」之间切换
            content
                .frame(width: panelWidth, height: DT.Layout.contentHeight)
                .clipped()
            // 底部固定 Action Bar
            actionBar
        }
        .frame(width: panelWidth, height: panelHeight)
        // 原生右键菜单 Liquid Glass：macOS 26 用 SwiftUI .glassEffect 渲染系统玻璃（与右键菜单同款），
        // 旧系统回退 .ultraThinMaterial。不再依赖 AppKit 层 NSVisualEffectView。
        .background(panelGlass)
        // 跟随系统深浅色：不再 .preferredColorScheme(.dark)，玻璃 tint / DT.Color 动态色自动适配
    }

    /// 面板背景：原生 Liquid Glass 玻璃层（tint 随系统深浅色动态切换）
    @ViewBuilder
    private var panelGlass: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: DT.Layout.panelRadius, style: .continuous)
                .fill(.clear)
                .glassEffect(
                    Glass.regular.tint(
                        colorScheme == .light
                            ? Color.white.opacity(0.25)
                            : Color.black.opacity(0.1)
                    ),
                    in: RoundedRectangle(cornerRadius: DT.Layout.panelRadius, style: .continuous)
                )
        } else {
            // 旧系统：ultraThinMaterial + 随深浅色动态的 tint，与 macOS 26 的玻璃霜感保持一致
            ZStack {
                RoundedRectangle(cornerRadius: DT.Layout.panelRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: DT.Layout.panelRadius, style: .continuous)
                    .fill(DT.Color.panelTint)
            }
        }
    }

    // MARK: - 内容区（路由切换）
    @ViewBuilder
    private var content: some View {
        switch route {
        case .list:
            listContent
                .transition(.route(edge: .leading))
        case .provider(let p):
            ProviderDetailCard(provider: p, service: service) {
                withAnimation(Motion.route) { route = .list }
            }
            .transition(.route(edge: .trailing))
        case .combo(let c):
            ComboDetailCard(
                combo: c,
                isActive: service.activeComboID == c.id,
                onClose: { withAnimation(Motion.route) { route = .list } },
                onActivate: {
                    Task {
                        _ = await service.switchCombo(to: c.id)
                        withAnimation(Motion.route) { route = .list }
                    }
                }
            )
            .transition(.route(edge: .trailing))
        }
    }

    // MARK: - 列表内容
    private var listContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: DT.Space.xxl) {
                StatusCard(service: service) {
                    Task { await service.checkForUpdate() }
                }
                if service.needsAuth {
                    authBanner
                } else if service.isUpdating {
                    updateBanner
                } else if let err = service.lastErrorMessage, !service.needsAuth {
                    errorBanner(err)
                } else if let msg = service.updateMessage, service.updateAvailable {
                    updateAvailableBanner(msg)
                }
                UsageSummary(usage: service.usage, call: service.latestCall, isRunning: service.status == .running)
                ProviderList(providers: service.providers, service: service) { provider in
                    withAnimation(Motion.route) { route = .provider(provider) }
                }
                ComboSelector(service: service) { combo in
                    withAnimation(Motion.route) { route = .combo(combo) }
                }
            }
            // 关键：硬钉死内容宽度，任何子视图都不能把 ScrollView 横向撑爆
            .frame(width: contentWidth, alignment: .leading)
            .padding(DT.Space.xl)
            .padding(.bottom, 32) // 给底部 Action Bar 留位置（收紧与路由策略的距离）
        }
        .scrollDisabled(false)
        .scrollIndicators(.hidden)
        .introspectScrollView { nssv in
            NSScrollView.omnibarHideScrollbars(nssv)
        }
    }

    // MARK: - 顶栏（ClashMac 品牌区：圆角 App 图标 + 名称 + 右侧操作）
    private var header: some View {
        HStack(spacing: DT.Space.m) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
            Text("OmniBar")
                .font(DT.Font.headline)
                .foregroundStyle(DT.Color.textPrimary)
            Spacer()
            HStack(spacing: DT.Space.m) {
                Button(action: { openSettings() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(DT.Color.textSecondary)
                        .frame(width: 22, height: 22)
                }
                .interactiveButton()
            }
        }
        .padding(.horizontal, DT.Space.xl)
        .padding(.vertical, DT.Space.l)
        // 背景透明：玻璃由根视图 .glassEffect 提供，这里只留一条细分隔线
        .overlay(
            Rectangle().fill(DT.Color.stroke).frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - 底部 Action Bar
    private var actionBar: some View {
        HStack(spacing: 0) {
            ActionButton(
                icon: "play.fill",
                label: "启动",
                color: DT.Color.accent,
                phase: phase(for: .start),
                isEnabled: service.status != .running && !service.isOperationInProgress
            ) {
                Task { _ = await service.start() }
            }

            ActionButton(
                icon: "stop.fill",
                label: "停止",
                color: DT.Color.danger,
                phase: phase(for: .stop),
                isEnabled: service.status == .running && !service.isOperationInProgress
            ) {
                Task { _ = await service.stop() }
            }

            ActionButton(
                icon: "arrow.clockwise",
                label: "重启",
                color: DT.Color.accent,
                highlighted: true,
                phase: phase(for: .restart),
                isEnabled: !service.isOperationInProgress
            ) {
                Task { _ = await service.restart() }
            }

            Spacer().frame(width: 0)

            Button(action: {
                if let url = URL(string: settings.dashboardURL) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(DT.Color.textSecondary.opacity(0.4))
            }
            .interactiveButton()
            .help("打开 Dashboard")
            .padding(.trailing, DT.Space.xl)
        }
        .frame(height: 56)
        .padding(.leading, DT.Space.xl)
        // 背景透明：玻璃由根视图 .glassEffect 提供，这里只留一条细分隔线
        .overlay(
            Rectangle().fill(DT.Color.stroke).frame(height: 0.5),
            alignment: .top
        )
    }

    /// 将 service 的操作状态映射为按钮的视觉阶段
    private func phase(for operation: ServiceOperation) -> ActionPhase {
        if service.runningOperation == operation { return .loading }
        if let result = service.lastOperationResult, result.operation == operation {
            return result.success ? .success : .failure
        }
        return .idle
    }

    private func openSettings() {
        NotificationCenter.default.post(name: .openOmniBarSettings, object: nil)
    }

    // MARK: - 健壮性提示横幅

    private var authBanner: some View {
        HStack(spacing: DT.Space.m) {
            Image(systemName: "lock.shield")
                .foregroundStyle(DT.Color.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("API 鉴权失败")
                    .font(DT.Font.bodyMedium)
                    .foregroundStyle(DT.Color.textPrimary)
                Text("请前往 偏好设置 → 连接 填写 API Key")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            Spacer()
            Button("设置") {
                openSettings()
            }
            .buttonStyle(.borderless)
            .font(DT.Font.bodyMedium)
            .foregroundStyle(DT.Color.accent)
        }
        .padding(DT.Space.m)
        .background(DT.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(DT.Color.warning.opacity(0.45), lineWidth: 1)
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: DT.Space.m) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(DT.Color.warning)
            Text(message)
                .font(DT.Font.caption)
                .foregroundStyle(DT.Color.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(DT.Space.m)
        .background(DT.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(DT.Color.stroke, lineWidth: 1)
        )
    }

    /// 更新进行中横幅
    private var updateBanner: some View {
        HStack(spacing: DT.Space.m) {
            ProgressView()
                .controlSize(.small)
                .tint(DT.Color.accent)
            Text(service.updateMessage ?? "正在更新 omniroute…")
                .font(DT.Font.caption)
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
            Spacer()
        }
        .padding(DT.Space.m)
        .background(DT.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(DT.Color.accent.opacity(0.5), lineWidth: 1)
        )
    }

    /// 发现新版本横幅：可一键更新
    private func updateAvailableBanner(_ message: String) -> some View {
        HStack(spacing: DT.Space.m) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(DT.Color.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Omniroute 可更新")
                    .font(DT.Font.bodyMedium)
                    .foregroundStyle(DT.Color.textPrimary)
                Text(message)
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("更新") {
                Task { await service.performUpdate() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DT.Color.accent)
        }
        .padding(DT.Space.m)
        .background(DT.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(DT.Color.warning.opacity(0.45), lineWidth: 1)
        )
    }
}

extension Notification.Name {
    static let openOmniBarSettings = Notification.Name("openOmniBarSettings")
}
