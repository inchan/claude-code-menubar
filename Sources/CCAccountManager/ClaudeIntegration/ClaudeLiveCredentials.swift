import Foundation

/// 활성 Claude OAuth credentials 의 단일 정의원.
/// Keychain 우선 → 파일 fallback. macOS Claude Code 는 토큰 refresh / 새 로그인 시
/// Keychain 만 갱신하고 `~/.claude/.credentials.json` 파일은 stale 또는 부재 상태로
/// 남기는 동작이 관찰됨.
enum ClaudeLiveCredentials {
    enum Error: Swift.Error, CustomStringConvertible {
        case notFound
        case decodeFailed(String)
        var description: String {
            switch self {
            case .notFound: return "활성 Claude credentials 를 찾지 못함 (Keychain + 파일 둘 다 부재)"
            case .decodeFailed(let m): return "credentials 디코드 실패: \(m)"
            }
        }
    }

    enum Source: String { case keychain, file }

    /// raw JSON bytes. Keychain 우선 → 파일 fallback. source 로깅으로 회귀 즉시 진단 가능.
    static func readRaw() throws -> Data {
        if let data = ClaudeKeychainCredentials.readRaw(),
           (try? JSON.decode(ClaudeCredentialsRoot.self, from: data)) != nil {
            Log.usage.info("[CRED-SRC] keychain")
            return data
        }
        let file = ClaudeCredentialsFile()
        if let data = try? file.readRaw(),
           (try? JSON.decode(ClaudeCredentialsRoot.self, from: data)) != nil {
            Log.usage.info("[CRED-SRC] file")
            return data
        }
        Log.usage.error("[CRED-SRC] none — Keychain + file 모두 부재/디코드 실패")
        throw Error.notFound
    }

    static func read() throws -> ClaudeCredentialsRoot {
        let data = try readRaw()
        do { return try JSON.decode(ClaudeCredentialsRoot.self, from: data) }
        catch { throw Error.decodeFailed(String(describing: error)) }
    }
}
