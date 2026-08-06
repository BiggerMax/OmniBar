//
//  SettingsView.swift
//  OmniBar
//
//  设置窗口：左侧品牌 + nav，右侧 content（1:1 还原 Stitch 设计）
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var service: OmnirouteService?
    var linkManager: ProviderLinkManager?
    @State private var selection: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general, connection, link, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "通用"
            case .connection: return "连接"
            case .link: return "AI 接入"
            case .about: return "关于"
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .connection: return "hub"
            case .link: return "arrow.triangle.branch"
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
        .frame(width: DT.Layout.settingsWidth, height: DT.Layout.settingsHeight)
        // 设置窗口顶部贴系统标题栏：只圆底部两角，消除顶部圆角空隙
        .liquidGlassPanel(cornerRadius: DT.Radius.card, bottomCornersOnly: true)
        // 跟随系统深浅色：不强制深色，DT.Color 动态色自动切换
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
                    Text("Gateway v2.0")
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
        .background(DT.Color.surface.opacity(0.5))
    }

    private func navItem(_ tab: Tab) -> some View {
        let isSelected = selection == tab
        return Button {
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
            // ClashMac 选中态：靛蓝实心胶囊白字
            .foregroundStyle(isSelected ? Color.white : DT.Color.textSecondary.opacity(0.75))
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .fill(isSelected ? DT.Color.accent : .clear)
            )
        }
        .buttonStyle(.borderless)
    }

    // MARK: 内容区
    /// 动态解析：Settings scene 只构建一次，启动时捕获的 linkManager 可能为 nil；
    /// 因此在渲染时从 AppDelegate.shared 实时取（NSApp.delegate 是协议抽象类型，无法 as? AppDelegate）。
    private var resolvedLinkManager: ProviderLinkManager? {
        linkManager ?? AppDelegate.shared?.linkManager
    }

    @ViewBuilder
    private var contentArea: some View {
        Group {
            switch selection {
            case .general: GeneralSettings(settings: settings, service: service)
            case .connection: ConnectionSettings(settings: settings)
            case .link:
                if let manager = resolvedLinkManager {
                    AIIntegrationSettings(settings: settings, service: service, manager: manager)
                } else {
                    Text("AI 接入不可用（未初始化）")
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
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
