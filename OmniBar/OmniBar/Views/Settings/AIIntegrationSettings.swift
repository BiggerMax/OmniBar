//
//  AIIntegrationSettings.swift
//  OmniBar
//
//  v2.0「AI 接入」设置：把 omniroute 网关一键接入 Claude Code / Codex。
//

//  实际卡片与开关逻辑复用 Views/Components/AIIntegrationSection.swift。
//

import SwiftUI

struct AIIntegrationSettings: View {
    @ObservedObject var settings: AppSettings
    var service: OmnirouteService?
    @ObservedObject var manager: ProviderLinkManager

    var body: some View {
        ScrollView {
            AIIntegrationSection(settings: settings, service: service, manager: manager)
        }
        .scrollIndicators(.hidden)
        .introspectScrollView { nssv in
            NSScrollView.omnibarHideScrollbars(nssv)
        }
    }
}
