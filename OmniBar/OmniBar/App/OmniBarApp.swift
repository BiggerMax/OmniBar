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
            SettingsView(
                settings: settings,
                service: (NSApplication.shared.delegate as? AppDelegate)?.omnirouteService
            )
        }
    }
}
