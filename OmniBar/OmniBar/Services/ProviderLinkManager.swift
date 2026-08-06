//
//  ProviderLinkManager.swift
//  OmniBar
//
//  v2.0「AI 接入」编排器：把 omniroute 网关接入 Claude Code / Codex 的本地配置。
//  提供 enable / disable / 联动刷新，文件级操作交给 LiveConfig 各写器，备份回滚交给 BackupManager。
//

import Foundation
import Combine

// MARK: - 定位器（可注入，测试用临时目录）

/// 决定各 live 文件的位置。
protocol LinkLocator {
    var claudeSettingsURL: URL { get }
    var codexHomeURL: URL { get }
    var claudeDesktop: ClaudeDesktopURLs { get }
}

extension LinkLocator {
    var codexConfigURL: URL { codexHomeURL.appendingPathComponent("config.toml") }
    var codexAuthURL: URL { codexHomeURL.appendingPathComponent("auth.json") }
    var codexCatalogURL: URL { codexHomeURL.appendingPathComponent(CodexLiveConfig.catalogFileName) }
}

/// 默认定位器：指向真实的 ~/.claude、~/.codex 与 Claude Desktop 支持目录。
struct DefaultLinkLocator: LinkLocator {
    var claudeSettingsURL: URL { ClaudeCodeLiveConfig.defaultSettingsURL }
    var codexHomeURL: URL { CodexLiveConfig.defaultHomeURL }
    var claudeDesktop: ClaudeDesktopURLs { ClaudeDesktopLiveConfig.defaultURLs }
}

// MARK: - 结果与错误

enum LinkError: LocalizedError {
    case claudeCodeWriteFailed
    case codexAuthWriteFailed
    case codexConfigWriteFailed
    case codexCatalogWriteFailed
    case catalogTemplateUnavailable

    var errorDescription: String? {
        switch self {
        case .claudeCodeWriteFailed: return "Claude Code 配置写入失败"
        case .codexAuthWriteFailed: return "Codex auth.json 写入失败"
        case .codexConfigWriteFailed: return "Codex config.toml 写入失败"
        case .codexCatalogWriteFailed: return "Codex 模型目录写入失败"
        case .catalogTemplateUnavailable: return "无法获取 Codex 模型目录模板"
        }
    }
}

struct LinkResult: Equatable {
    let success: Bool
    let message: String?
    let error: LinkError?
}

/// 目标 live 配置当前的接管状态（6.6 冲突检测结果）。
enum TakeoverStatus: Equatable {
    /// 未被任何管理器接管；可安全接入。
    case none
    /// 已被其它管理器（如 cc-switch）接管；接入将覆盖其配置。
    case other(owner: String)
}


// MARK: - Manager

@MainActor
final class ProviderLinkManager: ObservableObject {
    private let settings: AppSettings
    private let backups: BackupManager
    private let locator: LinkLocator
    /// 联动刷新时取最新网关模型列表（由 AppDelegate 注入 OmnirouteService.gatewayModels）。
    private let modelsProvider: () -> [GatewayModel]
    /// Codex 模型目录模板来源（测试注入廉价模板，避免真实调用 codex CLI）。
    private let templateProvider: () -> [String: Any]
    private var cancellables: Set<AnyCancellable> = []
    private var applyingTargets: Set<LinkTarget> = []
    private var debounceTask: Task<Void, Never>?
    /// 上次观察到的「触发重写」的设置快照：仅端口 / Key / 模型选择变化才重写，
    /// 避免改轮询间隔等无关设置也重写用户 live 文件。
    private var lastRelevantSnapshot: (port: Int, apiKey: String, claudeModel: String, codexModel: String,
                                        desktopPort: Int, sonnet: String, opus: String, haiku: String, fable: String)?

    init(settings: AppSettings,
         locator: LinkLocator = DefaultLinkLocator(),
         backupDir: URL? = nil,
         modelsProvider: @escaping () -> [GatewayModel] = { [] },
         templateProvider: @escaping () -> [String: Any] = { ModelCatalogBuilder.resolveTemplate() }) {
        self.settings = settings
        self.locator = locator
        self.backups = BackupManager(directory: backupDir)
        self.modelsProvider = modelsProvider
        self.templateProvider = templateProvider
        self.lastRelevantSnapshot = Self.relevantSnapshot(of: settings)
        observeSettings()
    }

