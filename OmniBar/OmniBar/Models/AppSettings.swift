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
    @AppStorage("showCostInsteadOfTokens") var showCostInsteadOfTokens: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage("omniroutePort") var omniroutePort: Int = 20128 {
        didSet { objectWillChange.send() }
    }

    @AppStorage("omnirouteAPIKey") var omnirouteAPIKey: String = "sk-c4b1296a521c8ac2-243703-59cc5103" {
        didSet { objectWillChange.send() }
    }

    @AppStorage("pollIntervalSeconds") var pollIntervalSeconds: Int = 15
    @AppStorage("omnirouteBinaryPath") var omnirouteBinaryPath: String = AppSettings.detectOmnirouteBinary()

    // MARK: - 全生命周期托管

    /// 启动 OmniBar 时自动拉起 omniroute（若未运行）
    @AppStorage("autoStartOnLaunch") var autoStartOnLaunch: Bool = true {
        didSet { objectWillChange.send() }
    }
    /// omniroute 意外崩溃后自动重启
    @AppStorage("autoRestartOnCrash") var autoRestartOnCrash: Bool = true {
        didSet { objectWillChange.send() }
    }
    /// 退出 OmniBar 时自动停止 omniroute
    @AppStorage("stopOnQuit") var stopOnQuit: Bool = true {
        didSet { objectWillChange.send() }
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

    private init() {}
}
