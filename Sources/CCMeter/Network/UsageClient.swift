import Foundation

// MARK: - Errors

enum UsageClientError: Error, CustomStringConvertible {
    case unauthorized                 // 401: token expired or invalid
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int, body: String)
    case decodeFailed(String)
    case transport(Swift.Error)

    var description: String {
        switch self {
        case .unauthorized: return "Usage API: unauthorized (401)"
        case .rateLimited(let r): return "Usage API: rate limited (retry_after=\(r ?? -1))"
        case .http(let s, let b): return "Usage API: HTTP \(s) — \(b.prefix(200))"
        case .decodeFailed(let m): return "Usage API: decode failed — \(m)"
        case .transport(let e): return "Usage API: transport — \(e.localizedDescription)"
        }
    }
}

// MARK: - Wire types
//
// UNOFFICIAL ENDPOINT.
//   GET https://api.anthropic.com/api/oauth/usage
//   Headers:
//     Authorization: Bearer <claudeAiOauth.accessToken>
//     anthropic-beta: oauth-2025-04-20
//     anthropic-version: 2023-06-01
// 공식 API 문서에 등재되지 않은 비공식 OAuth 전용 엔드포인트. Anthropic 측 변경 시
// 동작이 중단될 수 있다. 변경되어도 계정 스위치 자체에는 영향이 없도록 격리되어 있다.

private struct UsageWindow: Decodable {
    let utilization: Double?
    let resets_at: String?
}

private struct UsageResponse: Decodable {
    let five_hour: UsageWindow?
    let seven_day: UsageWindow?
    let rate_limited: Bool?
    let retry_after: Int?
}

// MARK: - Client

protocol UsageClientProtocol: Sendable {
    func fetch(accessToken: String) async throws -> UsageSnapshot
}

struct UsageClient: UsageClientProtocol {
    let endpoint: URL
    let session: URLSession
    let clock: ClockProtocol

    init(endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
         session: URLSession = .shared,
         clock: ClockProtocol = SystemClock()) {
        self.endpoint = endpoint
        self.session = session
        self.clock = clock
    }

    func fetch(accessToken: String) async throws -> UsageSnapshot {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw UsageClientError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.http(status: -1, body: "no http response")
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw UsageClientError.unauthorized
        case 429:
            let retry = retryAfter(from: http, body: data)
            throw UsageClientError.rateLimited(retryAfter: retry)
        default:
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw UsageClientError.http(status: http.statusCode, body: body)
        }

        let decoded: UsageResponse
        do {
            decoded = try JSON.decoder.decode(UsageResponse.self, from: data)
        } catch {
            throw UsageClientError.decodeFailed(String(describing: error))
        }

        if decoded.rate_limited == true {
            throw UsageClientError.rateLimited(retryAfter: decoded.retry_after.map(TimeInterval.init))
        }

        let fiveUtil = Int((decoded.five_hour?.utilization ?? 0).rounded())
        let fiveResets = parseDate(decoded.five_hour?.resets_at)
        let sevenUtilOpt: Int? = decoded.seven_day?.utilization.map { Int($0.rounded()) }
        let sevenResets = parseDate(decoded.seven_day?.resets_at)

        return UsageSnapshot(
            fiveHourUtilization: fiveUtil,
            fiveHourResetsAt: fiveResets,
            sevenDayUtilization: sevenUtilOpt,
            sevenDayResetsAt: sevenResets,
            fetchedAt: clock.now()
        )
    }

    private func retryAfter(from http: HTTPURLResponse, body: Data) -> TimeInterval? {
        if let h = http.value(forHTTPHeaderField: "Retry-After"),
           let s = Double(h) {
            return s
        }
        if let parsed = try? JSON.decoder.decode(UsageResponse.self, from: body),
           let r = parsed.retry_after {
            return TimeInterval(r)
        }
        return nil
    }

    private func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return Self.iso8601WithFraction.date(from: s) ?? Self.iso8601.date(from: s)
    }

    // ISO8601DateFormatter 는 thread-safe (Apple 문서) → static let 캐시 안전.
    nonisolated(unsafe) private static let iso8601WithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
