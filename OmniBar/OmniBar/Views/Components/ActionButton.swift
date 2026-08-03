//
//  ActionButton.swift
//  OmniBar
//
//  底部 Action Bar 的操作按钮：按压回弹 + 加载动画 + 成功/失败瞬时反馈
//

import SwiftUI

/// 操作按钮的视觉阶段
enum ActionPhase: Equatable {
    case idle
    case loading
    case success
    case failure
}

struct ActionButton: View {
    let icon: String
    let label: String
    let color: SwiftUI.Color
    var highlighted: Bool = false
    var phase: ActionPhase = .idle
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isPressed = false
    @State private var isHovering = false
    /// 重启图标的持续旋转角度
    @State private var spinAngle: Double = 0
    /// 成功/失败反馈的弹跳缩放
    @State private var feedbackPop = false

    private var isBusy: Bool { phase == .loading }

    /// 当前应显示的图标（加载/成功/失败时替换）
    private var displayIcon: String {
        switch phase {
        case .idle, .loading: return icon
        case .success: return "checkmark"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    /// 当前图标颜色
    private var iconColor: SwiftUI.Color {
        guard isEnabled || isBusy else { return DT.Color.textSecondary.opacity(0.25) }
        switch phase {
        case .success: return DT.Color.success
        case .failure: return DT.Color.danger
        case .idle, .loading: return color
        }
    }
    /// 图标底板背景
    private var backgroundStyle: AnyShapeStyle {
        switch phase {
        case .success: return AnyShapeStyle(DT.Color.success.opacity(0.18))
        case .failure: return AnyShapeStyle(DT.Color.danger.opacity(0.18))
        case .loading: return AnyShapeStyle(color.opacity(0.16))
        case .idle:
            if !isEnabled { return AnyShapeStyle(SwiftUI.Color.clear) }
            if isHovering { return AnyShapeStyle(color.opacity(0.16)) }
            // ClashMac 分段控制感：常驻白色 5% 底板，重启态用 accent 20%
            return highlighted ? AnyShapeStyle(DT.Color.accent.opacity(0.20)) : AnyShapeStyle(SwiftUI.Color.white.opacity(0.05))
        }
    }

    var body: some View {
        Button(action: triggerAction) {
            VStack(spacing: DT.Space.xxs) {
                iconPlate
                Text(label.uppercased())
                    .font(DT.Font.label)
                    .foregroundStyle(labelColor)
                    .tracking(1.5)
                    .animation(.easeOut(duration: 0.2), value: phase)
                    .animation(.easeOut(duration: 0.2), value: isEnabled)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        // 按压回弹：整体轻微缩小，松开时用弹簧回弹
        .scaleEffect(isPressed ? 0.90 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: isPressed)
        .onHover { hovering in
            guard isEnabled else {
                isHovering = false
                return
            }
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
        // 用手势捕捉按下/抬起，Button 自身无法提供持续的 pressed 状态
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled, !isPressed else { return }
                    isPressed = true
                }
                .onEnded { _ in isPressed = false }
        )
        .onChange(of: phase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { isHovering = false }
        }
    }

    // MARK: - 图标底板

    private var iconPlate: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DT.Radius.button, style: .continuous)
                .fill(backgroundStyle)

            // 加载时的环形进度圈，包裹在图标外侧
            if isBusy {
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        color.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                    )
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(spinAngle))
            }

            Image(systemName: displayIcon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(iconColor)
                // 重启按钮在加载时持续自转，其它按钮保持静止
                .rotationEffect(.degrees(isBusy && icon == "arrow.clockwise" ? spinAngle : 0))
                .scaleEffect(feedbackPop ? 1.28 : 1.0)
                // 图标切换用缩放+透明淡入淡出，避免生硬替换
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .id(displayIcon)
        }
        .frame(width: 28, height: 28)
        .animation(.spring(response: 0.32, dampingFraction: 0.6), value: phase)
        .animation(.easeOut(duration: 0.18), value: isHovering)
    }

    private var iconSize: CGFloat {
        phase == .success ? 15 : 16
    }

    private var labelColor: SwiftUI.Color {
        guard isEnabled || isBusy else { return DT.Color.textSecondary.opacity(0.25) }
        switch phase {
        case .success: return DT.Color.success.opacity(0.95)
        case .failure: return DT.Color.danger.opacity(0.95)
        case .loading: return DT.Color.textSecondary.opacity(0.85)
        case .idle: return DT.Color.textSecondary.opacity(isHovering ? 0.9 : 0.7)
        }
    }

    // MARK: - 交互与动画驱动

    private func triggerAction() {
        guard isEnabled else { return }
        // 触觉反馈，贴合 macOS 原生手感
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        action()
    }

    private func handlePhaseChange(_ newPhase: ActionPhase) {
        switch newPhase {
        case .loading:
            spinAngle = 0
            // 线性持续旋转
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                spinAngle = 360
            }
        case .success, .failure:
            // 结束旋转并做一次弹跳强调
            withAnimation(.easeOut(duration: 0.2)) { spinAngle = 0 }
            feedbackPop = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) {
                feedbackPop = false
            }
        case .idle:
            withAnimation(.easeOut(duration: 0.2)) { spinAngle = 0 }
            feedbackPop = false
        }
    }
}
