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

        var title = ""
        if settings.showTokenInMenuBar {
            title = settings.showCostInsteadOfTokens
                ? omnirouteService.usage.todayCostText
                : omnirouteService.usage.todayTokensText + " tok"
        }

        button.image = Self.statusBarIcon(for: omnirouteService.status)
        button.title = title
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeft
        button.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
        button.toolTip = "OmniBar — \(omnirouteService.status.label)"
    }

    /// 绘制菜单栏图标：路由符号 + 右下角状态圆点
    /// 非 template 图像（需要保留状态色），因此自行适配深浅色模式
    private static func statusBarIcon(for status: ServiceStatus) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            // 使用通用的路由符号，确保在 macOS 14+ 上可用
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let symbolName = "point.3.connected.trianglepath"
            guard let symbol = NSImage(systemSymbolName: symbolName,
                                       accessibilityDescription: "OmniBar")?
                .withSymbolConfiguration(config) else { 
                print("⚠️ SF Symbol '\(symbolName)' 不可用，使用备用方案")
                return Self.drawFallbackIcon(in: NSRect(x: 0, y: 0, width: 18, height: 18), status: status)
            }

            // 跟随系统深浅色，保证在两种模式下都清晰
            let tint = NSColor.labelColor
            let rect = NSRect(x: 0, y: 1, width: 16, height: 16)
            symbol.isTemplate = true
            tint.set()
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.9)
            rect.fill(using: .sourceAtop)

            // 右下角状态点
            let dotColor: NSColor
            switch status {
            case .running: dotColor = .systemGreen
            case .stopped: dotColor = .systemGray
            case .error:   dotColor = .systemRed
            case .unknown: dotColor = .systemYellow
            }
            let dotRect = NSRect(x: 11.5, y: 0.5, width: 6, height: 6)
            // 描一圈背景色边，让圆点在符号上仍可辨识
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -1, dy: -1)).fill()
            dotColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        
        // 备用方案：如果 SF Symbol 不可用，绘制简单的路由图标
        let fallbackImage = NSImage(size: size, flipped: false) { _ in
            return Self.drawFallbackIcon(in: NSRect(x: 0, y: 0, width: 18, height: 18), status: status)
        }
        fallbackImage.isTemplate = false
        return fallbackImage
    }
    
    /// 备用图标绘制方案（当 SF Symbol 不可用时使用）
    private static func drawFallbackIcon(in rect: NSRect, status: ServiceStatus) -> Bool {
        // 绘制简单的三角形路由符号
        let dotColor: NSColor
        switch status {
        case .running: dotColor = .systemGreen
        case .stopped: dotColor = .systemGray
        case .error:   dotColor = .systemRed
        case .unknown: dotColor = .systemYellow
        }
        
        // 中心三角形
        let trianglePath = NSBezierPath()
        let center = NSPoint(x: rect.midX, y: rect.midY + 2)
        let size: CGFloat = 8
        trianglePath.move(to: NSPoint(x: center.x, y: center.y + size))
        trianglePath.line(to: NSPoint(x: center.x - size, y: center.y - size/2))
        trianglePath.line(to: NSPoint(x: center.x + size, y: center.y - size/2))
        trianglePath.close()
        dotColor.setFill()
        trianglePath.fill()
        
        // 右下角状态点
        let dotRect = NSRect(x: rect.maxX - 6, y: rect.minY + 1, width: 5, height: 5)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(ovalIn: dotRect.insetBy(dx: -1, dy: -1)).fill()
        dotColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        
        return true
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

        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = 520

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
        // 关闭系统面板阴影，避免透明玻璃外围出现一圈黑影（控制中心无硬阴影）
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        // 面板固定浅色外观：白色透明玻璃风格（配合 .preferredColorScheme(.light)）
        panel.appearance = NSAppearance(named: .aqua)

        let content = PopoverPanel(service: omnirouteService, settings: settings)
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // 背景由下方 NSVisualEffectView 提供；PopoverPanel 根视图不绘制背景（见其 body），
        // 因此 NSHostingView 内容透明，毛玻璃能透上来。

        // 外层普通容器 + 裁剪，防止 SwiftUI intrinsic 溢出改变实际布局宽度
        let container = ClippingContainerView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))

        // macOS 原生控制中心同款毛玻璃：NSVisualEffectView(.popover) + behindWindow 混合，
        // 模糊背后内容并透视，交给 SwiftUI 的是完全透明的 SwiftUI 层。
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(effectView)
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.widthAnchor.constraint(equalToConstant: panelWidth),
            effectView.heightAnchor.constraint(equalToConstant: panelHeight),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.widthAnchor.constraint(equalToConstant: panelWidth),
            hosting.heightAnchor.constraint(equalToConstant: panelHeight)
        ])

        panel.contentView = container
        panel.contentMinSize = NSSize(width: panelWidth, height: panelHeight)
        panel.contentMaxSize = NSSize(width: panelWidth, height: panelHeight)
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        panel.setFrame(panelRect, display: false)

        panel.orderFrontRegardless()
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
        let settingsView = SettingsView(settings: settings)
        let hosting = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "OmniBar 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        // 设置窗口固定深色外观：保持深色玻璃风格
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

/// 固定尺寸的裁剪容器：屏蔽子视图（SwiftUI hosting view）的 intrinsic size 影响
/// 并在 layer 层裁切圆角——毛玻璃（NSVisualEffectView）不受 SwiftUI clipShape 约束，
/// 必须在此用 layer.cornerRadius 裁出面板圆角。
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
        // 与 PopoverPanel 的 DT.Radius.card(12) 一致，裁切毛玻璃圆角
        layer?.cornerRadius = 12
    }
}
