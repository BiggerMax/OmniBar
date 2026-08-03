//
//  AppDelegate.swift
//  OmniBar
//
//  在 AppKit 层管理 NSStatusItem 生命周期
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    private(set) var omnirouteService: OmnirouteService!
    private var statusItemManager: StatusItemManager?
    /// 兜底观察器：Cmd+, 打开的 SwiftUI Settings 窗口出现时强制浅色标题栏
    private var settingsWindowAppearanceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 测试宿主（XCTest hosted test）环境下跳过业务逻辑，
        // 避免 OmnirouteService 轮询 / 网络请求干扰单元测试执行。
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        // 启动时隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        // 强制全局深色外观：Cmd+, 的 SwiftUI Settings 窗口标题栏在系统浅色模式下
        // 默认跟随系统变浅，与 Popover 的 ClashMac 深色玻璃风格不一致。统一为 .darkAqua 后，
        // 所有窗口（含设置窗口标题栏）在深浅色系统主题下都保持深色玻璃。
        // （Popover 面板与 openSettings 窗口已各自显式 .darkAqua，不受影响。）
        NSApp.appearance = NSAppearance(named: .darkAqua)
        observeSettingsWindowAppearance()

        // 若用户此前未配置 API Key（或仍是无效占位值），则填充本地网关默认 Key。
        // 占位/测试值会导致网关返回 403（token 无效），应替换为可用的默认 Key。
        let key = settings.omnirouteAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty || key == "test-api-key" {
            settings.omnirouteAPIKey = "sk-c4b1296a521c8ac2-243703-59cc5103"
        }

        let service = OmnirouteService(settings: settings)
        self.omnirouteService = service

        let manager = StatusItemManager(service: service, settings: settings)
        self.statusItemManager = manager

        omnirouteService.startPolling()
        Task { await omnirouteService.refreshStatus() }
        // 全生命周期托管：启动时自动拉起 omniroute（若开启且未运行）
        Task { await omnirouteService.startIfNeeded() }
    }

    /// 优雅退出：若开启 stopOnQuit，先停止 omniroute 再真正退出，避免后台残留
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let service = omnirouteService, settings.stopOnQuit else {
            omnirouteService?.stopPolling()
            return .terminateNow
        }
        Task { @MainActor in
            await service.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        omnirouteService?.stopPolling()
    }

    /// 兜底：Cmd+, 打开的 SwiftUI Settings 窗口在创建/激活时，再次强制深色标题栏，
    /// 确保即使在系统浅色模式下也始终与 Popover 风格一致。
    private func observeSettingsWindowAppearance() {
        settingsWindowAppearanceObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow,
                  window.styleMask.contains(.titled) else { return }
            // 仅处理尚未显式深色的标题窗口（Popover 是无边框面板，天然被过滤）
            if window.appearance?.name != .darkAqua {
                window.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
}
