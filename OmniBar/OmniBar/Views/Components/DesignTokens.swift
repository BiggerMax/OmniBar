//
//  DesignTokens.swift
//  OmniBar
//
//  集中管理设计 tokens（参考 666OS/ClashMac：深色玻璃拟态 + 靛蓝强调色）
//

import SwiftUI

enum DT {
    // MARK: - 颜色
    enum Color {
        // 容器与表面（ClashMac 接近黑的冷色深底）
        static let surface = SwiftUI.Color(red: 0.114, green: 0.114, blue: 0.122)         // #1D1D1F
        static let surfaceContainer = SwiftUI.Color(red: 0.145, green: 0.145, blue: 0.165) // #25252A
        static let surfaceElevated = SwiftUI.Color.white.opacity(0.06)                       // 白色/6 浅层
        static let stroke = SwiftUI.Color.white.opacity(0.08)                                // 描边
        static let strokeVariant = SwiftUI.Color.white.opacity(0.05)                         // 次级描边
        // 文字
        static let textPrimary = SwiftUI.Color.white                                         // 主文字
        static let textSecondary = SwiftUI.Color(red: 0.58, green: 0.60, blue: 0.68)         // #949AAE
        static let textTertiary = SwiftUI.Color(red: 0.58, green: 0.60, blue: 0.68).opacity(0.6)
        static let textLabel = SwiftUI.Color(red: 0.58, green: 0.60, blue: 0.68).opacity(0.8)
        // 主品牌（ClashMac 靛蓝/紫罗兰蓝）
        static let accent = SwiftUI.Color(red: 0.44, green: 0.47, blue: 0.94)                 // #7078F0
        static let accentSoft = SwiftUI.Color(red: 0.44, green: 0.47, blue: 0.94).opacity(0.20)
        // 辅助亮蓝（ClashMac 部分高亮）
        static let accentBlue = SwiftUI.Color(red: 0.22, green: 0.50, blue: 0.97)             // #3880F8
        static let warningSoft = SwiftUI.Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.15)
        // 状态
        static let success = SwiftUI.Color(red: 0.06, green: 0.73, blue: 0.51)              // #10B981
        static let warning = SwiftUI.Color(red: 0.96, green: 0.62, blue: 0.04)             // #F59E0B
        static let danger = SwiftUI.Color(red: 0.82, green: 0.20, blue: 0.16)              // #D13329
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

// MARK: - 液态玻璃（Liquid Glass）

/// 液态玻璃面板背景：ClashX 深色毛玻璃，纯高斯模糊、无彩色渐变。
/// 用作 PopoverPanel 的整块背景。
struct LiquidGlassPanel: View {
    var body: some View {
        ZStack {
            // 高斯模糊
            Rectangle().fill(.ultraThinMaterial)
            // 深色调，营造 ClashX 深色面板质感
            Rectangle().fill(Color.black.opacity(0.45))
            // 极淡蓝色微光，呼应 ClashX 蓝
            Rectangle().fill(DT.Color.accent.opacity(0.05))
        }
    }
}

/// 液态玻璃卡片底：深色半透明 + 细白描边，纯毛玻璃质感（无渐变）。
/// 让 DCard / DRow 等容器呈现 ClashX 深色玻璃质感。
private struct LiquidGlassCard: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                Rectangle().fill(Color.white.opacity(0.07))
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            )
    }
}

// MARK: - 通用 UI 组件

/// 卡片容器：液态玻璃底（半透白渐变 + 顶部内高光 + 细白描边）
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
            .modifier(LiquidGlassCard(cornerRadius: DT.Radius.card))
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
            .modifier(LiquidGlassCard(cornerRadius: DT.Radius.row))
    }
}

/// 分组小标题（uppercase tracking-widest，居左显示）
struct DSectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(DT.Font.sectionLabel)
            .foregroundStyle(DT.Color.textLabel)
            .textCase(.uppercase)
            .tracking(1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
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
