//
//  AIIntegrationSection.swift
//  OmniBar
//
//  v2.0「AI 接入」可复用区块：Claude Code / Codex 接入卡片 + 全部开关/回滚逻辑。
//  同时供设置窗口（AIIntegrationSettings）与 Popover 路由页（AIIntegrationPanel）复用，
//  保证两处交互与视觉完全一致。
//

import SwiftUI

// MARK: - 可复用接入区块

/// 两张接入卡片（Claude Code / Codex）+ 开关 / 回滚 / 模型填充逻辑。
/// 设置窗口与 Popover 路由页共用。
struct AIIntegrationSection: View {
    @ObservedObject var settings: AppSettings
    var service: OmnirouteService?
    @ObservedObject var manager: ProviderLinkManager

    @State private var claudeBusy = false
    @State private var codexBusy = false
    @State private var claudeMessage: String?
    @State private var codexMessage: String?

    private var models: [GatewayModel] { service?.gatewayModels ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.xxxl) {
            section(title: "Claude Code · Claude Desktop") {
                TargetCard(
                    target: .claudeCode,
                    isOn: $settings.linkClaudeCode,
                    isBusy: claudeBusy,
                    message: claudeMessage,
                    models: models,
                    selectedModel: $settings.linkClaudeModel,
                    conflictNote: conflictNote(for: .claudeCode),
                    externallyModified: manager.isExternallyModified(.claudeCode),
                    onToggle: { toggleLink(.claudeCode, on: $0) },
                    onRestore: { restoreLink(.claudeCode) }
                )
                if settings.linkClaudeCode {
                    ClaudeDesktopMappingCard(settings: settings, models: models)
                }
            }
            section(title: "Codex · ChatGPT Desktop") {
                TargetCard(
                    target: .codex,
                    isOn: $settings.linkCodex,
                    isBusy: codexBusy,
                    message: codexMessage,
                    models: models,
                    selectedModel: $settings.linkCodexModel,
                    conflictNote: conflictNote(for: .codex),
                    externallyModified: manager.isExternallyModified(.codex),
                    onToggle: { toggleLink(.codex, on: $0) },
                    onRestore: { restoreLink(.codex) }
                )
            }
        }
        .onAppear { fillDefaultModelsIfEmpty() }
        .onChange(of: models.count) { _, _ in fillDefaultModelsIfEmpty() }
    }

    // MARK: - 逻辑

    /// 接管前冲突提示：仅当目标尚未开启且被其它管理器接管时显示。
    private func conflictNote(for target: LinkTarget) -> String? {
        guard !(target == .claudeCode ? settings.linkClaudeCode : settings.linkCodex) else { return nil }
        switch manager.takeoverStatus(for: target) {
        case .none: return nil
        case .other(let owner): return "⚠️ 当前由 \(owner) 托管，开启将覆盖其配置（已自动备份可回滚）"
        }
    }

    /// 一键恢复外部改写：重新 enable（幂等）把托管配置写回。
    private func restoreLink(_ target: LinkTarget) {
        Task { @MainActor in
            switch target {
            case .claudeCode:
                claudeBusy = true
                _ = await manager.enable(.claudeCode, gatewayModels: models)
                claudeBusy = false
                claudeMessage = "已恢复托管配置"
            case .codex:
                codexBusy = true
                _ = await manager.enable(.codex, gatewayModels: models)
                codexBusy = false
                codexMessage = "已恢复托管配置"
            }
        }
    }

    private func toggleLink(_ target: LinkTarget, on: Bool) {
        let gatewayModels = models
        Task { @MainActor in
            switch target {
            case .claudeCode:
                claudeBusy = true
                claudeMessage = nil
                let result = await manager.toggle(.claudeCode, gatewayModels: gatewayModels)
                claudeBusy = false
                claudeMessage = result.message
                if !result.success {
                    // 写入失败回滚开关
                    settings.linkClaudeCode = on ? false : true
                }
            case .codex:
                codexBusy = true
                codexMessage = nil
                let result = await manager.toggle(.codex, gatewayModels: gatewayModels)
                codexBusy = false
                codexMessage = result.message
                if !result.success {
                    settings.linkCodex = on ? false : true
                }
            }
        }
    }

    /// 模型选择为空时，用网关第一个模型填充（避免用户手动选型）。
    private func fillDefaultModelsIfEmpty() {
        if settings.linkClaudeModel.isEmpty, let first = models.first {
            settings.linkClaudeModel = first.id
        }
        if settings.linkCodexModel.isEmpty, let first = models.first {
            settings.linkCodexModel = first.id
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
}

// MARK: - Popover 路由页

/// Popover 内的「AI 接入」完整页：顶部返回 + 可滚动接入卡片区。
struct AIIntegrationPanel: View {
    @ObservedObject var settings: AppSettings
    var service: OmnirouteService?
    var manager: ProviderLinkManager?
    let onClose: () -> Void

    /// 内容区实际可用宽度 = 面板宽 - 左右 padding(16*2)
    private var contentWidth: CGFloat { DT.Layout.panelWidth - DT.Space.xl * 2 }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let manager {
                ScrollView(.vertical, showsIndicators: false) {
                    AIIntegrationSection(settings: settings, service: service, manager: manager)
                        .frame(width: contentWidth, alignment: .leading)
                        .padding(DT.Space.xl)
                        .padding(.bottom, 32) // 给底部 Action Bar 留位置
                }
                .scrollIndicators(.hidden)
                .introspectScrollView { nssv in
                    NSScrollView.omnibarHideScrollbars(nssv)
                }
            } else {
                Spacer()
                Text("AI 接入不可用（未初始化）")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: DT.Space.m) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .frame(width: 22, height: 22)
            }
            .interactiveButton()
            Text("AI 接入")
                .font(DT.Font.headline)
                .foregroundStyle(DT.Color.textPrimary)
            Spacer()
        }
        .padding(.horizontal, DT.Space.xl)
        .padding(.vertical, DT.Space.l)
        // 背景透明：玻璃由根视图 .glassEffect 提供，这里只留一条细分隔线
        .overlay(
            Rectangle().fill(DT.Color.stroke).frame(height: 0.5),
            alignment: .bottom
        )
    }
}


