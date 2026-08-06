//
//  LiveConfigTests.swift
//  OmniBarTests
//
//  v2.0「AI 接入」测试：AtomicWriter / BackupManager / ClaudeCodeLiveConfig /
//  CodexLiveConfig / ProviderLinkManager 的文件读写、合并剥离与回滚逻辑。
//

import XCTest
@testable import OmniBar

// MARK: - AtomicWriter

final class AtomicWriterTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniBarAtomic-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testWriteCreatesFileWithContent() throws {
        let url = dir.appendingPathComponent("a.json")
        try AtomicWriter.write(Data("hello".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello")
    }

    func testWriteCreatesParentDirectories() throws {
        let url = dir.appendingPathComponent("nested/deep/b.json")
        try AtomicWriter.write(Data("x".utf8), to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testWriteOverwritesExisting() throws {
        let url = dir.appendingPathComponent("c.txt")
        try AtomicWriter.writeText("v1", to: url)
        try AtomicWriter.writeText("v2", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "v2")
    }

    func testWriteJSONRoundTrip() throws {
        let url = dir.appendingPathComponent("d.json")
        try AtomicWriter.writeJSON(["k": 1], to: url)
        let obj = try AtomicWriter.readJSON(url)
        XCTAssertEqual(obj["k"] as? Int, 1)
    }

    func testNoTempFileLeakAfterWrite() throws {
        let url = dir.appendingPathComponent("e.json")
        try AtomicWriter.writeText("v", to: url)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(leftovers.allSatisfy { !$0.contains("omnitmp") })
    }
}

// MARK: - BackupManager

final class BackupManagerTests: XCTestCase {

    private var dir: URL!
    private var backups: BackupManager!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniBarBackup-\(UUID().uuidString)", isDirectory: true)
        backups = BackupManager(directory: dir.appendingPathComponent("backups"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makeLiveFile(_ name: String, content: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testEnsureBackupCopiesOriginal() {
        let live = makeLiveFile("settings.json", content: "original")
        let backup = backups.ensureBackup(of: live, marker: "m")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try? String(contentsOf: backup, encoding: .utf8), "original")
    }

    func testEnsureBackupIsIdempotent() {
        let live = makeLiveFile("settings.json", content: "original")
        let first = backups.ensureBackup(of: live, marker: "m")
        // live 被修改后再次 ensureBackup，不应覆盖已有备份
        try? "changed".write(to: live, atomically: true, encoding: .utf8)
        let second = backups.ensureBackup(of: live, marker: "m")
        XCTAssertEqual(first.path, second.path)
        XCTAssertEqual(try? String(contentsOf: second, encoding: .utf8), "original")
    }

    func testEnsureBackupSkipsMissingLive() {
        let live = dir.appendingPathComponent("missing.json")
        let backup = backups.ensureBackup(of: live, marker: "m")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testRestoreOverwritesLiveFromBackup() {
        let live = makeLiveFile("settings.json", content: "original")
        _ = backups.ensureBackup(of: live, marker: "m")
        try? "managed".write(to: live, atomically: true, encoding: .utf8)
        let ok = backups.restore(liveURL: live, marker: "m")
        XCTAssertTrue(ok)
        XCTAssertEqual(try? String(contentsOf: live, encoding: .utf8), "original")
    }

    func testRestoreDeletesLiveWhenNoBackup() {
        // 接入前 live 不存在 → 没有备份 → 还原 = 删除当前文件
        let live = dir.appendingPathComponent("new.json")
        try? "managed".write(to: live, atomically: true, encoding: .utf8)
        let ok = backups.restore(liveURL: live, marker: "m")
        XCTAssertTrue(ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: live.path))
    }

    func testCleanupRemovesBackup() {
        let live = makeLiveFile("settings.json", content: "original")
        let backup = backups.ensureBackup(of: live, marker: "m")
        backups.cleanup(liveURL: live, marker: "m")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }
}

// MARK: - ClaudeCodeLiveConfig

final class ClaudeCodeLiveConfigTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniBarClaude-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func settingsURL() -> URL {
        dir.appendingPathComponent(".claude/settings.json")
    }

    private func readSettings(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: managedEnv

    func testManagedEnvContainsExpectedKeys() {
        let env = ClaudeCodeLiveConfig.managedEnv(baseURL: "http://localhost:20128/v1",
                                                  apiKey: "key",
                                                  model: "PY/model")
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"], "http://localhost:20128/v1")
        XCTAssertEqual(env["ANTHROPIC_AUTH_TOKEN"], "key")
        XCTAssertEqual(env["ANTHROPIC_MODEL"], "PY/model")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_SONNET_MODEL"], "PY/model")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_OPUS_MODEL"], "PY/model")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_HAIKU_MODEL"], "PY/model")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_FABLE_MODEL"], "PY/model")
        XCTAssertEqual(env["CLAUDE_CODE_SUBAGENT_MODEL"], "PY/model")
        XCTAssertEqual(env.count, ClaudeCodeLiveConfig.managedEnvKeys.count)
    }

    // MARK: merging

    func testMergingPreservesExistingEnvAndHooks() {
        let existing: [String: Any] = [
            "env": ["USER_VAR": "1"],
            "hooks": ["PreToolUse": []],
            "statusLine": "{}",
        ]
        let merged = ClaudeCodeLiveConfig.merging(
            env: ClaudeCodeLiveConfig.managedEnv(baseURL: "b", apiKey: "k", model: "m"),
            into: existing)
        XCTAssertEqual(merged["statusLine"] as? String, "{}")
        let hooks = merged["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks?["PreToolUse"])
        let env = merged["env"] as? [String: String]
        XCTAssertEqual(env?["USER_VAR"], "1")
        XCTAssertEqual(env?["ANTHROPIC_BASE_URL"], "b")
    }

    func testMergingCreatesEnvWhenMissing() {
        let merged = ClaudeCodeLiveConfig.merging(
            env: ["ANTHROPIC_BASE_URL": "b"],
            into: ["hooks": [:]])
        let env = merged["env"] as? [String: String]
        XCTAssertEqual(env?["ANTHROPIC_BASE_URL"], "b")
        XCTAssertNotNil(merged["hooks"])
    }

    // MARK: stripping

    func testStrippingRemovesOnlyManagedKeys() {
        let settings: [String: Any] = [
            "env": [
                "ANTHROPIC_BASE_URL": "b",
                "ANTHROPIC_AUTH_TOKEN": "k",
                "USER_VAR": "1",
            ],
            "hooks": [:]
        ]
        let stripped = ClaudeCodeLiveConfig.strippingManagedEnv(from: settings)
        let env = stripped["env"] as? [String: String]
        XCTAssertEqual(env?["USER_VAR"], "1")
        XCTAssertNil(env?["ANTHROPIC_BASE_URL"])
        XCTAssertNil(env?["ANTHROPIC_AUTH_TOKEN"])
        XCTAssertNotNil(stripped["hooks"])
    }

    func testStrippingRemovesEnvWhenEmpty() {
        let settings: [String: Any] = ["env": ["ANTHROPIC_BASE_URL": "b"]]
        let stripped = ClaudeCodeLiveConfig.strippingManagedEnv(from: settings)
        XCTAssertNil(stripped["env"])
    }

    // MARK: enable / disable

    func testEnableWritesMergedFile() throws {
        let url = settingsURL()
        let original: [String: Any] = ["env": ["USER_VAR": "1"], "hooks": [:]]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: original).write(to: url)

        _ = try ClaudeCodeLiveConfig.enable(settingsURL: url,
                                            baseURL: "http://localhost:20128/v1",
                                            apiKey: "key",
                                            model: "PY/model")
        let saved = readSettings(url)
        let env = saved?["env"] as? [String: String]
        XCTAssertEqual(env?["ANTHROPIC_BASE_URL"], "http://localhost:20128/v1")
        XCTAssertEqual(env?["USER_VAR"], "1")
        XCTAssertNotNil(saved?["hooks"])
    }

    func testEnableOnMissingFileCreatesNew() throws {
        let url = settingsURL()
        _ = try ClaudeCodeLiveConfig.enable(settingsURL: url,
                                            baseURL: "b",
                                            apiKey: "k",
                                            model: "m")
        let env = readSettings(url)?["env"] as? [String: String]
        XCTAssertEqual(env?["ANTHROPIC_MODEL"], "m")
    }

    func testDisableStripsManagedKeys() throws {
        let url = settingsURL()
        _ = try ClaudeCodeLiveConfig.enable(settingsURL: url, baseURL: "b", apiKey: "k", model: "m")
        try ClaudeCodeLiveConfig.disable(settingsURL: url)
        let env = readSettings(url)?["env"] as? [String: String]
        XCTAssertNil(env?["ANTHROPIC_BASE_URL"])
        XCTAssertNil(env?["ANTHROPIC_AUTH_TOKEN"])
    }

    func testDisableOnMissingFileIsNoop() throws {
        XCTAssertNoThrow(try ClaudeCodeLiveConfig.disable(settingsURL: settingsURL()))
    }

    func testIsManagedDetectsManagedEnvKeys() throws {
        let url = settingsURL()
        XCTAssertFalse(ClaudeCodeLiveConfig.isManaged(settingsURL: url))
        _ = try ClaudeCodeLiveConfig.enable(settingsURL: url, baseURL: "b", apiKey: "k", model: "m")
        XCTAssertTrue(ClaudeCodeLiveConfig.isManaged(settingsURL: url))
        try ClaudeCodeLiveConfig.disable(settingsURL: url)
        XCTAssertFalse(ClaudeCodeLiveConfig.isManaged(settingsURL: url))
    }
}

// MARK: - CodexLiveConfig

final class CodexLiveConfigTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniBarCodex-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func homeURL() -> URL {
        dir.appendingPathComponent(".codex", isDirectory: true)
    }

