//
//  OmniBarApp.swift
//  OmniBar
//
//  SwiftUI 应用入口
//

import SwiftUI

@main
struct OmniBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let settings = AppSettings.shared

    var body: some Scene {
        Settings {
            let appDelegate = NSApplication.shared.delegate as? AppDelegate
            SettingsView(
                settings: settings,
                service: appDelegate?.omnirouteService,
                linkManager: appDelegate?.linkManager
            )
        }
    }
}
