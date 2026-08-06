//
//  ClaudeCodeLiveConfig.swift
//  OmniBar
//
//  v2.0：Claude Code 本地配置（~/.claude/settings.json）的接管。
//  采用 merge（保留用户其它 env 与 hooks），只写入 / 移除 OmniBar 托管的 env 键。
//

import Foundation

/// Claude Code live config 读写，纯函数 + 原子写入，可单测。
enum ClaudeCodeLiveConfig {

    /// 默认 live 文件路径。
    static var defaultSettingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    }

    /// OmniBar 托管的 env 键（启用时写入、关闭时移除）。全部由单一网关模型驱动。
    static let managedEnvKeys: [String] = [
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "ANTHROPIC_DEFAULT_FABLE_MODEL",
        "CLAUDE_CODE_SUBAGENT_MODEL",
    ]

    /// 构造要写入的托管 env 字典。
    static func managedEnv(baseURL: String, apiKey: String, model: String) -> [String: String] {
        [
            "ANTHROPIC_BASE_URL": baseURL,
            "ANTHROPIC_AUTH_TOKEN": apiKey,
            "ANTHROPIC_MODEL": model,
            "ANTHROPIC_DEFAULT_SONNET_MODEL": model,
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": model,
            "ANTHROPIC_DEFAULT_OPUS_MODEL": model,
            "ANTHROPIC_DEFAULT_FABLE_MODEL": model,
            "CLAUDE_CODE_SUBAGENT_MODEL": model,
        ]
    }

    /// 把托管 env merge 进现有 settings 字典（保留其它键），返回新的字典。
    static func merging(env: [String: String], into settings: [String: Any]?) -> [String: Any] {
        var result = settings ?? [:]
        var newEnv = (result["env"] as? [String: String]) ?? [:]
        for (k, v) in env { newEnv[k] = v }
        result["env"] = newEnv
        return result
    }

    /// 从 settings 字典中移除全部托管 env 键；若 env 变空则整个移除 env 键。
    static func strippingManagedEnv(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard var env = result["env"] as? [String: String] else { return result }
        for key in managedEnvKeys { env.removeValue(forKey: key) }
        if env.isEmpty {
            result.removeValue(forKey: "env")
        } else {
            result["env"] = env
        }
        return result
    }

    /// 读取现有 settings.json 为字典；文件缺失或损坏返回 nil。
    static func readExisting(from url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// 当前 settings 是否含 OmniBar 托管的 env 键（用于断开时判断是否真被接管）。
    static func isManaged(settingsURL: URL) -> Bool {
        guard let existing = readExisting(from: settingsURL),
              let env = existing["env"] as? [String: String] else { return false }
        return managedEnvKeys.contains { env[$0] != nil }
    }

    /// 启用：把托管 env merge 进现有 settings 并原子写回。
    /// - Returns: 成功写入的文件内容（Data?）；失败抛错。
    static func enable(settingsURL: URL, baseURL: String, apiKey: String, model: String) throws -> Data {
        let existing = readExisting(from: settingsURL)
        let merged = merging(env: managedEnv(baseURL: baseURL, apiKey: apiKey, model: model), into: existing)
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try AtomicWriter.write(data, to: settingsURL)
        return data
    }

    /// 关闭/移除托管：从现有 settings 中剥离托管 env 键并写回。
    static func disable(settingsURL: URL) throws {
        guard let existing = readExisting(from: settingsURL) else { return }
        let stripped = strippingManagedEnv(from: existing)
        let data = try JSONSerialization.data(withJSONObject: stripped, options: [.prettyPrinted, .sortedKeys])
        try AtomicWriter.write(data, to: settingsURL)
    }
}