    /// 提取与 live 配置相关的设置快照（用于判断是否需要重写）。
    private static func relevantSnapshot(of settings: AppSettings)
        -> (port: Int, apiKey: String, claudeModel: String, codexModel: String,
            desktopPort: Int, sonnet: String, opus: String, haiku: String, fable: String) {
        (settings.omniroutePort, settings.omnirouteAPIKey,
         settings.linkClaudeModel, settings.linkCodexModel,
         settings.claudeDesktopProxyPort,
         settings.claudeDesktopSonnetModel, settings.claudeDesktopOpusModel,
         settings.claudeDesktopHaikuModel, settings.claudeDesktopFableModel)
    }

    private static func sameSnapshot(_ a: (port: Int, apiKey: String, claudeModel: String, codexModel: String,
                                           desktopPort: Int, sonnet: String, opus: String, haiku: String, fable: String),
                                     _ b: (port: Int, apiKey: String, claudeModel: String, codexModel: String,
                                           desktopPort: Int, sonnet: String, opus: String, haiku: String, fable: String)) -> Bool {
        a.port == b.port && a.apiKey == b.apiKey
            && a.claudeModel == b.claudeModel && a.codexModel == b.codexModel
            && a.desktopPort == b.desktopPort
            && a.sonnet == b.sonnet && a.opus == b.opus && a.haiku == b.haiku && a.fable == b.fable
    }

    var isClaudeCodeLinked: Bool { settings.linkClaudeCode }
    var isCodexLinked: Bool { settings.linkCodex }

    // MARK: - 网关参数

    /// 网关 /v1 前缀（Claude 的 ANTHROPIC_BASE_URL 与 Codex 的 provider base_url 共用）。
    var gatewayBaseURL: String {
        "http://localhost:\(settings.omniroutePort)/v1"
    }

    /// Claude Desktop 本地路由代理 base URL（3P profile 的 inferenceGatewayBaseUrl 指向它）。
    var claudeDesktopProxyBaseURL: String {
        "http://127.0.0.1:\(settings.claudeDesktopProxyPort)"
    }

    /// 各角色的真实网关模型（优先逐角色设置，其次跟随 linkClaudeModel，最后网关首模型/兜底）。
    func claudeRoleModels(gatewayModels: [GatewayModel]) -> [ClaudeRole: String] {
        let fallback = model(for: .claudeCode, gatewayModels: gatewayModels)
        var result: [ClaudeRole: String] = [:]
        for role in ClaudeRole.allCases {
            let stored: String
            switch role {
            case .sonnet: stored = settings.claudeDesktopSonnetModel
            case .opus: stored = settings.claudeDesktopOpusModel
            case .haiku: stored = settings.claudeDesktopHaikuModel
            case .fable: stored = settings.claudeDesktopFableModel
            }
            result[role] = stored.isEmpty ? fallback : stored
        }
        return result
    }

    func isLinked(_ target: LinkTarget) -> Bool {
        switch target {
        case .claudeCode: return settings.linkClaudeCode
        case .codex: return settings.linkCodex
        }
    }

    /// 目标默认模型：优先用户选择，其次活动 combo / 网关第一个模型，最后兜底。
    func model(for target: LinkTarget, gatewayModels: [GatewayModel]) -> String {
        let stored: String
        switch target {
        case .claudeCode: stored = settings.linkClaudeModel
        case .codex: stored = settings.linkCodexModel
        }
        if !stored.isEmpty { return stored }
        if let first = gatewayModels.first(where: { !$0.id.isEmpty }) { return first.id }
        return "auto/best-fast"
    }

    // MARK: - 启用 / 关闭

    /// 启用目标（幂等：重复调用会刷新配置而不重建快照）。
    @discardableResult
    func enable(_ target: LinkTarget, gatewayModels: [GatewayModel]) async -> LinkResult {
        guard !applyingTargets.contains(target) else {
            return LinkResult(success: false, message: "操作进行中，请稍候", error: nil)
        }
        applyingTargets.insert(target)
        defer { applyingTargets.remove(target) }

        switch target {
        case .claudeCode: return await enableClaudeCode(gatewayModels: gatewayModels)
        case .codex: return await enableCodex(gatewayModels: gatewayModels)
        }
    }

