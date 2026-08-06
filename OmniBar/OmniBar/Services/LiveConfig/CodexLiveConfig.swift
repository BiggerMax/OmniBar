//
//  CodexLiveConfig.swift
//  OmniBar
//
//  v3.0：Codex 本地配置（~/.codex/config.toml + auth.json + 模型目录）的接管。
//  config.toml 用「哨兵标记块」管理：只增删 OmniBar 的块与托管键，保留用户其余配置
//  （mcp_servers / projects / hooks 等）。
//

import Foundation

/// Codex live config 的读写。纯函数 + 原子写入，可单测。
enum CodexLiveConfig {

    /// 默认 home 目录（~/.codex）。
    static var defaultHomeURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex", isDirectory: true)
    }

    /// OmniBar 生成的模型目录文件名（避免与 cc-switch 的 cc-switch-model-catalog.json 冲突）。
    static let catalogFileName = "omnibar-model-catalog.json"

    /// 保留的 provider 表（覆盖其它工具对它的写入，保证 base_url 指向网关）。
    static let providerTable = "model_providers.custom"

    /// 哨兵行。
    static var beginMarker: String { "# >>> omnibar-managed >>>" }
    static var endMarker: String { "# <<< omnibar-managed <<<" }

    /// 托管顶层键：这些键由 OmniBar 独占，块外出现时也会被清理，避免重复键导致 TOML 解析失败。
    static let managedRootKeys: [String] = [
        "model_provider",
        "model",
        "model_reasoning_effort",
        "disable_response_storage",
        "model_catalog_json",
    ]

    /// 托管 provider 表的键（完整表体由 renderManagedBlock 生成）。
    static let managedProviderKeys: [String] = [
        "name", "base_url", "wire_api", "requires_openai_auth",
    ]

    // MARK: - 渲染

    /// 生成完整的托管块文本（含哨兵注释）。
    static func renderManagedBlock(baseURL: String, model: String, modelCatalogFileName: String = catalogFileName) -> String {
        var lines: [String] = []
        lines.append(beginMarker)
        lines.append("model_provider = \"custom\"")
        lines.append("model = \"\(model)\"")
        lines.append("model_reasoning_effort = \"high\"")
        lines.append("disable_response_storage = true")
        lines.append("model_catalog_json = \"\(modelCatalogFileName)\"")
        lines.append("")
        lines.append("[model_providers.custom]")
        lines.append("name = \"omniroute\"")
        lines.append("wire_api = \"responses\"")
        lines.append("requires_openai_auth = true")
        lines.append("base_url = \"\(baseURL)\"")
        lines.append(endMarker)
        return lines.joined(separator: "\n")
    }

    /// 生成 auth.json 内容。
    static func renderAuthJSON(apiKey: String) -> Data {
        let obj: [String: Any] = ["OPENAI_API_KEY": apiKey]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // MARK: - 行级 TOML 编辑

    /// 判断一行是否是表格头（如 `[model_providers.custom]`）。
    private static func isTableHeader(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("[")
    }

    private static func tableName(of line: String) -> String {
        var name = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // 剥离行尾注释，如 `[model_providers.custom] # note`
        if let hash = name.firstIndex(of: "#") {
            name = String(name[..<hash]).trimmingCharacters(in: .whitespaces)
        }
        // TOML 表头形如 `[model_providers.custom]`，去括号后与 providerTable 常量可比
        if name.hasPrefix("["), name.hasSuffix("]") {
            name.removeFirst()
            name.removeLast()
        }
        return name
    }

    /// 从既有内容中剥离：OmniBar 托管块、块外的托管顶层键、以及保留 provider 表。
    /// 其余内容原样保留（含其它工具的哨兵块 / 其它 provider 表）。
    static func strippingManaged(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var inManagedBlock = false
        var currentSection = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 托管块边界
            if trimmed.hasPrefix(beginMarker) { inManagedBlock = true; continue }
            if trimmed.hasPrefix(endMarker) { inManagedBlock = false; continue }
            if inManagedBlock { continue }

            // 表格头 → 更新当前 section；保留 provider 表头直接丢弃（连同表体）
            if isTableHeader(line) {
                let name = tableName(of: line)
                currentSection = name
                if name == providerTable { continue }
                out.append(line)
                continue
            }

            // 托管 provider 表体
            if currentSection == providerTable { continue }

            // 顶层托管键（注释或带前导空白的也识别）
            if currentSection.isEmpty {
                let trimmedLower = line.trimmingCharacters(in: .whitespaces)
                if !trimmedLower.isEmpty,
                   !trimmedLower.hasPrefix("#"),
                   let key = trimmedLower.components(separatedBy: "=").first?
                       .trimmingCharacters(in: .whitespaces),
                   managedRootKeys.contains(key) {
                    continue
                }
            }

            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    /// 启用：托管块插到文件顶部（保证顶层键在任意表格头之前），返回新文本。
    /// 用户内容先裁剪首尾空白再拼接固定分隔，保证重复应用（幂等）结果一致。
    static func applyingManaged(to text: String, baseURL: String, model: String) -> String {
        let stripped = strippingManaged(from: text)
        let block = renderManagedBlock(baseURL: baseURL, model: model)
        let rest = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = block
        if !rest.isEmpty {
            result += "\n\n" + rest
        }
        // 末尾补一个换行，保证 TOML 结束干净
        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }

    /// 关闭：仅剥离托管块与托管键。
    static func disabling(from text: String) -> String {
        strippingManaged(from: text)
    }

    // MARK: - 文件级操作

    static func readConfig(from url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// config.toml 是否含 OmniBar 托管哨兵块（用于断开时判断是否真被接管）。
    static func isManaged(homeURL: URL) -> Bool {
        let configURL = homeURL.appendingPathComponent("config.toml")
        guard let text = readConfig(from: configURL) else { return false }
        return text.contains(beginMarker)
    }

    /// 启用：写 auth.json + config.toml，返回各文件写入是否成功。
    /// - Returns: (authOK, configOK)
    static func enable(homeURL: URL, baseURL: String, model: String, apiKey: String) -> (authOK: Bool, configOK: Bool) {
        let authURL = homeURL.appendingPathComponent("auth.json")
        let configURL = homeURL.appendingPathComponent("config.toml")
        let authOK = (try? AtomicWriter.write(renderAuthJSON(apiKey: apiKey), to: authURL)) != nil
        let existing = readConfig(from: configURL) ?? ""
        let configOK = (try? AtomicWriter.writeText(applyingManaged(to: existing, baseURL: baseURL, model: model), to: configURL)) != nil
        return (authOK, configOK)
    }

    /// 关闭：仅剥离 config.toml 中的托管块与托管键。
    /// auth.json 不在写器层置空 —— 接入前的原内容由 ProviderLinkManager 依据备份回滚，
    /// 避免把用户接入前已有的其它凭证覆盖成空串。
    static func disable(homeURL: URL) -> Bool {
        let configURL = homeURL.appendingPathComponent("config.toml")
        guard let existing = readConfig(from: configURL) else { return false }
        return (try? AtomicWriter.writeText(disabling(from: existing), to: configURL)) != nil
    }
}