    private func configURL() -> URL {
        homeURL().appendingPathComponent("config.toml")
    }

    private func authURL() -> URL {
        homeURL().appendingPathComponent("auth.json")
    }

    // MARK: render / sentinel

    func testRenderManagedBlockIsSentinelWrapped() {
        let block = CodexLiveConfig.renderManagedBlock(baseURL: "http://localhost:20128/v1", model: "auto/best-fast")
        XCTAssertTrue(block.hasPrefix(CodexLiveConfig.beginMarker))
        XCTAssertTrue(block.hasSuffix(CodexLiveConfig.endMarker))
        XCTAssertTrue(block.contains("model_provider = \"custom\""))
        XCTAssertTrue(block.contains("wire_api = \"responses\""))
        XCTAssertTrue(block.contains("base_url = \"http://localhost:20128/v1\""))
        XCTAssertTrue(block.contains("model_catalog_json = \"omnibar-model-catalog.json\""))
    }

    func testApplyingManagedPrependsBlockAndKeepsUserContent() {
        let user = """
        approval_policy = "on-request"

        [mcp_servers.filesystem]
        command = "npx"
        """
        let out = CodexLiveConfig.applyingManaged(to: user, baseURL: "b", model: "m")
        XCTAssertTrue(out.hasPrefix(CodexLiveConfig.beginMarker))
        XCTAssertTrue(out.contains("[mcp_servers.filesystem]"))
        XCTAssertTrue(out.contains("approval_policy = \"on-request\""))
    }

