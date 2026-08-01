//
//  ConnectionSettings.swift
//  OmniBar
//
//  连接设置：端口 / 二进制路径 / API Key / Dashboard URL + 信息提示
//

import SwiftUI

struct ConnectionSettings: View {
    @ObservedObject var settings: AppSettings
    @State private var showAPIKey: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.xl) {
                VStack(spacing: DT.Space.l) {
                    fieldRow(label: "端口", placeholder: "20128", text: Binding(
                        get: { String(settings.omniroutePort) },
                        set: { newValue in
                            if let port = Int(newValue), (1...65535).contains(port) {
                                settings.omniroutePort = port
                            }
                        }
                    ))
                    fieldRow(label: "二进制路径", placeholder: "/usr/local/bin/omniroute", text: $settings.omnirouteBinaryPath)
                    apiKeyRow
                    fieldRow(label: "Dashboard", placeholder: "http://localhost:20128/dashboard", text: $settings.dashboardURL)
                }

                // 信息提示
                HStack(alignment: .top, spacing: DT.Space.m) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(DT.Color.accent)
                    Text("这些设置直接控制本地网关连接。修改后可能需要重启 OmniBar 以应用更改。")
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineSpacing(2)
                }
                .padding(DT.Space.l)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.row)
                        .fill(DT.Color.accent.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.row)
                        .strokeBorder(DT.Color.accent.opacity(0.2), lineWidth: 0.5)
                )
            }
        }
    }

    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: DT.Space.l) {
            Text(label)
                .font(DT.Font.bodyMedium)
                .foregroundStyle(DT.Color.textSecondary)
                .frame(width: 72, alignment: .trailing)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(DT.Font.mono)
                .padding(.horizontal, DT.Space.l)
                .padding(.vertical, DT.Space.m)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.row)
                        .fill(DT.Color.surfaceElevated.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.row)
                        .strokeBorder(DT.Color.strokeVariant, lineWidth: 0.5)
                )
        }
    }

    private var apiKeyRow: some View {
        HStack(spacing: DT.Space.l) {
            Text("API Key")
                .font(DT.Font.bodyMedium)
                .foregroundStyle(DT.Color.textSecondary)
                .frame(width: 72, alignment: .trailing)
            HStack(spacing: DT.Space.s) {
                Group {
                    if showAPIKey {
                        TextField("API Key", text: $settings.omnirouteAPIKey)
                            .textFieldStyle(.plain)
                            .font(DT.Font.mono)
                    } else {
                        SecureField("API Key", text: $settings.omnirouteAPIKey)
                            .textFieldStyle(.plain)
                            .font(DT.Font.mono)
                    }
                }
                .padding(.horizontal, DT.Space.l)
                .padding(.vertical, DT.Space.m)
                Button(action: { showAPIKey.toggle() }) {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .buttonStyle(.borderless)
            }
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.row)
                    .fill(DT.Color.surfaceElevated.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.row)
                    .strokeBorder(DT.Color.strokeVariant, lineWidth: 0.5)
            )
        }
    }
}
