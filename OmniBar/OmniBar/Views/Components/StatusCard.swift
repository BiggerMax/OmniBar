//
//  StatusCard.swift
//  OmniBar
//
//  顶部状态卡片：脉冲状态点 + 状态文字 + 版本胶囊 + Port/PID/Uptime
//

import SwiftUI

struct StatusCard: View {
    @ObservedObject var service: OmnirouteService

    var body: some View {
        DCard(padding: DT.Space.xl) {
            VStack(spacing: DT.Space.l) {
                topRow
                metricsGrid
            }
        }
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

    private var metricsGrid: some View {
        HStack(spacing: DT.Space.l) {
            metric(label: "PORT", value: "\(service.port)", ratio: 0.30)
            metric(label: "PID", value: service.pid.map(String.init) ?? "—", ratio: 0.30)
            metric(label: "UPTIME", value: formatUptime(service.uptime), accent: true, ratio: 0.40)
        }
    }

    private func metric(label: String, value: String, accent: Bool = false, ratio: CGFloat = 0.33) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DT.Font.micro)
                .foregroundStyle(DT.Color.textSecondary)
                .tracking(1.0)
            Text(value)
                .font(DT.Font.mono)
                .foregroundStyle(accent ? DT.Color.accent : DT.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // 数字滚动过渡：重启后 PID 变化能被直观看到
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.3), value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