    func testApplyingManagedIsIdempotent() {
        let user = "model = \"user-kept\"\n\n[mcp_servers.x]\ncommand = \"npx\"\n"
        let once = CodexLiveConfig.applyingManaged(to: user, baseURL: "b", model: "m")
        let twice = CodexLiveConfig.applyingManaged(to: once, baseURL: "b", model: "m")
        XCTAssertEqual(once, twice)
    }

    // MARK: stripping

    func testStrippingRemovesRootKeysOutsideBlock() {
        let text = """
        model_provider = "custom"
        model = "stray"
        approval_policy = "on-request"
        """
        let out = CodexLiveConfig.strippingManaged(from: text)
        XCTAssertFalse(out.contains("model_provider"))
        XCTAssertFalse(out.contains("model = \"stray\""))
        XCTAssertTrue(out.contains("approval_policy"))
    }

    func testStrippingRemovesManagedProviderTable() {
        let text = """
        [model_providers.custom]
        name = "omniroute"
        base_url = "http://localhost:20128/v1"

        [model_providers.other]
        name = "other"
        """
        let out = CodexLiveConfig.strippingManaged(from: text)
        XCTAssertFalse(out.contains("model_providers.custom"))
        XCTAssertTrue(out.contains("model_providers.other"))
    }

    func testStrippingPreservesOtherToolBlockButCleansManagedRootKeys() {
        // 其它工具的哨兵注释保留；但根级托管键（如 model）会被清理——
        // 否则与 OmniBar 的托管块形成 TOML 重复键，导致 Codex 解析失败。
        let text = """
        # >>> other-tool-managed >>>
        model = "x"
        # <<< other-tool-managed <<<
        """
        let out = CodexLiveConfig.strippingManaged(from: text)
        XCTAssertTrue(out.contains("other-tool-managed"))
        XCTAssertFalse(out.contains("model = \"x\""))
    }

    func testStrippingRecognizesProviderTableWithInlineComment() {
        let text = """
        [model_providers.custom] # omnibar-managed
        name = "omniroute"
        base_url = "http://localhost:20128/v1"
        """
        let out = CodexLiveConfig.strippingManaged(from: text)
        XCTAssertFalse(out.contains("model_providers.custom"), "带行尾注释的托管表也应被剥离")
    }

