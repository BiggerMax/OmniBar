//
//  Motion.swift
//  OmniBar
//
//  统一的「交互/动效系统」：
//  - Motion：集中管理弹簧/缓动时钟，保证全 App 手感一致
//  - AnyTransition.route：列表 <-> 详情大卡片的滑动 + 缩放 + 淡入淡出
//  - hoverLift：卡片/行的「上浮 + 辉光」悬停反馈
//  - InteractiveButtonStyle：小图标按钮的按压缩放 + 底衬反馈
//

import SwiftUI
import AppKit

// MARK: - 统一的动效时钟
enum Motion {
    /// 弹簧：悬停/按压等轻量、带一点回弹的交互
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.68)
    /// 弹簧：更强的强调（进出场 / 状态切换）
    static let bouncy = Animation.spring(response: 0.38, dampingFraction: 0.60)
    /// 路由切换：高阻尼、几乎无回弹，平滑柔和（页面跳转用）
    static let route = Animation.spring(response: 0.34, dampingFraction: 0.90)
    /// 数值/状态缓动
    static let value = Animation.easeOut(duration: 0.28)
    /// 悬停提亮
    static let hover = Animation.easeOut(duration: 0.18)
    /// 路由切换时长（与 route 过渡配合）
    static let routeDuration: Double = 0.28
}

// MARK: - 路由过渡（滑动 + 缩放 + 淡入淡出）
extension AnyTransition {
    /// 列表 <-> 详情大卡片的统一过渡。
    /// 进场：同方向滑动 + 轻微缩放 + 淡入；退场：同方向滑动 + 淡出。
    /// scale 接近 1 以减弱回弹观感。
    static func route(edge: Edge) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: edge)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.988)),
            removal: .move(edge: edge)
                .combined(with: .opacity)
        )
    }
}

// MARK: - 悬停上浮 + 辉光
private struct HoverLiftModifier: ViewModifier {
    @State private var isHovered = false
    var scale: CGFloat
    var glow: SwiftUI.Color
    var radius: CGFloat
    var liftDistance: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .shadow(
                color: isHovered ? glow.opacity(0.35) : .clear,
                radius: isHovered ? radius : 0,
                y: isHovered ? liftDistance : 0
            )
            .animation(Motion.spring, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    /// 卡片/行的「上浮 + 辉光」悬停反馈。
    /// - scale: 悬停时轻微放大
    /// - glow: 辉光颜色（默认强调色）
    /// - radius / liftDistance: 辉光强度与上浮距离
    func hoverLift(
        scale: CGFloat = 1.015,
        glow: SwiftUI.Color = DT.Color.accent,
        radius: CGFloat = 8,
        liftDistance: CGFloat = 4
    ) -> some View {
        modifier(HoverLiftModifier(scale: scale, glow: glow, radius: radius, liftDistance: liftDistance))
    }
}

// MARK: - 小图标/普通按钮的交互反馈
struct InteractiveButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 7
    var hoverTint: SwiftUI.Color = DT.Color.surfaceElevated

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? hoverTint.opacity(0.9) : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(Motion.spring, value: configuration.isPressed)
    }
}

extension View {
    /// 给小图标/普通按钮套用统一的按压反馈
    func interactiveButton() -> some View {
        buttonStyle(InteractiveButtonStyle())
    }
}
