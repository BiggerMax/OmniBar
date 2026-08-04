//
//  DesignTokens.swift
//  OmniBar
//
//  集中管理设计 tokens（参考 666OS/ClashMac：深色玻璃拟态 + 靛蓝强调色）
//

import SwiftUI
import AppKit

enum DT {
    // MARK: - 颜色
    // 所有颜色均为动态色（跟随 appearance 自动切换浅/深色值）。
    // dark 分支按 ClashMac 27 风格：深炭底 + 白 5-7% 卡片 + 白 8-10% 细描边 + 靛蓝强调。
    enum Color {
        // ---- 表面（light: 高透明白色玻璃 / dark: 深炭 #121214 系）----
        static let surface = dynamicColor(
            light: SwiftUI.Color.white.opacity(0.10),
            dark: SwiftUI.Color(red: 0.071, green: 0.071, blue: 0.078)   // #121214
        )
        static let surfaceContainer = dynamicColor(
            light: SwiftUI.Color.white.opacity(0.14),
            dark: SwiftUI.Color(red: 0.110, green: 0.110, blue: 0.125)   // #1C1C20
        )
        // 卡片浅层（light: 半透明白底卡片 / dark: 白 6% 浅层）
        static let surfaceElevated = dynamicColor(
            light: SwiftUI.Color.white.opacity(0.28),
            dark: SwiftUI.Color.white.opacity(0.06)
        )
        // 描边（light: 黑 12% / dark: 白 8-10%）
        static let stroke = dynamicColor(
            light: SwiftUI.Color.black.opacity(0.14),
            dark: SwiftUI.Color.white.opacity(0.10)
        )
        static let strokeVariant = dynamicColor(
            light: SwiftUI.Color.black.opacity(0.09),
            dark: SwiftUI.Color.white.opacity(0.08)
        )
        // ---- 文字（macOS 26 语义色：.primary/.secondary 在玻璃上自动应用 Vibrancy）----
        // 直接使用 SwiftUI 语义色，Liquid Glass 背景上会自动做活力补偿与智能调色，
        // 无需再按深浅色手写十六进制（light/dark 分支一并语义化）。
        static let textPrimary = SwiftUI.Color.primary
        static let textSecondary = SwiftUI.Color.secondary
        // 三级文字用系统语义 tertiaryLabelColor：层级语义与 .primary/.secondary 一致，
        // 且不会因为二次降透明度在小字（monoSmall/micro）上过暗
        static let textTertiary = SwiftUI.Color(nsColor: .tertiaryLabelColor)
        static let textLabel = SwiftUI.Color.secondary
        // ---- 主品牌（ClashMac 靛蓝，Active 态作实心胶囊）----
        static let accent = dynamicColor(
            light: SwiftUI.Color(red: 0.35, green: 0.40, blue: 0.93),    // 浅色底略深
            dark: SwiftUI.Color(red: 0.298, green: 0.431, blue: 0.961)   // #4C6EF5
        )
        static let accentSoft = dynamicColor(
            light: SwiftUI.Color(red: 0.35, green: 0.40, blue: 0.93).opacity(0.14),
            dark: SwiftUI.Color(red: 0.298, green: 0.431, blue: 0.961).opacity(0.18)
        )
        static let accentBlue = SwiftUI.Color(red: 0.22, green: 0.50, blue: 0.97) // #3880F8
        static let warningSoft = dynamicColor(
            light: SwiftUI.Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.18),
            dark: SwiftUI.Color(red: 1.00, green: 0.84, blue: 0.04).opacity(0.16)
        )
        // ---- 状态（浅色加深饱和 / 深色提亮）----
        static let success = dynamicColor(
            light: SwiftUI.Color(red: 0.03, green: 0.58, blue: 0.41),
            dark: SwiftUI.Color(red: 0.188, green: 0.820, blue: 0.345)   // #30D158
        )
        static let warning = dynamicColor(
            light: SwiftUI.Color(red: 0.82, green: 0.52, blue: 0.02),
            dark: SwiftUI.Color(red: 1.000, green: 0.839, blue: 0.039)   // #FFD60A
        )
        static let danger = dynamicColor(
            light: SwiftUI.Color(red: 0.72, green: 0.17, blue: 0.13),
            dark: SwiftUI.Color(red: 1.000, green: 0.271, blue: 0.227)   // #FF453A
        )
        static let offline = SwiftUI.Color(red: 0.42, green: 0.48, blue: 0.58)  // #6B7A94
        // 透明占位
        static let clear = SwiftUI.Color.clear

        // ---- 面板（macOS 26 原生 Liquid Glass：.glassEffect 玻璃的 tint 色）----
        // 深色霜感：在保持玻璃透视的前提下压深背景（比原生菜单略暗，ClashMac 深炭风格）；
        // 浅色为高透明白色霜感。动态色随系统深浅色自动切换。
        static let panelTint = dynamicColor(
            light: SwiftUI.Color.white.opacity(0.10),
            dark: SwiftUI.Color(red: 0.055, green: 0.063, blue: 0.086).opacity(0.1)
        )
        // 面板边缘：玻璃折射高光——顶部亮、底部隐，营造「浮在桌面上」的薄片感。
        // 浅色底用白色高光 + 轻微黑边；深色底用白高光渐隐。
        static let glassBorderTop = dynamicColor(
            light: SwiftUI.Color.white.opacity(0.6),
            dark: SwiftUI.Color.white.opacity(0.22)
        )
        static let glassBorderBottom = dynamicColor(
            light: SwiftUI.Color.black.opacity(0.10),
            dark: SwiftUI.Color.white.opacity(0.06)
        )