    func testIsManagedDetectsSentinel() {
        try? FileManager.default.createDirectory(at: homeURL(), withIntermediateDirectories: true)
        try? "model = \"x\"".write(to: configURL(), atomically: true, encoding: .utf8)
        XCTAssertFalse(CodexLiveConfig.isManaged(homeURL: homeURL()))
        _ = CodexLiveConfig.enable(homeURL: homeURL(), baseURL: "b", model: "m", apiKey: "k")
        XCTAssertTrue(CodexLiveConfig.isManaged(homeURL: homeURL()))
    }

    // MARK: file-level

    func testEnableWritesAuthAndConfig() {
        let (authOK, configOK) = CodexLiveConfig.enable(homeURL: homeURL(),
                                                        baseURL: "http://localhost:20128/v1",
                                                        model: "auto/best-fast",
                                                        apiKey: "omniroute-key")
        XCTAssertTrue(authOK)
        XCTAssertTrue(configOK)
        let auth = (try? JSONSerialization.jsonObject(with: Data(contentsOf: authURL()))) as? [String: String]
        XCTAssertEqual(auth?["OPENAI_API_KEY"], "omniroute-key")
        let config = try? String(contentsOf: configURL(), encoding: .utf8)
        XCTAssertTrue(config?.contains(CodexLiveConfig.beginMarker) ?? false)
    }

    func testDisableRemovesBlockKeepsUserConfig() {
        let user = "approval_policy = \"on-request\"\n\n[mcp_servers.x]\ncommand = \"npx\"\n"
        try? FileManager.default.createDirectory(at: homeURL(), withIntermediateDirectories: true)
        try? user.write(to: configURL(), atomically: true, encoding: .utf8)
        _ = CodexLiveConfig.enable(homeURL: homeURL(), baseURL: "b", model: "m", apiKey: "k")
        let ok = CodexLiveConfig.disable(homeURL: homeURL())
        XCTAssertTrue(ok)
        let out = (try? String(contentsOf: configURL(), encoding: .utf8)) ?? ""
        XCTAssertFalse(out.contains(CodexLiveConfig.beginMarker))
        XCTAssertFalse(out.contains("model_provider"))
        XCTAssertTrue(out.contains("approval_policy"))
        XCTAssertTrue(out.contains("[mcp_servers.x]"))
    }

    func testDisableDoesNotTouchAuth() {
        try? FileManager.default.createDirectory(at: homeURL(), withIntermediateDirectories: true)
        try? "{\"OPENAI_API_KEY\":\"pre-existing\"}".write(to: authURL(), atomically: true, encoding: .utf8)
        try? "model = \"pre\"".write(to: configURL(), atomically: true, encoding: .utf8)
        _ = CodexLiveConfig.disable(homeURL: homeURL())
        let auth = (try? String(contentsOf: authURL(), encoding: .utf8)) ?? ""
        XCTAssertTrue(auth.contains("pre-existing"), "disable 不应改写 auth.json")
    }
}

// MARK: - ClaudeDesktopLiveConfig（M4，方案 A）

final class ClaudeDesktopLiveConfigTests: XCTestCase {