// MARK: - 目标卡片

private struct TargetCard: View {
    let target: LinkTarget
    @Binding var isOn: Bool
    let isBusy: Bool
    let message: String?
    let models: [GatewayModel]
    @Binding var selectedModel: String
    let conflictNote: String?
    let externallyModified: Bool
    let onToggle: (Bool) -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.l) {
            DCard(padding: 0) {
                VStack(spacing: 0) {
                    header
                    Divider().background(DT.Color.strokeVariant).padding(.horizontal, DT.Space.l)
                    modelRow
                    if let message {
                        Divider().background(DT.Color.strokeVariant).padding(.horizontal, DT.Space.l)
                        HStack(spacing: DT.Space.m) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(message.contains("失败") ? DT.Color.danger : DT.Color.success)
                            Text(message)
                                .font(DT.Font.micro)
                                .foregroundStyle(message.contains("失败") ? DT.Color.danger : DT.Color.textSecondary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, DT.Space.l)
                        .padding(.vertical, DT.Space.m)
                    }
                    if externallyModified {
                        Divider().background(DT.Color.strokeVariant).padding(.horizontal, DT.Space.l)
                        HStack(spacing: DT.Space.m) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DT.Color.warning)
                            Text("配置被外部工具修改")
                                .font(DT.Font.micro)
                                .foregroundStyle(DT.Color.warning)
                            Spacer()
                            Button("一键恢复", action: onRestore)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        .padding(.horizontal, DT.Space.l)
                        .padding(.vertical, DT.Space.m)
                    } else if let conflictNote, !isOn {
                        Divider().background(DT.Color.strokeVariant).padding(.horizontal, DT.Space.l)
                        Text(conflictNote)
                            .font(DT.Font.micro)
                            .foregroundStyle(DT.Color.warning)
                            .padding(.horizontal, DT.Space.l)
                            .padding(.vertical, DT.Space.m)
                    }
                }
            }
            // 接入中的路径提示
            if isOn {
                Text(pathHint)
                    .font(DT.Font.micro)
                    .foregroundStyle(DT.Color.textTertiary)
                    .padding(.leading, DT.Space.xs)
            }
        }
    }

private var header: some View {
        HStack(spacing: DT.Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: DT.Radius.row)
                    .fill(isOn ? DT.Color.accent : DT.Color.surfaceElevated)
                    .frame(width: 30, height: 30)
                Image(systemName: target.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? .white : DT.Color.textSecondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(target.title)
                    .font(DT.Font.bodySemibold)
                    .foregroundStyle(DT.Color.textPrimary)
                Text(target.subtitle)
                    .font(DT.Font.micro)
                    .foregroundStyle(DT.Color.textTertiary)
            }
            Spacer()
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(DT.Color.accent)
                .labelsHidden()
                .disabled(isBusy)
                .onChange(of: isOn) { _, newValue in onToggle(newValue) }
        }
        .padding(.horizontal, DT.Space.l)
        .padding(.vertical, DT.Space.l)
    }

    private var modelRow: some View {
        HStack(spacing: DT.Space.l) {
            Text("模型")
                .font(DT.Font.bodyMedium)
                .foregroundStyle(isOn ? DT.Color.textSecondary : DT.Color.textSecondary.opacity(0.5))
                .frame(width: 48, alignment: .leading)
            Spacer()
            if models.isEmpty {
                TextField("模型 ID（如 auto/best-fast）", text: $selectedModel)
                    .textFieldStyle(.plain)
                    .font(DT.Font.monoSmall)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(isOn ? DT.Color.textPrimary : DT.Color.textSecondary.opacity(0.5))
                    .disabled(!isOn)
            } else {
                GroupedModelPicker(selection: $selectedModel, models: models)
                    .disabled(!isOn)
            }
        }
        .padding(.horizontal, DT.Space.l)
        .padding(.vertical, DT.Space.l)
    }

    private var pathHint: String {
        switch target {
        case .claudeCode: return "写入 ~/.claude/settings.json 的 env 块（保留其余配置）"
        case .codex: return "写入 ~/.codex/config.toml / auth.json，并生成 omnibar-model-catalog.json"
        }
    }
}

