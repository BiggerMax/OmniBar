//
//  SettingsView.swift
//  OmniBar
//
//  设置窗口：左侧品牌 + nav，右侧 content（1:1 还原 Stitch 设计）
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var selection: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general, connection, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "通用"
            case .connection: return "连接"
            case .about: return "关于"
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .connection: return "hub"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().background(DT.Color.strokeVariant)
            contentArea
        }
        .frame(width: 613, height: 453)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                .fill(DT.Color.surface.opacity(0.75))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                .strokeBorder(DT.Color.stroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 25, x: 0, y: 25)
    }

    // MARK: 侧边栏
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: DT.Space.m) {
            // 品牌头
            HStack(spacing: DT.Space.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: DT.Radius.row)
                        .fill(DT.Color.accent)
                        .frame(width: 32, height: 32)
                        .shadow(color: DT.Color.accent.opacity(0.4), radius: 8, x: 0, y: 4)
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("OmniBar")
                        .font(DT.Font.headline)
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("Gateway v1.0")
                        .font(DT.Font.micro)
                        .foregroundStyle(DT.Color.textSecondary.opacity(0.5))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
            }
            .padding(.horizontal, DT.Space.m)
            .padding(.bottom, DT.Space.xxl)

            // Nav
            VStack(spacing: DT.Space.xxs) {
                ForEach(Tab.allCases) { tab in
                    navItem(tab)
                }
            }
            Spacer()
            Text("DEV_MODE::ACTIVE")
                .font(DT.Font.monoTiny)
                .foregroundStyle(DT.Color.textSecondary.opacity(0.3))
                .padding(.horizontal, DT.Space.m)
        }
        .padding(.vertical, DT.Space.xl)
        .padding(.horizontal, DT.Space.m)
        .frame(width: 192, alignment: .leading)
        .background(DT.Color.surface.opacity(0.8).background(.ultraThinMaterial))
    }

    private func navItem(_ tab: Tab) -> some View {
        Button {
            selection = tab
        } label: {
            HStack(spacing: DT.Space.l) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(tab.title)
                    .font(DT.Font.bodyMedium)
                Spacer()
            }
            .padding(.horizontal, DT.Space.l)
            .padding(.vertical, DT.Space.s)
            .foregroundStyle(selection == tab ? DT.Color.accent : DT.Color.textSecondary.opacity(0.7))
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .fill(selection == tab ? DT.Color.accentSoft : .clear)
            )
        }
        .buttonStyle(.borderless)
    }

    // MARK: 内容区
    @ViewBuilder
    private var contentArea: some View {
        Group {
            switch selection {
            case .general: GeneralSettings(settings: settings)
            case .connection: ConnectionSettings(settings: settings)
            case .about: AboutSettings()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 40)
        .padding(.horizontal, DT.Space.xxxl)
        .padding(.bottom, DT.Space.xxxl)
        .background(
            // 顶部标题浮层
            ZStack(alignment: .topTrailing) {
                DT.Color.clear
                Text("OmniBar Settings")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(DT.Color.accent)
                    .padding(.trailing, DT.Space.xl)
                    .padding(.top, DT.Space.m)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing),
            alignment: .top
        )
    }
}