        /// 构造跟随 appearance 的动态颜色
        private static func dynamicColor(light: SwiftUI.Color, dark: SwiftUI.Color) -> SwiftUI.Color {
            let nsLight = NSColor(light)
            let nsDark = NSColor(dark)
            let dynamic = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? nsDark : nsLight
            }
            return SwiftUI.Color(nsColor: dynamic)
        }
    }
    // MARK: - 布局（SwiftUI 与 AppKit 面板共用的尺寸常量）
    enum Layout {
        static let panelWidth: CGFloat = 340
        static let panelHeight: CGFloat = 560
        static let contentHeight: CGFloat = 464
        static let panelRadius: CGFloat = 10   // 原生右键菜单 Liquid Glass 圆角
        static let settingsWidth: CGFloat = 613
        static let settingsHeight: CGFloat = 453
    }

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
        static let label = SwiftUI.Font.system(size: 11, weight: .bold)
        static let sectionLabel = SwiftUI.Font.system(size: 11, weight: .bold)
        static let micro = SwiftUI.Font.system(size: 10, weight: .medium)
        // 数字（JetBrains Mono → system monospaced）
        static let mono = SwiftUI.Font.system(size: 12, weight: .regular, design: .monospaced)
        static let monoMedium = SwiftUI.Font.system(size: 12, weight: .medium, design: .monospaced)
        static let monoSmall = SwiftUI.Font.system(size: 11, weight: .regular, design: .monospaced)
        static let monoTiny = SwiftUI.Font.system(size: 10, weight: .medium, design: .monospaced)
        static let caption = SwiftUI.Font.system(size: 11, weight: .regular)
        // bento 统计数字（ClashMac：大号等宽数字 + 小号上标签）
        static let statNumber = SwiftUI.Font.system(size: 20, weight: .semibold, design: .monospaced)
        static let statLabel = SwiftUI.Font.system(size: 10, weight: .bold)
    }
}

// MARK: - 液态玻璃（Liquid Glass）

/// 液态玻璃卡片底：原生 .ultraThinMaterial 材质（macOS 26 自动渲染为 Liquid Glass 卡片）+ 细描边。
/// 浅色 = 白底卡片；深色 = 顶亮底隐的渐变描边，让卡片像嵌在玻璃面板里的半透明浮层。
private struct LiquidGlassCard: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                // 原生材质：macOS 26 上 .ultraThinMaterial 即 Liquid Glass，旧系统自动降级为普通半透明材质
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .light
                            ? LinearGradient(colors: [Color.black.opacity(0.12), Color.black.opacity(0.12)],
                                             startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)],
                                             startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8
                    )
            )
    }
}

// MARK: - 液态玻璃面板（Liquid Glass Panel）
// 面板级背景：相较上面的卡片，这里不压任何暗色底，而是用"竖向渐变 + 顶部高光 + 光泽"，
// 让 NSVisualEffectView 的毛玻璃清晰透上来，达成液态玻璃的通透质感。

/// 液态玻璃底色层：极淡的 tint，叠在 NSVisualEffectView 真模糊之上。
/// 模糊后的桌面环境色会渗入面板底部，达成 ClashMac 菜单的「活玻璃」质感。
private struct LGGlassBase: View {
    var body: some View {
        DT.Color.panelTint
    }
}

/// 液态玻璃面板修饰器：供 Popover / 设置窗口根视图套用
struct LiquidGlassPanelBuddy: ViewModifier {
    var cornerRadius: CGFloat
    var borderEmphasis: Double = 1.0
    func body(content: Content) -> some View {
        Group {
            // 玻璃材质由 AppKit NSVisualEffectView(.popover/.menu) 提供——
            // macOS 26 下已适配 Liquid Glass，SwiftUI 层只叠半透明 tint，不再画玻璃
            content
                .background(LGGlassBase())
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            // 玻璃边缘折射：顶部高光 → 底部隐没
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [DT.Color.glassBorderTop, DT.Color.glassBorderBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }
}

extension View {
    /// 给任意视图套上液态玻璃面板底
    func liquidGlassPanel(cornerRadius: CGFloat = DT.Radius.card) -> some View {
        modifier(LiquidGlassPanelBuddy(cornerRadius: cornerRadius))
    }
}

// MARK: - 通用 UI 组件

/// 卡片容器：液态玻璃卡片（半透白渐变 + 顶部内高光 + 细白描边）
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
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
    }
}

/// 实心填充胶囊（ClashMac Active 态：高亮蓝底白字）
struct DPill: View {
    let text: String
    let color: SwiftUI.Color

    var body: some View {
        Text(text)
            .font(DT.Font.label)
            .foregroundStyle(Color.white)
            .padding(.horizontal, DT.Space.m)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }
}

/// Bento 统计卡（ClashMac 仪表盘：图标 + 小标签 + 大号数字 + 可选副文本）
struct DStatCard: View {
    let icon: String
    let iconColor: SwiftUI.Color
    let label: String
    let value: String
    var subtitle: String? = nil
    var valueColor: SwiftUI.Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.xs) {
            HStack(spacing: DT.Space.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(DT.Font.statLabel)
                    .foregroundStyle(DT.Color.textLabel)
                    .tracking(1)
            }
            Text(value)
                .font(DT.Font.statNumber)
                .foregroundStyle(valueColor ?? DT.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // 数据刷新时数字滚动过渡
                .contentTransition(.numericText())
                .animation(Motion.value, value: value)
            if let subtitle {
                Text(subtitle)
                    .font(DT.Font.micro)
                    .foregroundStyle(DT.Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DT.Space.l)
        .modifier(LiquidGlassCard(cornerRadius: DT.Radius.row))
    }
}