    /// 关闭目标：回滚备份（无备份则剥离托管内容）。
    @discardableResult
    func disable(_ target: LinkTarget) async -> LinkResult {
        guard !applyingTargets.contains(target) else {
            return LinkResult(success: false, message: "操作进行中，请稍候", error: nil)
        }
        applyingTargets.insert(target)
        defer { applyingTargets.remove(target) }

        switch target {
        case .claudeCode: return disableClaudeCode()
        case .codex: return disableCodex()
        }
    }

    /// 便捷：按目标当前开关状态调用 enable/disable。
    @discardableResult
    func toggle(_ target: LinkTarget, gatewayModels: [GatewayModel]) async -> LinkResult {
        if isLinked(target) {
            return await enable(target, gatewayModels: gatewayModels)
        } else {
            return await disable(target)
        }
    }

    // MARK: - 冲突检测（6.6）

    /// 接管前检测：目标 live 文件当前是否被其它管理器接管。
    /// 网关自身的 base_url 不算「其它管理器」，仅当指向到非本网关的第三方端点 / 其它哨兵时判定。
    func takeoverStatus(for target: LinkTarget) -> TakeoverStatus {
        switch target {
        case .claudeCode: return claudeTakeoverStatus()
        case .codex: return codexTakeoverStatus()
        }
    }

    /// Claude Code：`settings.json` 的 env.ANTHROPIC_BASE_URL 指向非本网关 → 其它管理器托管。
    private func claudeTakeoverStatus() -> TakeoverStatus {
        guard let existing = ClaudeCodeLiveConfig.readExisting(from: locator.claudeSettingsURL),
              let env = existing["env"] as? [String: String],
              let baseURL = env["ANTHROPIC_BASE_URL"],
              !baseURL.isEmpty else { return .none }
        // 指向本地 omniroute 网关的视为已由 OmniBar 接管（幂等刷新），不判定为冲突
        if baseURL == gatewayBaseURL { return .none }
        return .other(owner: "其它工具（cc-switch 等）")
    }

    /// Codex：`config.toml` 含其它管理器的哨兵 / 第三方 base_url → 其它管理器托管。
    private func codexTakeoverStatus() -> TakeoverStatus {
        guard let text = CodexLiveConfig.readConfig(from: locator.codexConfigURL) else { return .none }
        // 其它管理器的哨兵（cc-switch 目录名 / 代理标记等能力提示）
        let foreignMarkers = ["cc-switch-model-catalog", "PROXY_MANAGED"]
        if foreignMarkers.first(where: { text.contains($0) }) != nil {
            return .other(owner: "cc-switch / 其它代理")
        }
        // provider 表 base_url 指向非本网关
        if text.contains("base_url"), !text.contains("\"\(gatewayBaseURL)\"") {
            // 仅当确实有 base_url 且不含本网关时提示（避免误报）
            return .other(owner: "其它代理")
        }
        return .none
    }

    /// 接管后检测：OmniBar 已托管但 live 文件被外部改写（托管键被删/改）。
    /// - 检测到外来写入时供 UI 提供「一键恢复」。
    func isExternallyModified(_ target: LinkTarget) -> Bool {
        switch target {
        case .claudeCode:
            // 本应含托管 env 键（开关开启时），若缺失则认为被外部改写
            guard settings.linkClaudeCode else { return false }
            return !ClaudeCodeLiveConfig.isManaged(settingsURL: locator.claudeSettingsURL)
        case .codex:
            guard settings.linkCodex else { return false }
            return !CodexLiveConfig.isManaged(homeURL: locator.codexHomeURL)
        }
    }

    // MARK: - 具体实现

