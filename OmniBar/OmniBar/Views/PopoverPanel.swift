//
//  PopoverPanel.swift
//  OmniBar
//
//  主面板：顶栏 / 内容 / 底部 Action Bar
//  1:1 还原 Stitch 设计：340 宽玻璃面板
//

import SwiftUI

struct PopoverPanel: View {
    @ObservedObject var service: OmnirouteService
    @ObservedObject var settings: AppSettings

    /// 路由：列表 <-> 详情大卡片
    enum Route: Equatable {
        case list
        case provider(Provider)
        case combo(Combo)
    }
    @State private var route: Route = .list

    /// 面板总宽
    private let panelWidth: CGFloat = 340
    /// 内容区实际可用宽度 = 面板宽 - 左右 padding(16*2)
    private var contentWidth: CGFloat { panelWidth - DT.Space.xl * 2 }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏：OmniBar + 设置图标
            header
            // 内容区：根据路由在「列表」与「详情大卡片」之间切换
            content
                .frame(width: panelWidth, height: 424)
                .clipped()
            // 底部固定 Action Bar
            actionBar
        }
        .frame(width: panelWidth, height: 520)
        // 背景完全交给 AppKit 层 NSVisualEffectView（StatusItemManager 中）：
        // 这里不再绘制任何背景，确保 hosting 层透明、透出控制中心同款毛玻璃。
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
        // Popover 强制浅色：白色透明玻璃风格
        .preferredColorScheme(.light)
    }

    // MARK: - 内容区（路由切换）
    @ViewBuilder
    private var content: some View {
        switch route {
        case .list:
            listContent
                .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
        case .provider(let p):
            ProviderDetailCard(provider: p, service: service) {
                withAnimation(.easeInOut(duration: 0.22)) { route = .list }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
        case .combo(let c):
            ComboDetailCard(
                combo: c,
                isActive: service.activeComboID == c.id,
                onClose: { withAnimation(.easeInOut(duration: 0.22)) { route = .list } },
                onActivate: {
                    Task {
                        _ = await service.switchCombo(to: c.id)
                        withAnimation(.easeInOut(duration: 0.22)) { route = .list }
                    }
                }
            )
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
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
                UsageSummary(usage: service.usage)
                ProviderList(providers: service.providers, service: service) { provider in
                    withAnimation(.easeInOut(duration: 0.22)) { route = .provider(provider) }
                }
                ComboSelector(service: service) { combo in
                    withAnimation(.easeInOut(duration: 0.22)) { route = .combo(combo) }
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

    // MARK: - 顶栏
    private var header: some View {
        HStack {
            Text("OmniBar")
                .font(DT.Font.headline)
                .foregroundStyle(DT.Color.textPrimary)
            Spacer()
            HStack(spacing: DT.Space.m) {
                Button(action: { openSettings() }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .foregroundStyle(DT.Color.textSecondary.opacity(0.7))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                Button(action: { openSettings() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(DT.Color.textSecondary.opacity(0.7))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, DT.Space.xl)
        .padding(.vertical, DT.Space.l)
        // 背景透明：毛玻璃由 AppKit 层 NSVisualEffectView 统一提供，保持控制中心通透感
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
            .buttonStyle(.borderless)
            .help("打开 Dashboard")
            .padding(.trailing, DT.Space.xl)
        }
        .frame(height: 56)
        .padding(.leading, DT.Space.xl)
        // 背景透明：毛玻璃由 AppKit 层 NSVisualEffectView 统一提供，保持控制中心通透感
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
        .background(DT.Color.warningSoft)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(DT.Color.warning.opacity(0.4), lineWidth: 1)
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
        .background(DT.Color.surfaceContainer)
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
        .background(DT.Color.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(DT.Color.accent.opacity(0.4), lineWidth: 1)
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
        .background(DT.Color.warningSoft)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(DT.Color.warning.opacity(0.4), lineWidth: 1)
        )
    }
}

extension Notification.Name {
    static let openOmniBarSettings = Notification.Name("openOmniBarSettings")
}
