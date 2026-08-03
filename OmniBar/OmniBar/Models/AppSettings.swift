//
//  AppSettings.swift
//  OmniBar
//
//  应用偏好设置，使用 @AppStorage 持久化
//

import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet { LaunchAtLogin.shared.setEnabled(launchAtLogin) }
    }

    @AppStorage("showTokenInMenuBar") var showTokenInMenuBar: Bool = true
    // 菜单栏双层显示：上行 Token 量、下行金额。
    // 注意：didSet 里的 objectWillChange.send() 必须异步分发（DispatchQueue.main.async），
    // 若同步发送，SwiftUI 视图更新期间（如设置页 Toggle）会触发
    // “Publishing changes from within view updates is not allowed”断言崩溃。
    // 菜单栏 Token 是否压缩显示（12.3K），否则显示完整数字（12345）
    @AppStorage("compressTokenInMenuBar") var compressTokenInMenuBar: Bool = true {
        didSet { notifyChange() }
    }

    @AppStorage("omniroutePort") var omniroutePort: Int = 20128 {
        didSet { notifyChange() }
    }

    @AppStorage("omnirouteAPIKey") var omnirouteAPIKey: String = "sk-c4b1296a521c8ac2-243703-59cc5103" {
        didSet { notifyChange() }
    }

    @AppStorage("pollIntervalSeconds") var pollIntervalSeconds: Int = 15
    @AppStorage("omnirouteBinaryPath") var omnirouteBinaryPath: String = AppSettings.detectOmnirouteBinary()

    // MARK: - Cloudflare Tunnel（代理 localhost:port/v1 到公网）

    /// cloudflared 可执行文件路径
    @AppStorage("cloudflaredBinaryPath") var cloudflaredBinaryPath: String = "/opt/homebrew/bin/cloudflared"
    /// cloudflared 命名隧道配置文件
    @AppStorage("cloudflaredConfigPath") var cloudflaredConfigPath: String = AppSettings.defaultCloudflaredConfig()
    /// cloudflared 隧道名（run <name>）
    @AppStorage("cloudflaredTunnelName") var cloudflaredTunnelName: String = "openclaw-web"
    /// 隧道公网地址（仅展示）
    @AppStorage("tunnelPublicURL") var tunnelPublicURL: String = "https://api.biggermax.xyz"

    static func defaultCloudflaredConfig() -> String {
        NSHomeDirectory() + "/.cloudflared/config.yml"
    }

    // MARK: - 全生命周期托管

    /// 启动 OmniBar 时自动拉起 omniroute（若未运行）
    @AppStorage("autoStartOnLaunch") var autoStartOnLaunch: Bool = true {
        didSet { notifyChange() }
    }
    /// omniroute 意外崩溃后自动重启
    @AppStorage("autoRestartOnCrash") var autoRestartOnCrash: Bool = true {
        didSet { notifyChange() }
    }
    /// 退出 OmniBar 时自动停止 omniroute
    @AppStorage("stopOnQuit") var stopOnQuit: Bool = true {
        didSet { notifyChange() }
    }
    /// 崩溃自动重启的最大连续尝试次数（防止无限重启循环）
    @AppStorage("restartRetryLimit") var restartRetryLimit: Int = 3

    /// 自动探测 omniroute 可执行文件位置（Homebrew ARM / Intel / 用户目录）
    static func detectOmnirouteBinary() -> String {
        let candidates = [
            "/opt/homebrew/bin/omniroute",
            "/usr/local/bin/omniroute",
            NSHomeDirectory() + "/.npm-global/bin/omniroute",
            NSHomeDirectory() + "/.local/bin/omniroute"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/opt/homebrew/bin/omniroute"
    }
    @AppStorage("dashboardURL") var dashboardURL: String = "http://localhost:20128/dashboard"

    var baseURL: URL {
        URL(string: "http://localhost:\(omniroutePort)")!
    }

    /// 通知非 SwiftUI 观察者（菜单栏、OmnirouteService 等）设置已变更。
    /// 必须异步发送：同步发送会在 SwiftUI 视图更新期间触发
    /// “Publishing changes from within view updates”断言导致崩溃。
    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    private init() {}
}
