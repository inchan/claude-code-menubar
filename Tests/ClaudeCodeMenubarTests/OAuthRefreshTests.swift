import XCTest
@testable import ClaudeCodeMenubar
import Foundation

// MARK: - URLProtocol stub

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let h = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (resp, data) = try h(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private func makeSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: cfg)
}

private let baseCreds = ClaudeAiOAuth(
    accessToken: "old-access",
    refreshToken: "old-refresh",
    expiresAt: 0,
    scopes: ["user:inference"],
    subscriptionType: "pro",
    rateLimitTier: "default"
)

// MARK: - Tests

final class OAuthRefreshTests: XCTestCase {

    override func tearDown() { StubProtocol.handler = nil }

    func testRefreshSuccessRotatesTokens() async throws {
        StubProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
            let body = (try? req.bodyAsString()) ?? ""
            XCTAssertTrue(body.contains("grant_type=refresh_token"))
            XCTAssertTrue(body.contains("refresh_token=old-refresh"))
            XCTAssertTrue(body.contains("client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"))
            let json = #"{"token_type":"Bearer","access_token":"new-access","refresh_token":"new-refresh","expires_in":28800,"scope":"user:inference user:profile"}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let sut = ClaudeOAuthRefresh(endpoints: [URL(string: "https://stub/v1/oauth/token")!],
                                     session: makeSession(),
                                     clock: SystemClock())
        let new = try await sut.refresh(refreshToken: "old-refresh", existing: baseCreds)
        XCTAssertEqual(new.accessToken, "new-access")
        XCTAssertEqual(new.refreshToken, "new-refresh")
        XCTAssertGreaterThan(new.expiresAt, Int64(Date().timeIntervalSince1970 * 1000))
    }

    func testRefreshKeepsOldRefreshTokenWhenServerOmits() async throws {
        StubProtocol.handler = { req in
            let json = #"{"token_type":"Bearer","access_token":"new-access","expires_in":3600}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let sut = ClaudeOAuthRefresh(endpoints: [URL(string: "https://stub/v1/oauth/token")!],
                                     session: makeSession(),
                                     clock: SystemClock())
        let new = try await sut.refresh(refreshToken: "old-refresh", existing: baseCreds)
        XCTAssertEqual(new.refreshToken, "old-refresh")  // rotation fallback
        XCTAssertEqual(new.scopes, baseCreds.scopes)
    }

    func testRefreshInvalidGrantThrows() async {
        StubProtocol.handler = { req in
            let body = #"{"error":"invalid_grant"}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }
        let sut = ClaudeOAuthRefresh(endpoints: [URL(string: "https://stub/v1/oauth/token")!],
                                     session: makeSession(),
                                     clock: SystemClock())
        do {
            _ = try await sut.refresh(refreshToken: "x", existing: baseCreds)
            XCTFail("expected invalid_grant")
        } catch OAuthRefreshError.invalidGrant {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testRefreshFallsBackToSecondEndpointOn5xx() async throws {
        nonisolated(unsafe) var calls = 0
        StubProtocol.handler = { req in
            calls += 1
            if req.url!.host == "first" {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (resp, Data("svc unavailable".utf8))
            }
            let json = #"{"token_type":"Bearer","access_token":"new-access","expires_in":3600}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let sut = ClaudeOAuthRefresh(endpoints: [URL(string: "https://first/v1/oauth/token")!,
                                                 URL(string: "https://second/v1/oauth/token")!],
                                     session: makeSession(),
                                     clock: SystemClock())
        let new = try await sut.refresh(refreshToken: "r", existing: baseCreds)
        XCTAssertEqual(new.accessToken, "new-access")
        XCTAssertEqual(calls, 2)
    }
}

private extension URLRequest {
    func bodyAsString() throws -> String {
        if let d = httpBody { return String(data: d, encoding: .utf8) ?? "" }
        guard let stream = httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: 4096)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
