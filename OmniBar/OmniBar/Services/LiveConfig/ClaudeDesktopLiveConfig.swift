//
//  ClaudeDesktopLiveConfig.swift
//  OmniBar
//
//  v2.0 M4：Claude Desktop（Claude Code desktop）3P 模式的接入。
//  按 cc-switch 同款路径写入 3P 部署文件：deploymentMode + configLibrary profile + _meta 激活。
//  v2.1 方案 B（模型映射代理模式）：profile 写 inferenceModels（claude-sonnet-*/claude-opus-*/claude-haiku-*/claude-fable-*）
//  并把 inferenceGatewayBaseUrl 指向本地 ClaudeRouteProxy（127.0.0.1:<proxyPort>），由代理把角色 ID 重写为真实网关模型。
//

import Foundation

/// Claude Desktop 3P 部署涉及的各文件路径（可注入，测试用临时目录）。
struct ClaudeDesktopURLs {
    /// ~/Library/Application Support/Claude/claude_desktop_config.json
    let claudeAppConfig: URL
    /// ~/Library/Application Support/Claude-3p/claude_desktop_config.json
    let claude3pConfig: URL
    /// ~/Library/Application Support/Claude-3p/configLibrary/
    let libraryDir: URL

    /// profile 文件（<profileID>.json）
    var profileURL: URL { libraryDir.appendingPathComponent("\(ClaudeDesktopLiveConfig.profileID).json") }
    /// 激活元数据
    var metaURL: URL { libraryDir.appendingPathComponent("_meta.json") }
}

/// Claude Desktop live config 读写。纯函数 + 原子写入，可单测（注入临时路径）。
enum ClaudeDesktopLiveConfig {

    /// OmniBar 的 profile 固定 ID（合法 UUID 格式，供识别与删除）。
    static let profileID = "D1CE0000-0000-4000-8000-00000000C0DE"
    static let profileName = "OmniBar"

    // MARK: - 路径

    static var defaultURLs: ClaudeDesktopURLs {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let claudeDir = base.appendingPathComponent("Claude", isDirectory: true)
        let claude3pDir = base.appendingPathComponent("Claude-3p", isDirectory: true)
        return ClaudeDesktopURLs(
            claudeAppConfig: claudeDir.appendingPathComponent("claude_desktop_config.json"),
            claude3pConfig: claude3pDir.appendingPathComponent("claude_desktop_config.json"),
            libraryDir: claude3pDir.appendingPathComponent("configLibrary", isDirectory: true)
        )
    }

    // MARK: - profile 内容（v2.1 模型映射代理模式）

    /// 生成 profile JSON。写 inferenceModels（4 个角色 ID），网关指向本地路由代理。
    static func profileJSON(baseURL: String, apiKey: String, roleModels: [ClaudeRole: String]) -> [String: Any] {
        let inferenceModels: [[String: Any]] = ClaudeRole.allCases.map { role in
            let real = roleModels[role] ?? ""
            return [
                "name": role.roleModelID,
                "labelOverride": real.isEmpty ? role.title : real,
            ]
        }
        return [
            "coworkEgressAllowedHosts": ["*"],
            "disableDeploymentModeChooser": true,
            "inferenceGatewayApiKey": apiKey,
            "inferenceGatewayAuthScheme": "bearer",
            "inferenceGatewayBaseUrl": baseURL,
            "inferenceModels": inferenceModels,
            "inferenceProvider": "gateway",
        ]
    }

    /// 生成 _meta.json（激活本 profile）。
    static func metaJSON(appliedID: String, entries: [[String: Any]]) -> [String: Any] {
        ["appliedId": appliedID, "entries": entries]
    }

    // MARK: - 读取 / 判断

    /// 是否已被 OmniBar 接管（profile 文件存在即视为已接管）。
    static func isManaged(_ urls: ClaudeDesktopURLs) -> Bool {
        FileManager.default.fileExists(atPath: urls.profileURL.path)
    }

    /// 读取现有 3p config（JSON 字典），缺失/损坏返回 nil。
    static func readConfig(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// 强制把 deploymentMode 设为指定值并写回（保留其余键）。
    static func setDeploymentMode(_ url: URL, mode: String) throws {
        var dict = readConfig(url) ?? [:]
        dict["deploymentMode"] = mode
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try AtomicWriter.write(data, to: url)
    }

    // MARK: - 启用 / 关闭（文件级，路径可注入）

    /// 启用：写入 3P 部署文件。返回写入是否成功的各标记。
    @discardableResult
    static func enable(urls: ClaudeDesktopURLs, baseURL: String, apiKey: String, roleModels: [ClaudeRole: String]) -> Bool {
        do {
            // 1) Claude/claude_desktop_config.json → deploymentMode 3p
            try setDeploymentMode(urls.claudeAppConfig, mode: "3p")
            // 2) Claude-3p/claude_desktop_config.json → deploymentMode 3p（保留其余用户配置）
            try setDeploymentMode(urls.claude3pConfig, mode: "3p")
            // 3) configLibrary/<profileID>.json → gateway profile（v2.1 含 inferenceModels，指向本地路由代理）
            try AtomicWriter.writeJSON(profileJSON(baseURL: baseURL, apiKey: apiKey, roleModels: roleModels), to: urls.profileURL)
            // 4) configLibrary/_meta.json → 激活本 profile
            try AtomicWriter.writeJSON(metaJSON(appliedID: profileID,
                                                entries: [["id": profileID, "name": profileName]]),
                                       to: urls.metaURL)
            return true
        } catch {
            return false
        }
    }

    /// 关闭：恢复官方（deploymentMode 1p），删除 profile 与激活记录。
    @discardableResult
    static func disable(urls: ClaudeDesktopURLs) -> Bool {
        do {
            // 删除 profile 与 meta（恢复官方：deploymentMode 改回 1p，删除 profile 与 appliedId 记录）
            try? FileManager.default.removeItem(at: urls.profileURL)
            try? FileManager.default.removeItem(at: urls.metaURL)
            try setDeploymentMode(urls.claudeAppConfig, mode: "1p")
            try setDeploymentMode(urls.claude3pConfig, mode: "1p")
            return true
        } catch {
            return false
        }
    }
}
