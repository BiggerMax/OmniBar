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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 测试宿主（XCTest hosted test）环境下跳过业务逻辑，
        // 避免 OmnirouteService 轮询 / 网络请求干扰单元测试执行。
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        // 启动时隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        // 背景跟随系统深浅色：不强制全局外观（不再设置 NSApp.appearance），
        // DT.Color 设计 token 均为动态色，Popover / 设置窗口会随系统主题自动切换。

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
}