    private var dir: URL!
    private var urls: ClaudeDesktopURLs!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniBarDesktop-\(UUID().uuidString)", isDirectory: true)
        urls = ClaudeDesktopURLs(
            claudeAppConfig: dir.appendingPathComponent("Claude/claude_desktop_config.json"),
            claude3pConfig: dir.appendingPathComponent("Claude-3p/claude_desktop_config.json"),
            libraryDir: dir.appendingPathComponent("Claude-3p/configLibrary", isDirectory: true)
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testProfileJSONWritesInferenceModelsForAllRoles() {
        let roles: [ClaudeRole: String] = [
            .sonnet: "auto/best-coding",
            .opus: "auto/best-reasoning",
            .haiku: "auto/best-fast",
            .fable: "auto/best-chat",
        ]
        let profile = ClaudeDesktopLiveConfig.profileJSON(baseURL: "http://127.0.0.1:16931", apiKey: "k", roleModels: roles)
        XCTAssertEqual(profile["inferenceProvider"] as? String, "gateway")
        XCTAssertEqual(profile["inferenceGatewayBaseUrl"] as? String, "http://127.0.0.1:16931")
        XCTAssertEqual(profile["inferenceGatewayApiKey"] as? String, "k")
        XCTAssertEqual(profile["inferenceGatewayAuthScheme"] as? String, "bearer")
        let models = profile["inferenceModels"] as? [[String: Any]]
        XCTAssertEqual(models?.count, 4, "四个角色都要写 inferenceModels")
        let names = models?.compactMap { $0["name"] as? String } ?? []
        XCTAssertEqual(Set(names), Set(ClaudeRole.allCases.map(\.roleModelID)))
    }

    func testProfileJSONFallsBackToRoleTitleWhenModelEmpty() {
        let profile = ClaudeDesktopLiveConfig.profileJSON(baseURL: "b", apiKey: "k", roleModels: [:])
        let models = profile["inferenceModels"] as? [[String: Any]]
        let sonnet = models?.first { ($0["name"] as? String) == ClaudeRole.sonnet.roleModelID }
        XCTAssertEqual(sonnet?["labelOverride"] as? String, "Sonnet", "角色模型为空时 labelOverride 用角色名")
    }

    func testEnableWritesAllDeploymentFiles() {
        let ok = ClaudeDesktopLiveConfig.enable(urls: urls, baseURL: "http://127.0.0.1:16931", apiKey: "k",
                                                roleModels: [.sonnet: "auto/best-coding"])
        XCTAssertTrue(ok)
        XCTAssertTrue(ClaudeDesktopLiveConfig.isManaged(urls))
        // Claude/claude_desktop_config.json → deploymentMode 3p
        let appConfig = ClaudeDesktopLiveConfig.readConfig(urls.claudeAppConfig)
        XCTAssertEqual(appConfig?["deploymentMode"] as? String, "3p")
        // Claude-3p config → deploymentMode 3p
        let threeP = ClaudeDesktopLiveConfig.readConfig(urls.claude3pConfig)
        XCTAssertEqual(threeP?["deploymentMode"] as? String, "3p")
        // profile 文件含 gateway 配置与 inferenceModels
        let profile = ClaudeDesktopLiveConfig.readConfig(urls.profileURL)
        XCTAssertEqual(profile?["inferenceProvider"] as? String, "gateway")
        XCTAssertNotNil(profile?["inferenceModels"])
        // _meta 激活
        let meta = ClaudeDesktopLiveConfig.readConfig(urls.metaURL)
        XCTAssertEqual(meta?["appliedId"] as? String, ClaudeDesktopLiveConfig.profileID)
    }

    func testEnablePreservesUserClaude3pConfig() {
        try? FileManager.default.createDirectory(at: urls.claude3pConfig.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? "{\"deploymentMode\":\"1p\",\"preferences\":{\"menuBarEnabled\":false}}".write(to: urls.claude3pConfig,
                                                                                            atomically: true,
                                                                                            encoding: .utf8)
        _ = ClaudeDesktopLiveConfig.enable(urls: urls, baseURL: "b", apiKey: "k", roleModels: [:])
        let config = ClaudeDesktopLiveConfig.readConfig(urls.claude3pConfig)
        XCTAssertEqual(config?["deploymentMode"] as? String, "3p")
        XCTAssertNotNil(config?["preferences"], "启用时应保留用户其余配置")
    }

    func testDisableRestoresOfficialAndCleansProfile() {
        _ = ClaudeDesktopLiveConfig.enable(urls: urls, baseURL: "b", apiKey: "k", roleModels: [:])
        XCTAssertTrue(ClaudeDesktopLiveConfig.isManaged(urls))
        let ok = ClaudeDesktopLiveConfig.disable(urls: urls)
        XCTAssertTrue(ok)
        XCTAssertFalse(ClaudeDesktopLiveConfig.isManaged(urls), "关闭后不应再是接管状态")
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.metaURL.path), "_meta 应被删除")
        XCTAssertEqual(ClaudeDesktopLiveConfig.readConfig(urls.claudeAppConfig)?["deploymentMode"] as? String, "1p")
        XCTAssertEqual(ClaudeDesktopLiveConfig.readConfig(urls.claude3pConfig)?["deploymentMode"] as? String, "1p")
    }
}

// MARK: - ProviderLinkManager

@MainActor
final class ProviderLinkManagerTests: XCTestCase {

    private struct TempLocator: LinkLocator {
        let claudeSettingsURL: URL
        let codexHomeURL: URL
        let claudeDesktop: ClaudeDesktopURLs
    }

    private var tempDir: URL!
    private var backupDir: URL!
    private var locator: TempLocator!
    private var settings: AppSettings!
    private var savedClaudeModel: String!
    private var savedCodexModel: String!
    private var savedClaudeLink: Bool!
    private var savedCodexLink: Bool!
    private var savedCompress: Bool!

