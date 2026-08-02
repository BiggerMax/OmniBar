//
//  GeneralSettings.swift
//  OmniBar
//
//  通用设置：启动 / 显示 / 网络分组
//

import SwiftUI

struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings
    var service: OmnirouteService?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.xxxl) {
                section(title: "启动") {
                    DRow {
                        toggleRow(title: "开机自启动 Omniroute + OmniBar", isOn: $settings.launchAtLogin)
                    }
                    DRow {
                        toggleRow(title: "启动 OmniBar 时自动拉起 Omniroute", isOn: $settings.autoStartOnLaunch)
                    }
                }
                section(title: "进程托管") {
                    DCard(padding: 0) {
                        VStack(spacing: 0) {
                            toggleRow(title: "Omniroute 意外崩溃后自动重启", isOn: $settings.autoRestartOnCrash)
                            Divider().background(DT.Color.strokeVariant).padding(.horizontal, DT.Space.l)
                            toggleRow(title: "退出 OmniBar 时停止 Omniroute", isOn: $settings.stopOnQuit)
                        }
                    }
                }
                section(title: "显示") {
                    DCard(padding: 0) {
                        VStack(spacing: 0) {
                            toggleRow(title: "在菜单栏显示 Token 与费用（双行）", isOn: $settings.showTokenInMenuBar)
                            Divider().background(DT.Color.strokeVariant).padding(.horizontal, DT.Space.l)
                            toggleRow(title: "Token 数字压缩显示（12.5K）", isOn: $settings.compressTokenInMenuBar)
                        }
                    }
                }
                section(title: "提示词压缩") {
                    if let svc = service {
                        PromptCompressionSection(service: svc)
                    } else {
                        Text("提示词压缩需要 Omniroute 服务运行后可用")
                            .font(DT.Font.micro)
                            .foregroundStyle(DT.Color.textSecondary)
                            .padding(.leading, DT.Space.xs)
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
        .scrollIndicators(.hidden)
        .introspectScrollView { nssv in
            NSScrollView.omnibarHideScrollbars(nssv)
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

    // MARK: - 提示词压缩分区

    /// 独立子视图持有非可选 @ObservedObject，保证开关/模式随网关状态实时更新；
    /// 父视图用 `if let` 守卫传入，避免测试环境下 service 为 nil 时崩溃。
    private struct PromptCompressionSection: View {
        @ObservedObject var service: OmnirouteService

        var body: some View {
            VStack(alignment: .leading, spacing: DT.Space.l) {
                DCard(padding: 0) {
                    VStack(spacing: 0) {
                        toggleRow(title: "启用提示词压缩", isOn: enabledBinding)
                        Divider().background(DT.Color.strokeVariant).padding(.horizontal, DT.Space.l)
                        DRow {
                            HStack {
                                Text("压缩模式")
                                    .font(DT.Font.bodyMedium)
                                    .foregroundStyle(service.compressionEnabled
                                                     ? DT.Color.textPrimary
                                                     : DT.Color.textSecondary.opacity(0.5))
                                Spacer()
                                Picker("", selection: modeBinding) {
                                    Text("关闭").tag("off")
                                    Text("Lite").tag("lite")
                                    Text("标准").tag("standard")
                                    Text("激进").tag("aggressive")
                                    Text("极致").tag("ultra")
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .tint(DT.Color.accent)
                                .disabled(!service.compressionEnabled)
                            }
                        }
                    }
                }
                // 由网关返回的瞬时错误（如网关不支持该端点）短暂提示
                if let msg = service.lastErrorMessage,
                   msg.contains("提示词压缩") {
                    Text(msg)
                        .font(DT.Font.micro)
                        .foregroundStyle(DT.Color.danger)
                        .padding(.leading, DT.Space.xs)
                }
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

        /// 读 service.compressionEnabled；写时异步写回网关（保留当前模式）。
        private var enabledBinding: Binding<Bool> {
            Binding(
                get: { service.compressionEnabled },
                set: { newValue in
                    Task { await service.setCompression(enabled: newValue, mode: service.compressionMode) }
                }
            )
        }

        /// 读 service.compressionMode；写时异步写回网关（保留当前开关状态）。
        private var modeBinding: Binding<String> {
            Binding(
                get: { service.compressionMode },
                set: { newValue in
                    Task { await service.setCompression(enabled: service.compressionEnabled, mode: newValue) }
                }
            )
        }
    }
}
