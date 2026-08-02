//
//  MockURLProtocol.swift
//  OmniBarTests
//
//  拦截 URLSession 请求并返回预设响应，用于测试 OmnirouteAPIClient。
//

import Foundation

/// 通过注入 URLSessionConfiguration.protocolClasses 拦截网络请求的自定义 URLProtocol。
final class MockURLProtocol: URLProtocol {
    /// 测试注入的响应构造闭包。返回 (HTTPURLResponse, Data) 或抛错。
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    /// 最后一次捕获的请求，供断言 URL / Headers / Method。
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