    override func setUp() {
        super.setUp()
        settings = AppSettings.shared
        savedClaudeModel = settings.linkClaudeModel
        savedCodexModel = settings.linkCodexModel
        savedClaudeLink = settings.linkClaudeCode
        savedCodexLink = settings.linkCodex
        savedCompress = settings.compressTokenInMenuBar
        settings.linkClaudeModel = ""
        settings.linkCodexModel = ""
        settings.linkClaudeCode = false
        settings.linkCodex = false
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniBarLink-\(UUID().uuidString)", isDirectory: true)
        backupDir = tempDir.appendingPathComponent("backups", isDirectory: true)
        locator = TempLocator(
            claudeSettingsURL: tempDir.appendingPathComponent(".claude/settings.json"),
            codexHomeURL: tempDir.appendingPathComponent(".codex"),
            claudeDesktop: ClaudeDesktopURLs(
                claudeAppConfig: tempDir.appendingPathComponent("Claude/claude_desktop_config.json"),
                claude3pConfig: tempDir.appendingPathComponent("Claude-3p/claude_desktop_config.json"),
                libraryDir: tempDir.appendingPathComponent("Claude-3p/configLibrary", isDirectory: true)
            )
        )
    }

    override func tearDown() {
        settings.linkClaudeModel = savedClaudeModel
        settings.linkCodexModel = savedCodexModel
        settings.linkClaudeCode = savedClaudeLink
        settings.linkCodex = savedCodexLink
        settings.compressTokenInMenuBar = savedCompress
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeManager() -> ProviderLinkManager {
        ProviderLinkManager(settings: settings,
                            locator: locator,
                            backupDir: backupDir,
                            modelsProvider: { [] },
                            templateProvider: { ModelCatalogBuilder.staticTemplate })
    }

    private func makeModel(_ id: String, context: Int? = nil) -> GatewayModel {
        GatewayModel(id: id, object: "model", ownedBy: nil,
                     contextLength: context,
                     capabilities: GatewayModel.Capabilities(toolCalling: true, reasoning: true, vision: false, thinking: true))
    }

    // MARK: Claude Code

    func testEnableClaudeCodeWritesSettingsWithGatewayModel() async {
        let manager = makeManager()
        let models = [makeModel("PY/deepseek-x"), makeModel("auto/best-fast")]
        let result = await manager.enable(.claudeCode, gatewayModels: models)
        XCTAssertTrue(result.success, result.message ?? "")
        guard let data = try? Data(contentsOf: locator.claudeSettingsURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let env = obj["env"] as? [String: String] else {
            return XCTFail("settings.json 未写入")
        }
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"], "http://localhost:\(settings.omniroutePort)/v1")
        XCTAssertEqual(env["ANTHROPIC_AUTH_TOKEN"], settings.omnirouteAPIKey)
        // 未存模型选择时取网关首个模型
        XCTAssertEqual(env["ANTHROPIC_MODEL"], "PY/deepseek-x")
    }

    func testEnableClaudeCodePrefersStoredModel() async {
        settings.linkClaudeModel = "auto/best-fast"
        let manager = makeManager()
        let result = await manager.enable(.claudeCode, gatewayModels: [makeModel("PY/deepseek-x")])
        XCTAssertTrue(result.success)
        let data = (try? Data(contentsOf: locator.claudeSettingsURL)) ?? Data()
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let env = obj?["env"] as? [String: String]
        XCTAssertEqual(env?["ANTHROPIC_MODEL"], "auto/best-fast")
    }

    func testDisableClaudeCodeRestoresOriginalBytes() async {
        let original = "{\"env\":{\"USER_VAR\":\"1\"},\"hooks\":{}}\n"
        try? FileManager.default.createDirectory(at: locator.claudeSettingsURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? original.write(to: locator.claudeSettingsURL, atomically: true, encoding: .utf8)

        let manager = makeManager()
        let enable = await manager.enable(.claudeCode, gatewayModels: [])
        XCTAssertTrue(enable.success)
        let after = (try? String(contentsOf: locator.claudeSettingsURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(after.contains("ANTHROPIC_BASE_URL"))

        let disable = await manager.disable(.claudeCode)
        XCTAssertTrue(disable.success, disable.message ?? "")
        let restored = (try? String(contentsOf: locator.claudeSettingsURL, encoding: .utf8)) ?? ""
        XCTAssertEqual(restored, original)
    }

    func testDisableClaudeCodeDeletesFileThatDidNotExist() async {
        let manager = makeManager()
        _ = await manager.enable(.claudeCode, gatewayModels: [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: locator.claudeSettingsURL.path))
        let disable = await manager.disable(.claudeCode)
        XCTAssertTrue(disable.success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locator.claudeSettingsURL.path))
    }

    // MARK: Codex

    func testEnableCodexWritesAuthConfigAndCatalog() async {
        let manager = makeManager()
        let models = [makeModel("auto/best-fast", context: 128_000)]
        let result = await manager.enable(.codex, gatewayModels: models)
        XCTAssertTrue(result.success, result.message ?? "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: locator.codexConfigURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: locator.codexAuthURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: locator.codexCatalogURL.path))

        let config = (try? String(contentsOf: locator.codexConfigURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(config.contains(CodexLiveConfig.beginMarker))
        XCTAssertTrue(config.contains("base_url = \"http://localhost:\(settings.omniroutePort)/v1\""))

        let catalog = (try? Data(contentsOf: locator.codexCatalogURL)) ?? Data()
        let obj = (try? JSONSerialization.jsonObject(with: catalog)) as? [String: Any]
        let modelsInCatalog = obj?["models"] as? [[String: Any]]
        XCTAssertEqual(modelsInCatalog?.count, 1)
        XCTAssertEqual(modelsInCatalog?.first?["slug"] as? String, "auto/best-fast")
        XCTAssertEqual(modelsInCatalog?.first?["context_window"] as? Int, 128_000)
    }

    func testDisableCodexRestoresOriginals() async {
        try? FileManager.default.createDirectory(at: locator.codexHomeURL, withIntermediateDirectories: true)
        let origConfig = "approval_policy = \"on-request\"\n"
        let origAuth = "{\"OPENAI_API_KEY\":\"my-original-key\"}"
        try? origConfig.write(to: locator.codexConfigURL, atomically: true, encoding: .utf8)
        try? origAuth.write(to: locator.codexAuthURL, atomically: true, encoding: .utf8)

        let manager = makeManager()
        _ = await manager.enable(.codex, gatewayModels: [makeModel("m", context: 100)])
        let disable = await manager.disable(.codex)
        XCTAssertTrue(disable.success, disable.message ?? "")

        let config = (try? String(contentsOf: locator.codexConfigURL, encoding: .utf8)) ?? ""
        XCTAssertEqual(config, origConfig)
        let auth = (try? String(contentsOf: locator.codexAuthURL, encoding: .utf8)) ?? ""
        XCTAssertEqual(auth, origAuth)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locator.codexCatalogURL.path))
    }

    // MARK: 联动刷新

    func testRefreshUsesModelsProviderForCatalog() async {
        // G4 回归：联动刷新路径必须取最新模型列表，而不是退化为空数组
        // （scheduleRefreshIfLinked 只对已开启的开关生效，因此需把 linkCodex 打开）
        settings.linkCodex = true
        var current: [GatewayModel] = []
        let manager = ProviderLinkManager(settings: settings,
                                          locator: locator,
                                          backupDir: backupDir,
                                          modelsProvider: { current },
                                          templateProvider: { ModelCatalogBuilder.staticTemplate })
        _ = await manager.enable(.codex, gatewayModels: [])
        // 模拟网关模型刷新后触发设置变化（改变相关设置项）→ 防抖刷新
        current = [makeModel("PY/refresh-model", context: 64_000)]
        settings.linkCodexModel = "PY/refresh-model" // 触发 objectWillChange 且属于相关快照
        try? await Task.sleep(nanoseconds: 700_000_000) // 等待 400ms 防抖 + 执行

        let catalog = (try? Data(contentsOf: locator.codexCatalogURL)) ?? Data()
        let obj = (try? JSONSerialization.jsonObject(with: catalog)) as? [String: Any]
        let slugs = (obj?["models"] as? [[String: Any]])?.compactMap { $0["slug"] as? String } ?? []
        XCTAssertTrue(slugs.contains("PY/refresh-model"), "刷新后目录应包含最新模型，实际: \(slugs)")
    }

    func testUnrelatedSettingsChangeDoesNotRewrite() async {
        // 快照收窄：修改与 live 配置无关的设置不应触发重写
        settings.linkCodex = true
        let manager = makeManager()
        _ = await manager.enable(.codex, gatewayModels: [makeModel("auto/best-fast")])
        let before = (try? Data(contentsOf: locator.codexConfigURL)) ?? Data()
        // compressTokenInMenuBar 有 didSet 会触发 objectWillChange，但不在相关快照内
        settings.compressTokenInMenuBar.toggle()
        try? await Task.sleep(nanoseconds: 700_000_000)
        let after = (try? Data(contentsOf: locator.codexConfigURL)) ?? Data()
        XCTAssertEqual(before, after, "无关设置变化不应重写 config.toml")
    }

    func testDisableClaudeCodeWithoutTakeoverKeepsUserFile() async {
        // 回归：从未接入过时调用 disable，不得误删用户原有配置文件
        let userFile = "{\"env\":{\"USER_VAR\":\"1\"},\"hooks\":{}}\n"
        try? FileManager.default.createDirectory(at: locator.claudeSettingsURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? userFile.write(to: locator.claudeSettingsURL, atomically: true, encoding: .utf8)
        let manager = makeManager()
        let result = await manager.disable(.claudeCode)
        XCTAssertTrue(result.success)
        let after = (try? String(contentsOf: locator.claudeSettingsURL, encoding: .utf8)) ?? ""
        XCTAssertEqual(after, userFile, "未接管时 disable 不得删除/改写用户文件")
    }

    func testDisableCodexWithoutTakeoverKeepsUserConfig() async {
        let userConfig = "approval_policy = \"on-request\"\n"
        let userAuth = "{\"OPENAI_API_KEY\":\"user-key\"}"
        try? FileManager.default.createDirectory(at: locator.codexHomeURL, withIntermediateDirectories: true)
        try? userConfig.write(to: locator.codexConfigURL, atomically: true, encoding: .utf8)
        try? userAuth.write(to: locator.codexAuthURL, atomically: true, encoding: .utf8)
        let manager = makeManager()
        let result = await manager.disable(.codex)
        XCTAssertTrue(result.success)
        let config = (try? String(contentsOf: locator.codexConfigURL, encoding: .utf8)) ?? ""
        let auth = (try? String(contentsOf: locator.codexAuthURL, encoding: .utf8)) ?? ""
        XCTAssertEqual(config, userConfig, "未接管时 disable 不得删除 config.toml")
        XCTAssertEqual(auth, userAuth, "未接管时 disable 不得删除 auth.json")
    }

    // MARK: 冲突检测（6.6）

    func testClaudeNoTakeoverWhenNoEnv() {
        let manager = makeManager()
        XCTAssertEqual(manager.takeoverStatus(for: .claudeCode), .none)
    }

    func testClaudeTakeoverWhenForeignBaseURL() {
        try? FileManager.default.createDirectory(at: locator.claudeSettingsURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let foreign = "{\"env\":{\"ANTHROPIC_BASE_URL\":\"https://api.tokenrouter.com\"}}\n"
        try? foreign.write(to: locator.claudeSettingsURL, atomically: true, encoding: .utf8)
        let manager = makeManager()
        XCTAssertEqual(manager.takeoverStatus(for: .claudeCode), .other(owner: "其它工具（cc-switch 等）"))
    }

    func testClaudeNotConflictWhenPointsToOwnGateway() {
        try? FileManager.default.createDirectory(at: locator.claudeSettingsURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let own = "{\"env\":{\"ANTHROPIC_BASE_URL\":\"http://localhost:\\(settings.omniroutePort)/v1\"}}\n"
        try? own.write(to: locator.claudeSettingsURL, atomically: true, encoding: .utf8)
        let manager = makeManager()
        XCTAssertEqual(manager.takeoverStatus(for: .claudeCode), .none)
    }

    func testCodexTakeoverWhenCCSwitchSentinel() {
        try? FileManager.default.createDirectory(at: locator.codexHomeURL, withIntermediateDirectories: true)
        let config = "model_catalog_json = \"cc-switch-model-catalog.json\"\n"
        try? config.write(to: locator.codexConfigURL, atomically: true, encoding: .utf8)
        let manager = makeManager()
        XCTAssertEqual(manager.takeoverStatus(for: .codex), .other(owner: "cc-switch / 其它代理"))
    }

    func testCodexNoTakeoverWhenManaged() async {
        let manager = makeManager()
        _ = await manager.enable(.codex, gatewayModels: [makeModel("auto/best-fast")])
        XCTAssertEqual(manager.takeoverStatus(for: .codex), .none)
    }

    func testClaudeExternallyModifiedDetected() async {
        let manager = makeManager()
        settings.linkClaudeCode = true // 模拟开关已开启（真实 toggle 流程会置位）
        _ = await manager.enable(.claudeCode, gatewayModels: [makeModel("auto/best-fast")])
        // 开关开启、文件已写 → 未被外部改写
        XCTAssertFalse(manager.isExternallyModified(.claudeCode))
        // 外部删掉托管键后 → 判定为被改写
        let stripped = "{\"env\":{\"USER_VAR\":\"1\"}}\n"
        try? stripped.write(to: locator.claudeSettingsURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(manager.isExternallyModified(.claudeCode))
        settings.linkClaudeCode = false
    }
}
