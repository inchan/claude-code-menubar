import Foundation

// MARK: - Errors

enum OAuthRefreshError: Error, CustomStringConvertible {
    case invalidGrant(String)           // 400/401: refresh_token 만료/revoke → 재로그인 필요
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int, body: String)
    case decodeFailed(String)
    case transport(Swift.Error)

    var description: String {
        switch self {
        case .invalidGrant(let m):       return "OAuth refresh: invalid_grant — \(m)"
        case .rateLimited(let r):        return "OAuth refresh: rate limited (retry=\(r ?? -1))"
        case .http(let s, let b):        return "OAuth refresh: HTTP \(s) — \(b.prefix(200))"
        case .decodeFailed(let m):       return "OAuth refresh: decode — \(m)"
        case .transport(let e):          return "OAuth refresh: transport — \(e.localizedDescription)"
        }
    }
}

// MARK: - Wire response
//
// UNOFFICIAL ENDPOINT. Claude Code 가 사용하는 OAuth refresh flow.
//   POST https://console.anthropic.com/v1/oauth/token   (1차)
//   POST https://claude.ai/v1/oauth/token               (fallback)
//   Content-Type: application/x-www-form-urlencoded
//   body:
//     grant_type=refresh_token
//     &refresh_token=<sk-ant-ort01-...>
//     &client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e
//
//   200: { token_type, access_token, refresh_token?, expires_in, scope, organization?, account? }
//   400/401: { error: "invalid_grant", ... } → 재로그인 필요
//   429: rate limited
//
// 공식 API 문서에 없으나 다수 오픈소스 (anthropics/claude-code#47754,
// griffinmartin/opencode-claude-auth, akashmohan.com) 에서 동일 client_id/엔드포인트 확인.

private struct RefreshResponseWire: Decodable {
    let token_type: String?
    let access_token: String
    let refresh_token: String?         // rotation — 없으면 기존 유지
    let expires_in: Int?               // seconds (typically 28800 = 8h)
    let scope: String?
}

// MARK: - Client

protocol ClaudeOAuthRefreshProtocol: Sendable {
    func refresh(refreshToken: String, existing: ClaudeAiOAuth) async throws -> ClaudeAiOAuth
}

struct ClaudeOAuthRefresh: ClaudeOAuthRefreshProtocol {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let primaryEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    static let fallbackEndpoint = URL(string: "https://claude.ai/v1/oauth/token")!

    let endpoints: [URL]
    let session: URLSession
    let clock: ClockProtocol

    init(endpoints: [URL] = [Self.primaryEndpoint, Self.fallbackEndpoint],
         session: URLSession = .shared,
         clock: ClockProtocol = SystemClock()) {
        self.endpoints = endpoints
        self.session = session
        self.clock = clock
    }

    func refresh(refreshToken: String, existing: ClaudeAiOAuth) async throws -> ClaudeAiOAuth {
        // 1차/fallback 순차 시도. transport / 5xx / 429 fallback. invalid_grant(400/401) 만 즉시 throw.
        // 실측: console.anthropic.com 가 429 던지는 동안 claude.ai 가 200 — endpoint 별 rate limit 분리됨.
        var lastError: Swift.Error?
        for url in endpoints {
            do {
                return try await postRefresh(url: url, refreshToken: refreshToken, existing: existing)
            } catch OAuthRefreshError.invalidGrant(let m) {
                throw OAuthRefreshError.invalidGrant(m)
            } catch OAuthRefreshError.transport(let e) {
                Log.usage.error("[OAUTH-REFRESH transport] url=\(url.absoluteString, privacy: .public) err=\(String(describing: e), privacy: .public)")
                lastError = OAuthRefreshError.transport(e)
                continue
            } catch OAuthRefreshError.rateLimited(let r) {
                Log.usage.error("[OAUTH-REFRESH 429] url=\(url.absoluteString, privacy: .public) retry=\(r ?? -1)")
                lastError = OAuthRefreshError.rateLimited(retryAfter: r)
                continue
            } catch OAuthRefreshError.http(let s, let b) where (500..<600).contains(s) {
                Log.usage.error("[OAUTH-REFRESH 5xx] url=\(url.absoluteString, privacy: .public) status=\(s)")
                lastError = OAuthRefreshError.http(status: s, body: b)
                continue
            } catch {
                throw error
            }
        }
        throw lastError ?? OAuthRefreshError.http(status: -1, body: "all endpoints failed")
    }

    private func postRefresh(url: URL, refreshToken: String, existing: ClaudeAiOAuth) async throws -> ClaudeAiOAuth {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let body = formEncode([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID
        ])
        req.httpBody = body.data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw OAuthRefreshError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw OAuthRefreshError.http(status: -1, body: "no http response")
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 400, 401:
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            Log.usage.error("[OAUTH-REFRESH invalid_grant] status=\(http.statusCode) body=\(bodyStr, privacy: .public)")
            throw OAuthRefreshError.invalidGrant(bodyStr)
        case 429:
            let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init)
            throw OAuthRefreshError.rateLimited(retryAfter: retry)
        default:
            let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OAuthRefreshError.http(status: http.statusCode, body: bodyStr)
        }

        let wire: RefreshResponseWire
        do {
            wire = try JSON.decoder.decode(RefreshResponseWire.self, from: data)
        } catch {
            throw OAuthRefreshError.decodeFailed(String(describing: error))
        }

        let newExpiresEpochMs: Int64
        if let secs = wire.expires_in {
            newExpiresEpochMs = Int64(clock.now().timeIntervalSince1970 * 1000) + Int64(secs) * 1000
        } else {
            // 응답에 expires_in 누락 — 기본 8h 가정
            newExpiresEpochMs = Int64(clock.now().timeIntervalSince1970 * 1000) + 8 * 3600 * 1000
        }

        Log.usage.info("[OAUTH-REFRESH ok] url=\(url.absoluteString, privacy: .public) rotated=\(wire.refresh_token != nil) expires_in=\(wire.expires_in ?? -1)")

        return ClaudeAiOAuth(
            accessToken:      wire.access_token,
            refreshToken:     wire.refresh_token ?? existing.refreshToken,  // rotation fallback
            expiresAt:        newExpiresEpochMs,
            scopes:           wire.scope.map { $0.split(separator: " ").map(String.init) } ?? existing.scopes,
            subscriptionType: existing.subscriptionType,
            rateLimitTier:    existing.rateLimitTier
        )
    }

    private func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return params
            .map { k, v in
                let kEnc = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
                let vEnc = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
                return "\(kEnc)=\(vEnc)"
            }
            .joined(separator: "&")
    }
}
