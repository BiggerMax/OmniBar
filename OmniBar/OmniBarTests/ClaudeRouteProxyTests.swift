//
//  ClaudeRouteProxyTests.swift
//  OmniBarTests
//
//  v2.1：ClaudeRouteProxy 模型重写逻辑与 ClaudeRole 定义测试。
//

import XCTest
@testable import OmniBar

// MARK: - ClaudeRole

final class ClaudeRoleTests: XCTestCase {

    func testRoleModelIDsCoverAllRoles() {
        XCTAssertEqual(Set(ClaudeRole.allCases.map(\.roleModelID)).count, ClaudeRole.allCases.count)
        for role in ClaudeRole.allCases {
            XCTAssertTrue(role.roleModelID.hasPrefix(role.modelPrefix), "角色 ID 必须以自己的前缀开头")
        }
    }

    func testModelPrefixesAreUniqueAndRecognizable() {
        XCTAssertTrue(ClaudeRole.sonnet.modelPrefix == "claude-sonnet")
        XCTAssertTrue(ClaudeRole.opus.modelPrefix == "claude-opus")
        XCTAssertTrue(ClaudeRole.haiku.modelPrefix == "claude-haiku")
        XCTAssertTrue(ClaudeRole.fable.modelPrefix == "claude-fable")
    }
}

// MARK: - ClaudeRouteProxy.rewrittenBody

final class ClaudeRouteProxyRewriteTests: XCTestCase {

    private func makeBody(model: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["model": model, "max_tokens": 1024, "stream": true])
    }

    func testRewriteClaudeSonnetRoleToRealModel() throws {
        let body = makeBody(model: "claude-sonnet-5")
        let out = try XCTUnwrap(ClaudeRouteProxy.rewrittenBody(body, resolver: { _ in "auto/best-fast" }))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: out) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "auto/best-fast")
        XCTAssertEqual(json["max_tokens"] as? Int, 1024, "重写只改 model，保留其余字段")
    }

    func testRewriteKeepsNonRoleModelUntouched() throws {
        let body = makeBody(model: "auto/best-coding")
        let out = ClaudeRouteProxy.rewrittenBody(body, resolver: { _ in "auto/best-fast" })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: out!) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "auto/best-coding")
    }

    func testRewriteAllRoles() throws {
        let cases: [(String, ClaudeRole)] = [
            ("claude-sonnet-5", .sonnet),
            ("claude-opus-4-8", .opus),
            ("claude-haiku-4-5", .haiku),
            ("claude-fable-5", .fable),
        ]
        for (model, role) in cases {
            let body = makeBody(model: model)
            let resolver: (ClaudeRole) -> String = { $0 == role ? "auto/\(role.rawValue)-model" : "unused" }
            let out = try XCTUnwrap(ClaudeRouteProxy.rewrittenBody(body, resolver: resolver))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: out) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "auto/\(role.rawValue)-model", "\(model) 应被重写")
        }
    }

    func testRewriteEmptyResolverLeavesBodyUnchanged() throws {
        let body = makeBody(model: "claude-sonnet-5")
        let out = ClaudeRouteProxy.rewrittenBody(body, resolver: { _ in "" })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: out!) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "claude-sonnet-5", "真实模型为空时不应改写")
    }

    func testRewriteInvalidJSONReturnsOriginal() {
        let garbage = Data("not json".utf8)
        XCTAssertEqual(ClaudeRouteProxy.rewrittenBody(garbage, resolver: { _ in "auto/best-fast" }), garbage)
    }
}