    private func enableClaudeCode(gatewayModels: [GatewayModel]) async -> LinkResult {
        let model = model(for: .claudeCode, gatewayModels: gatewayModels)
        backups.ensureBackup(of: locator.claudeSettingsURL, marker: LinkTarget.claudeCode.marker)
        do {
            try ClaudeCodeLiveConfig.enable(settingsURL: locator.claudeSettingsURL,
                                            baseURL: gatewayBaseURL,
                                            apiKey: settings.omnirouteAPIKey,
                                            model: model)
            // M4/M5：同步接入 Claude Desktop（3P 部署，v2.1 模型映射代理模式：inferenceModels + 指向本地路由代理）
            let roleModels = claudeRoleModels(gatewayModels: gatewayModels)
            let desktopOK = ClaudeDesktopLiveConfig.enable(urls: locator.claudeDesktop,
                                                           baseURL: claudeDesktopProxyBaseURL,
                                                           apiKey: settings.omnirouteAPIKey,
                                                           roleModels: roleModels)
            let message = desktopOK ? "Claude Code · Claude Desktop 已接入网关" : "Claude Code 已接入；Claude Desktop 写入失败"
            let error: LinkError? = desktopOK ? nil : .claudeCodeWriteFailed
            return LinkResult(success: true, message: message, error: error)
        } catch {
            return LinkResult(success: false, message: "Claude Code 配置写入失败：\(error.localizedDescription)", error: .claudeCodeWriteFailed)
        }
    }

    private func enableCodex(gatewayModels: [GatewayModel]) async -> LinkResult {
        let model = model(for: .codex, gatewayModels: gatewayModels)
        // 1) 备份既有文件（幂等：仅第一次真正复制）
        backups.ensureBackup(of: locator.codexConfigURL, marker: LinkTarget.codex.marker)
        backups.ensureBackup(of: locator.codexAuthURL, marker: LinkTarget.codex.marker)

        // 2) 生成模型目录（模板缺失时回退到静态模板，仍可写）
        let template = templateProvider()
        let entries: [[String: Any]]
        if gatewayModels.isEmpty {
            // 网关暂未返回模型列表：至少把当前选中模型暴露出去
            var entry = ModelCatalogBuilder.nativeProfile(stripping: template)
            entry["slug"] = model
            entry["display_name"] = model
            entry["description"] = model
            entries = [entry]
        } else {
            entries = ModelCatalogBuilder.buildEntries(models: gatewayModels, template: template)
        }
        do {
            let catalog = try ModelCatalogBuilder.catalogJSON(entries: entries)
            try AtomicWriter.write(catalog, to: locator.codexCatalogURL)
        } catch {
            return LinkResult(success: false, message: "Codex 模型目录写入失败", error: .codexCatalogWriteFailed)
        }

        // 3) 写 auth.json + config.toml
        let (authOK, configOK) = CodexLiveConfig.enable(homeURL: locator.codexHomeURL,
                                                        baseURL: gatewayBaseURL,
                                                        model: model,
                                                        apiKey: settings.omnirouteAPIKey)
        // 任一步失败：清理已写的模型目录，避免残留半套配置
        let cleanupCatalog = { [locator] in
            try? FileManager.default.removeItem(at: locator.codexCatalogURL)
        }
        if !authOK {
            cleanupCatalog()
            return LinkResult(success: false, message: "Codex auth.json 写入失败", error: .codexAuthWriteFailed)
        }
        if !configOK {
            // auth 已写成功而 config 失败：回滚 auth 到接入前状态（对齐 cc-switch 行为）
            _ = backups.restore(liveURL: locator.codexAuthURL, marker: LinkTarget.codex.marker)
            cleanupCatalog()
            return LinkResult(success: false, message: "Codex config.toml 写入失败", error: .codexConfigWriteFailed)
        }
        return LinkResult(success: true, message: "Codex 已接入网关", error: nil)
    }

