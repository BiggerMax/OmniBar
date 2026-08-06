//
//  CodexModelCatalogTests.swift
//  OmniBarTests
//
//  v2.0「AI 接入」测试：GatewayModel 解码 / ModelCatalogBuilder 生成 Codex 模型目录。
//

import XCTest
@testable import OmniBar

// MARK: - GatewayModel

final class GatewayModelTests: XCTestCase {

    func testDecodeFromModelsEndpointFixture() throws {
        let json = """
        {
          "id": "PY/deepseek-v4-flash",
          "object": "model",
          "owned_by": "deepseek",
          "context_length": 1048576,
          "capabilities": { "tool_calling": true, "reasoning": true, "vision": false, "thinking": true }
        }
        """.data(using: .utf8)!
        let model = try JSONDecoder().decode(GatewayModel.self, from: json)
        XCTAssertEqual(model.id, "PY/deepseek-v4-flash")
        XCTAssertEqual(model.object, "model")
        XCTAssertEqual(model.ownedBy, "deepseek")
        XCTAssertEqual(model.contextLength, 1_048_576)
        XCTAssertEqual(model.capabilities?.toolCalling, true)
        XCTAssertEqual(model.capabilities?.reasoning, true)
        XCTAssertEqual(model.capabilities?.vision, false)
    }

    func testDecodeModelsResponse() throws {
        let json = """
        { "object": "list", "data": [ { "id": "auto/best-fast" }, { "id": "PY/other" } ] }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(OmnirouteAPIClient.ModelsResponse.self, from: json)
        XCTAssertEqual(resp.data.count, 2)
        XCTAssertEqual(resp.data.first?.id, "auto/best-fast")
    }

    func testShortIDStripsNamespace() {
        XCTAssertEqual(GatewayModel(id: "auto/best-fast", object: nil, ownedBy: nil, contextLength: nil, capabilities: nil).shortID, "best-fast")
        XCTAssertEqual(GatewayModel(id: "PY/deepseek-x", object: nil, ownedBy: nil, contextLength: nil, capabilities: nil).shortID, "deepseek-x")
        XCTAssertEqual(GatewayModel(id: "no-slash", object: nil, ownedBy: nil, contextLength: nil, capabilities: nil).shortID, "no-slash")
    }

    func testProviderExtraction() {
        let make = { (id: String) -> GatewayModel in
            GatewayModel(id: id, object: nil, ownedBy: nil, contextLength: nil, capabilities: nil)
        }
        XCTAssertEqual(make("auto/best-fast").provider, "auto")
        XCTAssertEqual(make("PY/deepseek-x").provider, "PY")
        XCTAssertEqual(make("moonshotai/kimi-k3-free").provider, "moonshotai")
        XCTAssertEqual(make("no-slash").provider, "其他")
    }
}

// MARK: - ModelCatalogBuilder

final class ModelCatalogBuilderTests: XCTestCase {

    private func makeModel(_ id: String, context: Int? = nil, vision: Bool? = nil, reasoning: Bool? = nil) -> GatewayModel {
        GatewayModel(id: id,
                     object: "model",
                     ownedBy: nil,
                     contextLength: context,
                     capabilities: GatewayModel.Capabilities(toolCalling: true,
                                                             reasoning: reasoning,
                                                             vision: vision,
                                                             thinking: true))
    }

    private func makeTemplate() -> [String: Any] {
        [
            "slug": "gpt-5.5",
            "display_name": "GPT-5.5",
            "context_window": 800_000,
            "input_modalities": ["text", "image"],
            "apply_patch_tool_type": "CustomEdit",
            "web_search_tool_type": "ServerSideWebSearch",
            "model_messages": "prompt",
            "tools": [["type": "function"]],
            "shell_type": "default",
        ]
    }

    func testBuildEntriesCreatesOnePerModel() {
        let models = [makeModel("auto/best-fast"), makeModel("PY/x", context: 10)]
        let entries = ModelCatalogBuilder.buildEntries(models: models, template: makeTemplate())
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0]["slug"] as? String, "auto/best-fast")
        XCTAssertEqual(entries[0]["display_name"] as? String, "best-fast")
        XCTAssertEqual(entries[1]["slug"] as? String, "PY/x")
    }

    func testBuildEntriesStripsCustomTools() {
        let entries = ModelCatalogBuilder.buildEntries(models: [makeModel("m")], template: makeTemplate())
        let entry = entries[0]
        XCTAssertNil(entry["apply_patch_tool_type"])
        XCTAssertNil(entry["web_search_tool_type"])
        XCTAssertNil(entry["model_messages"])
        XCTAssertNil(entry["tools"])
    }

    func testBuildEntriesForcesShellCommand() {
        let entries = ModelCatalogBuilder.buildEntries(models: [makeModel("m")], template: makeTemplate())
        XCTAssertEqual(entries[0]["shell_type"] as? String, "shell_command")
    }

    func testBuildEntriesMapsContextWindow() {
        let entries = ModelCatalogBuilder.buildEntries(models: [makeModel("m", context: 128_000)], template: makeTemplate())
        XCTAssertEqual(entries[0]["context_window"] as? Int, 128_000)
        XCTAssertEqual(entries[0]["max_context_window"] as? Int, 128_000)
    }

    func testBuildEntriesMapsCapabilities() {
        let entries = ModelCatalogBuilder.buildEntries(
            models: [makeModel("m", vision: true, reasoning: true)],
            template: makeTemplate())
        XCTAssertEqual(entries[0]["supports_reasoning_summaries"] as? Bool, true)
        XCTAssertEqual(entries[0]["supports_image_detail_original"] as? Bool, true)
    }

    func testBuildEntriesEmptyModelsReturnsEmpty() {
        XCTAssertTrue(ModelCatalogBuilder.buildEntries(models: [], template: makeTemplate()).isEmpty)
    }

    func testCatalogJSONWrapsModels() throws {
        let data = try ModelCatalogBuilder.catalogJSON(entries: [["slug": "x", "display_name": "x"]])
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let models = obj?["models"] as? [[String: Any]]
        XCTAssertEqual(models?.count, 1)
        XCTAssertEqual(models?.first?["slug"] as? String, "x")
    }

    func testNativeProfileKeepsBaseInstructions() {
        let profile = ModelCatalogBuilder.nativeProfile(stripping: makeTemplate())
        XCTAssertNotNil(profile["base_instructions"])
        XCTAssertNil(profile["tools"])
    }

    func testPickTemplatePrefersPreferredSlugs() {
        let entries: [[String: Any]] = [
            ["slug": "gpt-4o"],
            ["slug": "gpt-5.5"],
            ["slug": "gpt-5"],
        ]
        let picked = ModelCatalogBuilder.pickTemplate(from: entries)
        XCTAssertEqual(picked?["slug"] as? String, "gpt-5.5")
    }

    func testPickTemplateFallsBackToLast() {
        let entries: [[String: Any]] = [["slug": "a"], ["slug": "b"]]
        XCTAssertEqual(ModelCatalogBuilder.pickTemplate(from: entries)?["slug"] as? String, "b")
    }
}
