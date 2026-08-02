//
//  OmnirouteAPIClientTests.swift
//  OmniBarTests
//
//  OmnirouteAPIClient 网络层测试：URL 构造、请求头、状态码处理、JSON 解码。
//

import XCTest
@testable import OmniBar

final class OmnirouteAPIClientTests: XCTestCase {

    private var client: OmnirouteAPIClient!
    private let port = 20128
    private let apiKey = "test-api-key"

    override func setUp() {
        super.setUp()
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.lastRequest = nil
        let settings = AppSettings.shared
        settings.omniroutePort = port
        settings.omnirouteAPIKey = apiKey
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        client = OmnirouteAPIClient(settings: settings, session: session)
    }

    private func response(status: Int, for path: String = "/api/x") throws -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "http://localhost:\(port)\(path)")!,
                        statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - fetchProviders

    func testFetchProvidersBuildsURLAndDecodes() async throws {
        let json = """
        {"connections": [{"id":"1","provider":"siliconflow","name":"main",
          "isActive":true,"testStatus":"active","backoffLevel":0}], "total":1}
        """
        MockURLProtocol.requestHandler = { request in
            return (try self.response(status: 200, for: "/api/providers"), Data(json.utf8))
        }
        let providers = try await client.fetchProviders()
        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.providerType, "siliconflow")
        XCTAssertEqual(providers.first?.health, .active)

        let url = try XCTUnwrap(MockURLProtocol.lastRequest?.url)
        XCTAssertEqual(url.path, "/api/providers")
        XCTAssertEqual(url.port, port)
        XCTAssertEqual(url.host, "localhost")
    }

    // MARK: - fetchCombos

    func testFetchCombosDecodesModels() async throws {
        let json = """
        {"combos": [{"id":"c1","name":"coding","strategy":"priority",
          "sortOrder":1,"models":[{"id":"m1","model":"command-code/deepseek/x"}]}], "total":1}
        """
        MockURLProtocol.requestHandler = { request in
            return (try self.response(status: 200, for: "/api/combos"), Data(json.utf8))
        }
        let combos = try await client.fetchCombos()
        XCTAssertEqual(combos.count, 1)
        XCTAssertEqual(combos.first?.name, "coding")
        XCTAssertEqual(combos.first?.models.first?.model, "command-code/deepseek/x")
    }

    // MARK: - Authorization Header

    func testRequestAddsAuthorizationHeader() async throws {
        MockURLProtocol.requestHandler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            XCTAssertEqual(auth, "Bearer \(self.apiKey)")
            let contentType = request.value(forHTTPHeaderField: "Content-Type")
            XCTAssertEqual(contentType, "application/json")
            return (try self.response(status: 200), Data("{}".utf8))
        }
        struct Empty: Codable {}
        let _: Empty = try await client.request("/api/settings")
    }

    // MARK: - HTTP Status Code Handling

    func testRequestHandles401AsUnauthorized() async {
        MockURLProtocol.requestHandler = { request in
            return (try self.response(status: 401), Data())
        }
        struct Empty: Codable {}
        do {
            let _: Empty = try await client.request("/api/providers")
            XCTFail("Expected unauthorized error")
        } catch let error as OmnirouteAPIError {
            guard case .unauthorized = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRequestHandles404AsEndpointUnavailable() async {
        MockURLProtocol.requestHandler = { request in
            return (try self.response(status: 404), Data())
        }
        struct Empty: Codable {}
        do {
            let _: Empty = try await client.request("/api/providers")
            XCTFail("Expected endpointUnavailable error")
        } catch let error as OmnirouteAPIError {
            guard case .endpointUnavailable = error else {
                return XCTFail("Expected .endpointUnavailable, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRequestHandles405AsEndpointUnavailable() async {
        MockURLProtocol.requestHandler = { request in
            return (try self.response(status: 405), Data())
        }
        struct Empty: Codable {}
        do {
            let _: Empty = try await client.request("/api/settings", method: "POST")
            XCTFail("Expected endpointUnavailable error")
        } catch let error as OmnirouteAPIError {
            guard case .endpointUnavailable = error else {
                return XCTFail("Expected .endpointUnavailable, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRequestHandlesServerError5xx() async {
        MockURLProtocol.requestHandler = { request in
            return (try self.response(status: 500), Data())
        }
        struct Empty: Codable {}
        do {
            let _: Empty = try await client.request("/api/providers")
            XCTFail("Expected httpError")
        } catch let error as OmnirouteAPIError {
            guard case .httpError(500) = error else {
                return XCTFail("Expected .httpError(500), got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - requestVoid

    func testRequestVoidSucceedsOn204() async throws {
        MockURLProtocol.requestHandler = { request in
            return (try self.response(status: 204), Data())
        }
        try await client.requestVoid("/api/providers/1", method: "PATCH")
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "PATCH")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/api/providers/1")
    }

    func testRequestVoidThrowsOnNon2xx() async {
        MockURLProtocol.requestHandler = { request in
            return (try self.response(status: 400), Data())
        }
        do {
            try await client.requestVoid("/api/providers/1", method: "DELETE")
            XCTFail("Expected httpError")
        } catch let error as OmnirouteAPIError {
            guard case .httpError(400) = error else {
                return XCTFail("Expected .httpError(400), got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

