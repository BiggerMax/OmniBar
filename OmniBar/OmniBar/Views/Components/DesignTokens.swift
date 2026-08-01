//
//  DesignTokens.swift
//  OmniBar
//
//  集中管理设计 tokens（1:1 还原 Stitch 设计系统：OmniBar Dark Tech）
//

import SwiftUI

enum DT {
    // MARK: - 颜色
    enum Color {
        // 容器与表面
        static let surface = SwiftUI.Color(red: 0.06, green: 0.07, blue: 0.08)            // #0F1115
        static let surfaceContainer = SwiftUI.Color(red: 0.10, green: 0.11, blue: 0.14)     // #1A1D23
        static let surfaceElevated = SwiftUI.Color.white.opacity(0.05)                       // white/5
        static let stroke = SwiftUI.Color.white.opacity(0.08)                                // outline
        static let strokeVariant = SwiftUI.Color.white.opacity(0.03)                         // outline-variant/30
        // 文字
        static let textPrimary = SwiftUI.Color.white                                         // on-surface
        static let textSecondary = SwiftUI.Color(red: 0.58, green: 0.64, blue: 0.72)        // #94A3B8
        static let textTertiary = SwiftUI.Color(red: 0.58, green: 0.64, blue: 0.72).opacity(0.6)
        static let textLabel = SwiftUI.Color(red: 0.58, green: 0.64, blue: 0.72).opacity(0.8)
        // 主品牌
        static let accent = SwiftUI.Color(red: 0.31, green: 0.62, blue: 1.0)                // #4F9DFF
        static let accentSoft = SwiftUI.Color(red: 0.31, green: 0.62, blue: 1.0).opacity(0.20)
        static let warningSoft = SwiftUI.Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.15)
        // 状态
        static let success = SwiftUI.Color(red: 0.06, green: 0.73, blue: 0.51)              // #10B981
        static let warning = SwiftUI.Color(red: 0.96, green: 0.62, blue: 0.04)             // #F59E0B
        static let danger = SwiftUI.Color(red: 0.94, green: 0.27, blue: 0.27)              // #EF4444
        static let offline = SwiftUI.Color(red: 0.39, green: 0.45, blue: 0.55)              // #64748B
        // 透明占位
        static let clear = SwiftUI.Color.clear
    }

    // MARK: - 间距
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 24
    }

    // MARK: - 圆角
    enum Radius {
        static let card: CGFloat = 12      // rounded-xl
        static let row: CGFloat = 8         // rounded-lg
        static let button: CGFloat = 12     // rounded-xl
        static let pill: CGFloat = 999
    }

    // MARK: - 字体
    enum Font {
        // headline (Space Grotesk → system rounded 替代)
        static let headline = SwiftUI.Font.system(size: 17, weight: .bold, design: .rounded)
        // 正文
        static let body = SwiftUI.Font.system(size: 13, weight: .regular)
        static let bodyMedium = SwiftUI.Font.system(size: 13, weight: .medium)
        static let bodySemibold = SwiftUI.Font.system(size: 13, weight: .semibold)
        // 标签
        static let label = SwiftUI.Font.system(size: 10, weight: .bold)
        static let sectionLabel = SwiftUI.Font.system(size: 11, weight: .bold)
        static let micro = SwiftUI.Font.system(size: 10, weight: .medium)
        // 数字（JetBrains Mono → system monospaced）
        static let mono = SwiftUI.Font.system(size: 12, weight: .regular, design: .monospaced)
        static let monoMedium = SwiftUI.Font.system(size: 12, weight: .medium, design: .monospaced)
        static let monoSmall = SwiftUI.Font.system(size: 10, weight: .regular, design: .monospaced)
        static let monoTiny = SwiftUI.Font.system(size: 9, weight: .regular, design: .monospaced)
        static let caption = SwiftUI.Font.system(size: 11, weight: .regular)
    }
}

// MARK: - 通用 UI 组件

/// 卡片容器：圆角12 + 描边 + surface-container 底色
struct DCard<Content: View>: View {
    var padding: CGFloat = DT.Space.xl
    @ViewBuilder var content: () -> Content

    init(padding: CGFloat = DT.Space.xl, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                    .fill(DT.Color.surfaceContainer)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                    .strokeBorder(DT.Color.stroke, lineWidth: 0.5)
            )
    }
}

/// 行容器：圆角8 + white/5 底 + 描边
struct DRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(DT.Space.m)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .fill(DT.Color.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .strokeBorder(DT.Color.strokeVariant, lineWidth: 0.5)
            )
    }
}

/// 分组小标题（uppercase tracking-widest）
struct DSectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(DT.Font.sectionLabel)
            .foregroundStyle(DT.Color.textLabel)
            .textCase(.uppercase)
            .tracking(1.5)
    }
}

/// 状态点
/// - `pulsing`: 是否呼吸（仅"运行中"需要，静止状态不应持续动画）
/// - `busy`: 操作进行中，向外扩散涟漪
struct StatusDot: View {
    let color: SwiftUI.Color
    var size: CGFloat = 10
    var pulsing: Bool = true
    var busy: Bool = false

    @State private var breathe = false
    @State private var rippleScale: CGFloat = 1.0
    @State private var rippleOpacity: Double = 0.0

    var body: some View {
        ZStack {
            // 操作进行中：向外扩散的涟漪
            if busy {
                Circle()
                    .stroke(color, lineWidth: 1.2)
                    .frame(width: size, height: size)
                    .scaleEffect(rippleScale)
                    .opacity(rippleOpacity)
            }

            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .scaleEffect(breathe ? 1.12 : 1.0)
                .opacity(breathe ? 0.55 : 1.0)
                .shadow(color: color.opacity(busy ? 0.7 : 0.45), radius: busy ? 5 : 3)
        }
        // 颜色切换平滑过渡，避免状态跳变时突兀
        .animation(.easeInOut(duration: 0.35), value: color)
        .onAppear { syncAnimations() }
        .onChange(of: pulsing) { _, _ in syncAnimations() }
        .onChange(of: busy) { _, _ in syncAnimations() }
    }

    private func syncAnimations() {
        // 呼吸：仅运行中开启
        if pulsing {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.25)) { breathe = false }
        }

        // 涟漪：仅操作进行中开启
        if busy {
            rippleScale = 1.0
            rippleOpacity = 0.8
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                rippleScale = 2.4
                rippleOpacity = 0.0
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { rippleOpacity = 0.0 }
            rippleScale = 1.0
        }
    }
}

/// 状态胶囊
struct StatusPill: View {
    let text: String
    let color: SwiftUI.Color

    var body: some View {
        Text(text)
            .font(DT.Font.label)
            .foregroundStyle(color)
            .padding(.horizontal, DT.Space.m)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.10)))
    }
}