    private func disableClaudeCode() -> LinkResult {
        // 先判断当前是否真的被接管（判断必须在剥离之前做）
        let managedNow = ClaudeCodeLiveConfig.isManaged(settingsURL: locator.claudeSettingsURL)
        let hadBackup = backups.hasBackup(liveURL: locator.claudeSettingsURL, marker: LinkTarget.claudeCode.marker)
        // 仅在确实被接管（含托管键）时才剥离写回；失败不阻断后续备份回滚（回滚是最终还原手段）。
        // 未接管时不得调用 disable 重写用户文件（否则会把用户原有 settings.json 重新序列化、改变字节内容）。
        var strippedOK = true
        if managedNow {
            strippedOK = (try? ClaudeCodeLiveConfig.disable(settingsURL: locator.claudeSettingsURL)) != nil
        }
        // 仅在确实接管过（有备份或当前含托管内容）时才回滚/删除，
        // 避免从未接入过的情况下误删用户原有配置文件
        var restored = true
        if hadBackup || managedNow {
            restored = backups.restore(liveURL: locator.claudeSettingsURL, marker: LinkTarget.claudeCode.marker)
        }
        backups.cleanup(liveURL: locator.claudeSettingsURL, marker: LinkTarget.claudeCode.marker)
        // M4：若 Claude Desktop 已被接管，恢复官方（deploymentMode 1p + 删除 profile）。独立于 CLI 配置。
        let desktopManaged = ClaudeDesktopLiveConfig.isManaged(locator.claudeDesktop)
        if desktopManaged {
            _ = ClaudeDesktopLiveConfig.disable(urls: locator.claudeDesktop)
        }
        let message: String
        if restored {
            if hadBackup || managedNow {
                message = strippedOK ? "Claude Code 已断开" : "Claude Code 已断开（剥离残留，已从备份还原）"
            } else {
                message = "Claude Code 已断开（未检测到接管配置）"
            }
        } else {
            message = "Claude Code 断开失败"
        }
        return LinkResult(success: restored, message: message, error: nil)
    }

    private func disableCodex() -> LinkResult {
        // 判断是否真被接管（必须在剥离之前做）
        let managedNow = CodexLiveConfig.isManaged(homeURL: locator.codexHomeURL)
        let hadBackup = backups.hasBackup(liveURL: locator.codexConfigURL, marker: LinkTarget.codex.marker)
        // 剥离 config.toml 托管块；auth.json 由备份回滚（写器不再置空密钥）
        let strippedOK = CodexLiveConfig.disable(homeURL: locator.codexHomeURL)
        // 仅在确实接管过时才回滚/删除，避免误删用户原有 ~/.codex 配置
        var configRestored = true
        var authRestored = true
        if hadBackup || managedNow {
            configRestored = backups.restore(liveURL: locator.codexConfigURL, marker: LinkTarget.codex.marker)
            authRestored = backups.restore(liveURL: locator.codexAuthURL, marker: LinkTarget.codex.marker)
        }
        backups.cleanup(liveURL: locator.codexConfigURL, marker: LinkTarget.codex.marker)
        backups.cleanup(liveURL: locator.codexAuthURL, marker: LinkTarget.codex.marker)
        try? FileManager.default.removeItem(at: locator.codexCatalogURL)
        let ok = configRestored && authRestored
        let message: String
        if ok {
            if hadBackup || managedNow {
                message = strippedOK ? "Codex 已断开" : "Codex 已断开（剥离残留，已从备份还原）"
            } else {
                message = "Codex 已断开（未检测到接管配置）"
            }
        } else {
            message = "Codex 断开失败"
        }
        return LinkResult(success: ok, message: message, error: nil)
    }

    // MARK: - 联动刷新（端口 / API Key / 模型变更后自动重写）

    /// 以最新模型列表对已开启目标幂等重写。
    /// 供「设置相关项变化防抖后」「网关模型列表加载完成后」调用。
    func refreshIfLinked() async {
        let models = modelsProvider()
        if isClaudeCodeLinked {
            _ = await enable(.claudeCode, gatewayModels: models)
        }
        if isCodexLinked {
            _ = await enable(.codex, gatewayModels: models)
        }
    }

    private func observeSettings() {
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // 只对与 live 配置相关的设置（端口/Key/模型选择）变化触发重写，
                // 避免改轮询间隔等无关设置也重写用户配置文件
                let snapshot = Self.relevantSnapshot(of: self.settings)
                if let last = self.lastRelevantSnapshot, Self.sameSnapshot(snapshot, last) {
                    return
                }
                self.lastRelevantSnapshot = snapshot
                self.scheduleRefreshIfLinked()
            }
            .store(in: &cancellables)
    }

    private func scheduleRefreshIfLinked() {
        guard isClaudeCodeLinked || isCodexLinked else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            // 刷新时取最新模型列表，保证 Codex 模型目录与 Claude 默认模型跟得上网关变化
            await self.refreshIfLinked()
        }
    }
}