//
//  StatusItemManager.swift
//  OmniBar
//
//  管理菜单栏图标、Token 文本、右键菜单与 Popover 面板
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusItemManager: NSObject {
    private let statusItem: NSStatusItem
    private let omnirouteService: OmnirouteService
    private let settings: AppSettings

    private var popoverPanel: NSPanel?
    private var globalClickMonitor: Any?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - 面板材质（原生右键菜单 style：.menu 材质 + 系统默认模糊）
    /// 背景模糊半径：数值越小越通透、透视越强（仅 .popover 设置窗口生效；.menu 用系统原生模糊）
    private let glassBlurRadius: CGFloat = 5
    /// 材质叠加透明度：1.0 = 完整显示材质；< 1 时更透，底层桌面更清晰地透上来
    private let glassBlurAlpha: CGFloat = 1

    init(service: OmnirouteService, settings: AppSettings) {
        self.omnirouteService = service
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        observeService()
        observeSettings()
        observeSettingsNotification()
        rebuildMenu()
    }

    // MARK: - Status Item UI

    private func configureStatusItem() {
        statusItem.behavior = []
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            // 左键 → Popover；右键 → NSMenu
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        renderTitle()
        // 不要在这里设置 statusItem.menu，否则会拦截所有点击
    }

    private func renderTitle() {
        guard let button = statusItem.button else { return }

        if settings.showTokenInMenuBar {
            // 双层显示：上行 Token 量，下行金额
            let tokens = settings.compressTokenInMenuBar
                ? omnirouteService.usage.todayTokensText
                : "\(omnirouteService.usage.todayTokens)"
            button.image = Self.menuBarTwoLineImage(top: tokens, bottom: omnirouteService.usage.todayCostText)
        } else {
            // 关闭用量显示：退回只显示状态圆点，避免菜单栏出现空白占位
            button.image = Self.statusBarIcon(for: omnirouteService.status)
        }
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = "OmniBar — \(omnirouteService.status.label)"
    }

    /// 各状态图标只渲染一次并缓存（renderTitle 每秒调用，避免反复分配位图）。
    private static var iconCache: [ServiceStatus: NSImage] = [:]

    /// 绘制菜单栏图标：「关于」页品牌图标的迷你版——圆角方块底色随服务状态变化
    /// （运行绿 / 停止灰 / 错误红 / 未知黄），内部叠白色仪表符号，既统一品牌形象又保留状态语义。
    /// 用 lockFocus 写入位图缓存，保证菜单栏按钮必定能绘制出来，不会出现图标空白占位。
    /// 画布保持标准 18×18 菜单栏图标尺寸（与其他图标垂直对齐），与系统图标的视觉密度一致。
    private static func statusBarIcon(for status: ServiceStatus) -> NSImage {
        if let cached = iconCache[status] { return cached }
        let color = statusColor(for: status)
        let canvas: CGFloat = 18
        let size = NSSize(width: canvas, height: canvas)
        let image = NSImage(size: size)
        image.isTemplate = false
        image.lockFocus()

        // 圆角方块底（状态色）
        let squareSize: CGFloat = 16
        let inset = (canvas - squareSize) / 2
        let squareRect = NSRect(x: inset, y: inset, width: squareSize, height: squareSize)
        let squarePath = NSBezierPath(roundedRect: squareRect, xRadius: 4.5, yRadius: 4.5)
        color.setFill()
        squarePath.fill()

        // 白色仪表符号
        if let symbol = Self.whiteSymbol("gauge.with.dots.needle.67percent", pointSize: 11) {
            let symbolSize = symbol.size
            symbol.draw(in: NSRect(
                x: (canvas - symbolSize.width) / 2,
                y: (canvas - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            ))
        }
        image.unlockFocus()
        iconCache[status] = image
        return image
    }

    /// 渲染指定 SF Symbol 为白色位图（符号先按模板绘制，再用 sourceAtop 填充白色）
    private static func whiteSymbol(_ name: String, pointSize: CGFloat) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
              let symbol = base.withSymbolConfiguration(
                  NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
              )
        else { return nil }
        let symbolSize = symbol.size
        let tinted = NSImage(size: symbolSize)
        tinted.isTemplate = false
        tinted.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: symbolSize))
        NSColor.white.set()
        NSRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }

    /// 双层菜单栏文本缓存：renderTitle 每秒调用，但用量仅在轮询刷新时变化，
    /// 按 (top, bottom) 复用位图，避免每秒重绘。
    private static var twoLineImageCache: [String: NSImage] = [:]

    /// 双层菜单栏文本：上行 Token 量、下行金额。
    /// 绘制为 template 位图（文字用黑色，AppKit 只取 alpha 并按菜单栏配色渲染），
    /// 深浅色模式都正确，点击高亮时自动反白。
    private static func menuBarTwoLineImage(top: String, bottom: String) -> NSImage {
        let key = "\(top)|\(bottom)"
        if let cached = twoLineImageCache[key] { return cached }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let topAttr = NSAttributedString(string: top, attributes: attrs)
        let bottomAttr = NSAttributedString(string: bottom, attributes: attrs)
        let topSize = topAttr.size()
        let bottomSize = bottomAttr.size()

        // 总高控制在 20pt：菜单栏按钮内容区约 20pt，过高会被 imageScaling 缩放变糊
        let height: CGFloat = 20
        let lineStep = height / 2
        let width = ceil(max(topSize.width, bottomSize.width)) + 4

        let image = NSImage(size: NSSize(width: width, height: height))
        image.isTemplate = true
        image.lockFocus()
        // 注意：lockFocus 上下文是非翻转的（原点左下）。绝不能手动 scaleBy(y:-1) 翻转，
        // 否则文本系统会双重补偿，导致文字镜像/倒置。
        // draw(in:) 会自动处理方向，按上/下两个半区分别绘制即可。
        topAttr.draw(in: NSRect(x: (width - topSize.width) / 2, y: lineStep,
                                width: topSize.width, height: lineStep))
        bottomAttr.draw(in: NSRect(x: (width - bottomSize.width) / 2, y: 0,
                                   width: bottomSize.width, height: lineStep))
        image.unlockFocus()

        // 防止缓存无限增长：超过 100 张时整体清空（重建成本极低）
        if twoLineImageCache.count >= 100 {
            twoLineImageCache.removeAll(keepingCapacity: true)
        }
        twoLineImageCache[key] = image
        return image
    }

    private static func statusColor(for status: ServiceStatus) -> NSColor {
        switch status {
        case .running: return .systemGreen
        case .stopped: return .systemGray
        case .error:   return .systemRed
        case .unknown: return .systemYellow
        }
    }

    private func observeService() {
        // 每秒更新菜单栏 token 文本
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renderTitle() }
        }
        omnirouteService.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.renderTitle()
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
        omnirouteService.$usage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.renderTitle() }
            .store(in: &cancellables)
    }

    private func observeSettings() {
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.renderTitle()
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func observeSettingsNotification() {
        NotificationCenter.default.publisher(for: .openOmniBarSettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.openSettings() }
            .store(in: &cancellables)
    }

    // MARK: - Menu (Right-click)

    private func rebuildMenu() {
        // 仅构造菜单对象供右键弹出用，不挂到 statusItem.menu
        // statusItem.menu 一旦赋值会拦截所有点击（包括左键），必须为空
        let menu = NSMenu()
        let running = omnirouteService.status == .running
        let busy = omnirouteService.isOperationInProgress

        let startItem = menuItem(title: "启动 Omniroute", action: #selector(startService), keyEquivalent: "")
        startItem.isEnabled = !running && !busy
        menu.addItem(startItem)

        let stopItem = menuItem(title: "停止 Omniroute", action: #selector(stopService), keyEquivalent: "")
        stopItem.isEnabled = running && !busy
        menu.addItem(stopItem)

        let restartItem = menuItem(title: "重启 Omniroute", action: #selector(restartService), keyEquivalent: "r")
        restartItem.isEnabled = !busy
        menu.addItem(restartItem)

        // 手动控制 enabled 状态，否则 AppKit 会自动全部置灰/点亮
        menu.autoenablesItems = false
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "打开 Dashboard", action: #selector(openDashboard), keyEquivalent: "d"))
        menu.addItem(menuItem(title: "偏好设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "退出 OmniBar", action: #selector(quitApp), keyEquivalent: "q"))
        self.contextMenu = menu
    }

    private var contextMenu: NSMenu?

    private func menuItem(title: String, action: Selector?, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        // menu.autoenablesItems = false 时需显式启用
        item.isEnabled = true
        return item
    }

    // MARK: - Actions

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }
        switch event.type {
        case .rightMouseUp:
            showContextMenu()
        default:
            togglePopover(sender)
        }
    }

    private func showContextMenu() {
        // 弹出前重建，确保启用状态反映当前 status / isOperationInProgress
        rebuildMenu()
        guard let menu = contextMenu, let button = statusItem.button else { return }
        closePopoverPanel()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if let panel = popoverPanel, panel.isVisible {
            closePopoverPanel()
            return
        }
        showPopoverPanel()
    }

    private func closePopoverPanel() {
        popoverPanel?.orderOut(nil)
        popoverPanel = nil
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    /// 使用 NSPanel 实现 popover，完全自控 frame，绝对不受 SwiftUI intrinsic 影响。
    private func showPopoverPanel() {
        closePopoverPanel()

        guard let button = statusItem.button else { return }

        let panelWidth = DT.Layout.panelWidth
        let panelHeight = DT.Layout.panelHeight

        // 用屏幕坐标系直接计算 panel 位置：贴近状态栏按钮（屏幕右上角）下方。
        // 注意：不要依赖 button.window.convertToScreen（status bar 按钮的 window
        // 在某些 macOS 版本下坐标会异常，导致 panel 偏移）。
        let buttonFrameInScreen: NSRect
        if let buttonWindow = button.window {
            buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        } else {
            // fallback：使用鼠标当前位置作为锚点
            let mouseLoc = NSEvent.mouseLocation
            buttonFrameInScreen = NSRect(x: mouseLoc.x - 10, y: mouseLoc.y, width: 20, height: 20)
        }

        // 主屏幕可视区域
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame

        // panel 水平方向居中于按钮，但不超过屏幕右边缘
        var x = buttonFrameInScreen.midX - panelWidth / 2
        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - panelWidth - 8)

        // panel 放在按钮下方；若下方放不下则放上方
        var y = buttonFrameInScreen.minY - panelHeight - 4
        if y < visibleFrame.minY + 8 {
            y = buttonFrameInScreen.maxY + 4
        }

        let panelRect = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)

        let panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        // 与原生右键菜单一致的柔和投影（圆角玻璃，阴影由 invalidateShadow 贴合圆角形状）
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        // 跟随系统深浅色：不固定面板外观，DT.Color 动态色自动切换

        let content = PopoverPanel(service: omnirouteService,
                                   settings: settings,
                                   linkManager: AppDelegate.shared?.linkManager)
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // 原生 Liquid Glass 由 SwiftUI 根视图直接渲染（.glassEffect），窗口保持透明即可透出桌面

        // 外层普通容器 + 裁剪，防止 SwiftUI intrinsic 溢出改变实际布局宽度
        let container = ClippingContainerView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        container.addSubview(hosting)

        panel.contentView = container
        panel.contentMinSize = NSSize(width: panelWidth, height: panelHeight)
        panel.contentMaxSize = NSSize(width: panelWidth, height: panelHeight)
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        panel.setFrame(panelRect, display: false)

        panel.orderFrontRegardless()
        // 阴影形状由内容的透明区域决定：等下一轮 runloop（layout 已应用圆角裁切）
        // 再重新计算，让柔和投影贴合圆角玻璃而非矩形窗框
        DispatchQueue.main.async { [weak panel] in
            panel?.invalidateShadow()
        }
        self.popoverPanel = panel

        // 点击 panel 外自动关闭
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let self = self, let panel = panel else { return }
            guard panel.isVisible else { return }
            // 点击位置不在 panel 内 → 关闭
            let screenPoint = NSEvent.mouseLocation
            if !panel.frame.contains(screenPoint) {
                Task { @MainActor in self.closePopoverPanel() }
            }
        }
    }

    @objc private func startService() {
        Task { _ = await omnirouteService.start() }
    }

    @objc private func stopService() {
        Task { _ = await omnirouteService.stop() }
    }

    @objc private func restartService() {
        Task { _ = await omnirouteService.restart() }
    }

    @objc private func openDashboard() {
        if let url = URL(string: settings.dashboardURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSettings() {
        // 先关闭 popover，避免设置窗口与 popover 重叠
        closePopoverPanel()
        let settingsView = SettingsView(settings: settings,
                                        service: self.omnirouteService,
                                        linkManager: AppDelegate.shared?.linkManager)
        let hosting = NSHostingView(rootView: settingsView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.frame = NSRect(x: 0, y: 0, width: DT.Layout.settingsWidth, height: DT.Layout.settingsHeight)

        // 与 Popover 相同的轻度毛玻璃 + 上方透明 SwiftUI 层
        let container = NSView(frame: NSRect(x: 0, y: 0, width: DT.Layout.settingsWidth, height: DT.Layout.settingsHeight))
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.layer?.cornerRadius = DT.Radius.card
        // 设置窗口带系统标题栏：只圆底部两角，避免顶部与标题栏之间出现圆角空隙
        container.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]

        if let effectView = makeGlassEffect(frame: container.bounds) {
            container.addSubview(effectView)
        }
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.widthAnchor.constraint(equalToConstant: DT.Layout.settingsWidth),
            hosting.heightAnchor.constraint(equalToConstant: DT.Layout.settingsHeight)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: DT.Layout.settingsWidth, height: DT.Layout.settingsHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.title = "OmniBar 设置"
        // 窗口透明（无背景模糊）：背景由 SwiftUI 透明玻璃渐变直接提供，透出桌面内容
        window.isOpaque = false
        window.backgroundColor = .clear
        // 跟随系统深浅色：不固定窗口外观（不设置 window.appearance）
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// 构建毛玻璃背景视图：默认 .popover 材质（设置窗口，可调自定义模糊），
    /// 传入 .menu 材质时（Popover）交给系统渲染原生 Liquid Glass——与右键菜单完全一致：
    /// 系统默认模糊 + 自带边缘/活力，不覆盖任何私有参数。
    /// glassBlurAlpha<=0 时返回 nil（不添加模糊层）。
    private func makeGlassEffect(frame: NSRect, material: NSVisualEffectView.Material = .popover) -> NSVisualEffectView? {
        guard glassBlurAlpha > 0 else { return nil }
        let effectView = NSVisualEffectView(frame: frame)
        effectView.material = material
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        // 自定义 blurRadius 仅用于 .popover（设置窗口）；.menu 保持系统默认模糊，避免破坏原生玻璃观感
        if material == .popover,
           glassBlurRadius > 0,
           effectView.responds(to: NSSelectorFromString("setBlurRadius:")) {
            effectView.setValue(glassBlurRadius, forKey: "blurRadius")
        }
        if glassBlurAlpha < 1 {
            effectView.alphaValue = glassBlurAlpha
        }
        effectView.translatesAutoresizingMaskIntoConstraints = false
        return effectView
    }
}

/// 固定尺寸的裁剪容器：屏蔽子视图（SwiftUI hosting view）的 intrinsic size 影响
/// 并在 layer 层裁切圆角——毛玻璃（NSVisualEffectView）不受 SwiftUI clipShape 约束，
/// 必须在此用 layer.cornerRadius 裁出原生菜单圆角。
final class ClippingContainerView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    override var intrinsicContentSize: NSSize { .zero }

    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.masksToBounds = true
        // 与 PopoverPanel 的 DT.Layout.panelRadius 一致，裁切毛玻璃圆角
        layer?.cornerRadius = DT.Layout.panelRadius
    }
}