// MARK: - Claude Desktop 角色模型映射

/// Claude Desktop 3P 接入的角色模型映射：Sonnet/Opus/Haiku/Fable 各自对应的真实网关模型。
/// 留空跟随上方「模型」选择；由本地路由代理（ClaudeRouteProxy）把角色 ID 重写为真实模型。
private struct ClaudeDesktopMappingCard: View {
    @ObservedObject var settings: AppSettings
    let models: [GatewayModel]

    private var bindings: [ClaudeRole: Binding<String>] {
        [
            .sonnet: $settings.claudeDesktopSonnetModel,
            .opus: $settings.claudeDesktopOpusModel,
            .haiku: $settings.claudeDesktopHaikuModel,
            .fable: $settings.claudeDesktopFableModel,
        ]
    }

    var body: some View {
        DCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: DT.Space.m) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.Color.accent)
                    Text("Claude Desktop 角色模型映射")
                        .font(DT.Font.bodyMedium)
                        .foregroundStyle(DT.Color.textPrimary)
                    Spacer()
                    Text("留空跟随上方模型")
                        .font(DT.Font.micro)
                        .foregroundStyle(DT.Color.textTertiary)
                }
                .padding(.horizontal, DT.Space.l)
                .padding(.vertical, DT.Space.l)
                Divider().background(DT.Color.strokeVariant).padding(.horizontal, DT.Space.l)
                ForEach(ClaudeRole.allCases) { role in
                    mappingRow(role: role)
                    if role != ClaudeRole.allCases.last {
                        Divider().background(DT.Color.strokeVariant).padding(.horizontal, DT.Space.l)
                    }
                }
            }
        }
    }

    private func mappingRow(role: ClaudeRole) -> some View {
        HStack(spacing: DT.Space.l) {
            Text(role.title)
                .font(DT.Font.bodyMedium)
                .foregroundStyle(DT.Color.textSecondary)
                .frame(width: 48, alignment: .leading)
            Spacer()
            if models.isEmpty {
                TextField("模型 ID（留空跟随）", text: bindings[role]!)
                    .textFieldStyle(.plain)
                    .font(DT.Font.monoSmall)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(DT.Color.textPrimary)
            } else {
                GroupedModelPicker(selection: bindings[role]!, models: models, emptyLabel: "跟随上方模型")
            }
        }
        .padding(.horizontal, DT.Space.l)
        .padding(.vertical, DT.Space.l)
    }
}

// MARK: - 分组模型下拉

/// 按 provider 分组的模型下拉菜单（替代扁平 Picker）：
/// 每个 provider 一组，组标题 + Divider 分隔；auto（智能路由别名）置顶，其余按名称排序。
private struct GroupedModelPicker: View {
    @Binding var selection: String
    let models: [GatewayModel]
    var emptyLabel: String = "选择模型"

    /// provider -> 模型（组内保持网关原始顺序）
    private var groups: [(provider: String, models: [GatewayModel])] {
        let byProvider = Dictionary(grouping: models) { $0.provider }
        return byProvider
            .map { (provider: $0.key, models: $0.value) }
            .sorted { lhs, rhs in
                if lhs.provider == "auto" { return true }
                if rhs.provider == "auto" { return false }
                return lhs.provider.localizedStandardCompare(rhs.provider) == .orderedAscending
            }
    }

    /// 当前选中模型的短名（未选中时给占位文案）
    private var selectedLabel: String {
        models.first(where: { $0.id == selection })?.displayName
            ?? (selection.isEmpty ? emptyLabel : selection)
    }

    var body: some View {
        Menu {
            ForEach(groups, id: \.provider) { group in
                Text(group.provider)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DT.Color.accent)
                ForEach(group.models) { model in
                    Button {
                        selection = model.id
                    } label: {
                        Text(model.displayName)
                    }
                }
                if group.provider != groups.last?.provider {
                    Divider()
                }
            }
        } label: {
            HStack(spacing: DT.Space.xs) {
                Text(selectedLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary.opacity(0.5))
            }
            .font(DT.Font.monoSmall)
            .foregroundStyle(DT.Color.textPrimary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .tint(DT.Color.accent)
    }
}

