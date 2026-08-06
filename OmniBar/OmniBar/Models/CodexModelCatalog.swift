//
//  CodexModelCatalog.swift
//  OmniBar
//
//  v2.0：为 Codex 生成 `omnibar-model-catalog.json` 外部模型目录。
//  模板取自 `codex debug models --bundled`（或运行时 models_cache），按 NativeResponses
//  网关配置剪裁后克隆为网关暴露的每个模型条目。
//

import Foundation

/// 生成 Codex 模型目录（model_catalog_json）的纯逻辑构建器。
/// 输入：模板条目（[String: Any]）+ 网关模型列表；输出：目录 JSON。
enum ModelCatalogBuilder {

    /// 构建完整目录条目数组。
    /// - Parameters:
    ///   - models: 网关 /v1/models 返回的模型列表
    ///   - template: 模板条目（通常为 gpt-5.x 的 bundled 结构）
    /// - Returns: 每个网关模型一个克隆条目；模板缺失时返回空。
    static func buildEntries(models: [GatewayModel], template: [String: Any]) -> [[String: Any]] {
        guard !models.isEmpty else { return [] }
        let native = nativeProfile(stripping: template)
        return models.enumerated().map { index, model in
            var entry = native
            entry["slug"] = model.id
            entry["display_name"] = model.displayName
            entry["description"] = model.displayName
            if let ctx = model.contextLength, ctx > 0 {
                entry["context_window"] = ctx
                entry["max_context_window"] = ctx
            }
            // 后列出的模型优先级更高，方便在 /model 选择器里靠近顶部
            entry["priority"] = (1000 + index)
            // 网关 /v1/responses 暴露能力驱动输入模态；默认 text（多模态网关由模板补齐 image）
            if let caps = model.capabilities {
                if caps.reasoning == true { entry["supports_reasoning_summaries"] = true }
                if caps.vision == true { entry["supports_image_detail_original"] = true }
            }
            return entry
        }
    }

    /// 把模板条目剪裁为 NativeResponses 网关适配的形态：
    /// - 去掉 Codex 专有的自定义工具声明（apply_patch / web_search / model_messages / tools），
    ///   这些在原生 /responses 网关（如 omniroute 背后的 DeepSeek 系）上会被拒绝；
    /// - 强制 shell_type = "shell_command"（没有 apply_patch 时靠 shell 工具完成文件修改）。
    static func nativeProfile(stripping template: [String: Any]) -> [String: Any] {
        var entry = template
        for key in ["apply_patch_tool_type", "web_search_tool_type", "model_messages", "tools"] {
            entry.removeValue(forKey: key)
        }
        entry["shell_type"] = "shell_command"
        entry["base_instructions"] = entry["base_instructions"] ?? Self.neutralBaseInstructions
        return entry
    }

    /// 把目录条目数组序列化为 model_catalog_json 的 JSON 数据。
    static func catalogJSON(entries: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["models": entries], options: [.prettyPrinted, .sortedKeys])
    }

    /// 便捷入口：模型列表 + 模板 → 目录 JSON。
    static func catalogJSON(models: [GatewayModel], template: [String: Any]) throws -> Data {
        try catalogJSON(entries: buildEntries(models: models, template: template))
    }

    // MARK: - 模板获取

    /// 从 Codex CLI 取 bundled 模型模板；失败时返回 nil（调用方回退到静态模板）。
    static func templateEntryFromCodexCLI(timeout: TimeInterval = 8) -> [String: Any]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", "codex debug models --bundled"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            // 限时等待，避免 CLI 挂起阻塞 UI 操作
            let data = readAvailableData(from: pipe, timeout: timeout)
            guard !data.isEmpty else { return nil }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = obj["models"] as? [[String: Any]] else { return nil }
            return pickTemplate(from: models)
        } catch {
            return nil
        }
    }

    /// 从候选模板中挑一个结构最合适的（优先主代号模型）。
    static func pickTemplate(from entries: [[String: Any]]) -> [String: Any]? {
        let preferred = ["gpt-5.5", "gpt-5", "gpt-5.6-sol", "gpt-5.2"]
        for slug in preferred {
            if let entry = entries.first(where: { ($0["slug"] as? String) == slug }) {
                return entry
            }
        }
        return entries.last
    }

    /// 从 ~/.codex/models_cache.json 读取模板（Codex 连接过一次后写入本地）。
    static func templateEntryFromModelsCache() -> [String: Any]? {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return nil }
        return pickTemplate(from: models)
    }

    /// 统一的运行时模板解析顺序：CLI → models_cache → 内置静态模板。
    static func resolveTemplate(fallback: [String: Any] = Self.staticTemplate) -> [String: Any] {
        templateEntryFromCodexCLI()
            ?? templateEntryFromModelsCache()
            ?? fallback
    }

    // MARK: - 静态模板兜底

    /// 内置兜底模板（结构对齐 codex debug models --bundled 的 gpt-5.x 条目）。
    /// 仅在机器上没有 codex CLI 且没有 models_cache 时使用；字段为 NativeResponses 所需的子集。
    static let staticTemplate: [String: Any] = [
        "slug": "gpt-5.5",
        "display_name": "GPT-5.5",
        "description": "GPT-5.5",
        "context_window": 800_000,
        "max_context_window": 800_000,
        "effective_context_window_percent": 95,
        "priority": 1000,
        "additional_speed_tiers": [],
        "service_tiers": [],
        "availability_nux": NSNull(),
        "upgrade": NSNull(),
        "visibility": "list",
        "supported_in_api": true,
        "support_verbosity": true,
        "supports_parallel_tool_calls": true,
        "supports_reasoning_summaries": true,
        "supports_image_detail_original": true,
        "supports_search_tool": true,
        "input_modalities": ["text", "image"],
        "shell_type": "shell_command",
        "default_reasoning_level": "medium",
        "default_reasoning_summary": "none",
        "default_verbosity": "low",
        "supported_reasoning_levels": [
            ["effort": "low", "description": "Fast responses with lighter reasoning"],
            ["effort": "medium", "description": "Balanced speed and thoroughness"],
            ["effort": "high", "description": "Deep reasoning on complex tasks"],
        ],
        "truncation_policy": [
            "limit": 10_000,
            "mode": "tokens",
        ],
        "base_instructions": Self.neutralBaseInstructions,
    ]

    /// 兜底模板的中性系统提示词（模板缺失时不至于让 Codex 丢失人格）。
    static let neutralBaseInstructions = """
    You are Codex, a coding agent. You and the user share one workspace. \
    Read the codebase before assuming, keep edits closely scoped, prefer existing patterns, \
    and verify your work by running relevant checks.
    """

    // MARK: - 工具

    /// 读取进程管道全部数据，带超时（超时杀进程）。
    private static func readAvailableData(from pipe: Pipe, timeout: TimeInterval) -> Data {
        let file = pipe.fileHandleForReading
        let group = DispatchGroup()
        group.enter()
        var data = Data()
        DispatchQueue.global(qos: .userInitiated).async {
            data = file.readDataToEndOfFile()
            group.leave()
        }
        // 超时：管道未关闭前 readDataToEndOfFile 会一直阻塞，需 kill 触发 EOF
        let result = group.wait(timeout: .now() + timeout)
        if result == .timedOut {
            file.readabilityHandler = nil
        }
        return data
    }
}
