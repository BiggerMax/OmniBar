//
//  LaunchAtLogin.swift
//  OmniBar
//
//  通过 Service Management 框架实现开机自启
//

import Foundation
import ServiceManagement

final class LaunchAtLogin {
    static let shared = LaunchAtLogin()

    private init() {}

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 回退到传统的登录项方式
            fallbackSetLoginItem(enabled: enabled)
        }
    }

    // MARK: - Fallback via AppleScript / LaunchAgent

    private func fallbackSetLoginItem(enabled: Bool) {
        let bundlePath = Bundle.main.bundlePath
        let script: String
        let appName = "OmniBar"
        if enabled {
            script = """
            tell application "System Events" to make login item at end with properties {path:"\(bundlePath)", hidden:false}
            """
        } else {
            script = """
            tell application "System Events" to delete login item "\(appName)"
            """
        }
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            _ = error
        }
    }
}
