//
//  AppDelegate.swift
//  OmniBar
//
//  在 AppKit 层管理 NSStatusItem 生命周期
//

import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 共享实例：供 SwiftUI Settings scene / StatusItemManager 访问 linkManager 等（避免依赖 NSApp.delegate 类型转换）。
    static weak var shared: AppDelegate?

    let settings = AppSettings.shared
    private(set) var omnirouteService: OmnirouteService!
    private(set) var linkManager: ProviderLinkManager!
    private(set) var claudeRouteProxy: ClaudeRouteProxy!
    private var statusItemManager: StatusItemManager?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 测试宿主（XCTest hosted test）环境下跳过业务逻辑，
        // 避免 OmnirouteService 轮询 / 网络请求干扰单元测试执行。
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        Self.shared = self

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

        // v2.0「AI 接入」：管理 Claude Code / Codex 本地配置接管。
        // 注入 modelsProvider：联动刷新（端口/Key/模型变化）时用最新网关模型列表重写配置。
        self.linkManager = ProviderLinkManager(settings: settings) { [weak self] in
            self?.omnirouteService?.gatewayModels ?? []
        }
        // 网关模型列表加载完成后（首次轮询成功），用真实模型对已开启开关幂等重写
        service.$gatewayModels
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.linkManager?.refreshIfLinked()
                }
            }
            .store(in: &cancellables)
        // 启动时对已开启的开关幂等 apply（例如上次会话遗留的开关状态）
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.settings.linkClaudeCode || self.settings.linkCodex {
                await self.linkManager.refreshIfLinked()
            }
        }

        // v2.1：Claude Desktop 本地路由代理（模型映射）。随 App 启动常驻，
        // 3P profile 的 inferenceGatewayBaseUrl 指向它；未开启接入时无流量。
        let proxy = ClaudeRouteProxy(settings: settings, port: UInt16(settings.claudeDesktopProxyPort))
        self.claudeRouteProxy = proxy
        do {
            try proxy.start()
        } catch {
            // 端口被占用等失败不阻断主流程（桌面端接入时才需要代理在跑）
        }

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
        claudeRouteProxy?.stop()
    }
}
