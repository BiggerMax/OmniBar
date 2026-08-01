//
//  GeneralSettings.swift
//  OmniBar
//
//  通用设置：启动 / 显示 / 网络分组
//

import SwiftUI

struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.xxxl) {
                section(title: "启动") {
                    DRow {
                        toggleRow(title: "开机自启动 Omniroute + OmniBar", isOn: $settings.launchAtLogin)
                    }
                }
                section(title: "显示") {
                    DCard(padding: 0) {
                        VStack(spacing: 0) {
                            toggleRow(title: "在菜单栏显示 Token / 费用", isOn: $settings.showTokenInMenuBar)
                            Divider().background(DT.Color.strokeVariant).padding(.horizontal, DT.Space.l)
                            toggleRow(title: "显示费用（否则显示 Token）", isOn: $settings.showCostInsteadOfTokens)
                        }
                    }
                }
                section(title: "网络") {
                    DRow {
                        HStack {
                            Text("轮询间隔")
                                .font(DT.Font.bodyMedium)
                                .foregroundStyle(DT.Color.textPrimary)
                            Spacer()
                            Picker("", selection: $settings.pollIntervalSeconds) {
                                Text("10s").tag(10)
                                Text("15s").tag(15)
                                Text("30s").tag(30)
                                Text("60s").tag(60)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .tint(DT.Color.accent)
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.l) {
            Text(title.uppercased())
                .font(DT.Font.sectionLabel)
                .foregroundStyle(DT.Color.accent)
                .tracking(1.5)
            content()
        }
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(DT.Font.bodyMedium)
                .foregroundStyle(DT.Color.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(DT.Color.accent)
                .labelsHidden()
        }
        .padding(.horizontal, DT.Space.l)
        .padding(.vertical, DT.Space.l)
    }
}
