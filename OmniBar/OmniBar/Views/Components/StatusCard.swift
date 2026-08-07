//
//  StatusCard.swift
//  OmniBar
//
//  顶部状态卡片：脉冲状态点 + 状态文字 + 版本胶囊 + Port/PID/Uptime
//

import SwiftUI

struct StatusCard: View {
    @ObservedObject var service: OmnirouteService
    var onCheckUpdate: () -> Void = {}

    var body: some View {
        DCard(padding: DT.Space.xl) {
            VStack(spacing: DT.Space.l) {
                topRow
                metricsGrid
                tunnelRow
            }
        }
    }

    // MARK: - 隧道开关
    private var tunnelRow: some View {
        HStack(spacing: DT.Space.m) {
            Image(systemName: "network")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(service.tunnelRunning ? DT.Color.success : DT.Color.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text("隧道")
                    .font(DT.Font.statLabel)
                    .foregroundStyle(DT.Color.textLabel)
                    .tracking(1.0)
                Text(tunnelSubtitle)
                    .font(DT.Font.micro)
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { service.tunnelRunning },
                set: { newValue in
                    Task { _ = await service.setTunnel(enabled: newValue) }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            // 开关颜色跟随隧道状态：运行时绿色、切换中黄色、待开启时强调蓝
            .tint(tunnelTint)
            .animation(Motion.value, value: service.tunnelRunning)
            .animation(Motion.value, value: service.tunnelOperationInProgress)
            .disabled(service.status != .running || service.tunnelOperationInProgress)
        }
        .padding(.horizontal, DT.Space.s)
        .padding(.vertical, DT.Space.s)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                .fill(DT.Color.surfaceElevated.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                .strokeBorder(DT.Color.strokeVariant, lineWidth: 0.5)
        )
    }

    private var tunnelSubtitle: String {
        if service.status != .running { return "服务未运行" }
        if service.tunnelOperationInProgress { return "正在切换…" }
        if service.tunnelRunning {
            return service.tunnelPublicURL
        }
        return "点击开启公网访问"
    }

    /// 隧道开关颜色：切换中=警告黄，运行时=成功绿，待开启=强调蓝
    private var tunnelTint: SwiftUI.Color {
        if service.tunnelOperationInProgress { return DT.Color.warning }
        return service.tunnelRunning ? DT.Color.success : DT.Color.accent
    }

    private var topRow: some View {
        HStack {
            HStack(spacing: DT.Space.s) {
                StatusDot(
                    color: dotColor,
                    size: 10,
                    pulsing: service.status == .running,
                    busy: service.isOperationInProgress
                )
                Text(statusLabel)
                    .font(DT.Font.bodySemibold)
                    .foregroundStyle(DT.Color.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: statusLabel)
                    .id(statusLabel)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            Spacer()
            if service.needsAuth {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 11))
                    Text("需 API Key")
                        .font(DT.Font.micro)
                }
                .foregroundStyle(DT.Color.warning)
                .padding(.horizontal, DT.Space.s)
                .padding(.vertical, 2)
                .background(Capsule().fill(DT.Color.warningSoft))
            } else if service.updateAvailable {
                Button(action: onCheckUpdate) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 11))
                        Text("v\(service.version)")
                            .font(DT.Font.monoSmall)
                    }
                    .foregroundStyle(DT.Color.warning)
                    .padding(.horizontal, DT.Space.s)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DT.Color.warningSoft))
                }
                .buttonStyle(.borderless)
                .help("发现新版本，点击检查/更新")
            } else {
                Text("v\(service.version)")
                    .font(DT.Font.monoSmall)
                    .foregroundStyle(DT.Color.textSecondary)
                    .padding(.horizontal, DT.Space.s)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DT.Color.surfaceElevated))
            }
        }
    }

    // MARK: - 指标区（ClashMac bento 风格：小标签 + 大号等宽数字）
    private var metricsGrid: some View {
        HStack(spacing: DT.Space.l) {
            metric(label: "PORT", value: "\(service.port)")
            metric(label: "PID", value: service.pid.map(String.init) ?? "—")
            // UPTIME 用 TimelineView 每秒局部刷新，只重建这一格：
            // 避免 service.uptime 作为 @Published 每秒触发 PopoverPanel 整棵树重算。
            TimelineView(.periodic(from: .now, by: 1)) { context in
                metric(label: "UPTIME", value: uptimeText(at: context.date), accent: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 由 startedAt 实时计算运行时长；服务未运行时显示 "00:00"（与旧 uptime=0 行为一致）
    private func uptimeText(at now: Date) -> String {
        guard let started = service.startedAt, service.status == .running else { return "00:00" }
        return formatUptime(now.timeIntervalSince(started))
    }

    private func metric(label: String, value: String, accent: Bool = false) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(DT.Font.statLabel)
                .foregroundStyle(DT.Color.textSecondary)
                .tracking(1.0)
            Text(value)
                .font(DT.Font.monoMedium)
                .foregroundStyle(accent ? DT.Color.accent : DT.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // 数字滚动过渡：重启后 PID 变化能被直观看到
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.3), value: value)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var dotColor: SwiftUI.Color {
        service.needsAuth ? DT.Color.warning : service.status.color
    }

    private var statusLabel: String {
        service.needsAuth ? "鉴权失败" : service.status.label
    }

    private func formatUptime(_ interval: TimeInterval) -> String {
        let sec = Int(interval)
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
