import Foundation

enum ClaudeConfigError: Error, CustomStringConvertible {
    case fileNotFound(URL)
    case invalidJSON
    case missingOAuthAccount

    var description: String {
        switch self {
        case .fileNotFound(let u): return "Claude config not found: \(u.path)"
        case .invalidJSON: return "Claude config is not a valid JSON object"
        case .missingOAuthAccount: return "Claude config missing 'oauthAccount'"
        }
    }
}

/// `~/.claude.json` 의 `oauthAccount` 필드만 안전하게 R/W. 나머지 234KB는 보존.
final class ClaudeConfigFile {
    private let url: URL
    init(url: URL = Paths.claudeConfig) { self.url = url }

    /// 현재 파일 전체 raw bytes (백업용)
    func readRaw() throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ClaudeConfigError.fileNotFound(url)
        }
        return try Data(contentsOf: url)
    }

    /// `oauthAccount` 서브트리만 raw JSON bytes 로 추출
    func readOAuthAccountJSON() throws -> Data {
        let root = try readRoot()
        guard let oauth = root["oauthAccount"] else {
            throw ClaudeConfigError.missingOAuthAccount
        }
        return try JSONSerialization.data(withJSONObject: oauth, options: [.sortedKeys])
    }

    /// 표시용 부분 디코딩
    func readOAuthAccount() throws -> ClaudeOAuthAccount {
        let data = try readOAuthAccountJSON()
        return try JSON.decode(ClaudeOAuthAccount.self, from: data)
    }

    /// 새 oauthAccount JSON 으로 patch. **다른 모든 키 + 키 순서 + 들여쓰기 + 정수 표현 보존.**
    /// JSONSerialization 재직렬화 대신 byte-slice 교체 사용 (codex 권고 P1).
    func patchOAuthAccount(_ oauthAccountJSON: Data) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ClaudeConfigError.fileNotFound(url)
        }
        let original = try Data(contentsOf: url)
        // 키 존재 검증 (없으면 명확한 에러)
        guard try JSONSerialization.jsonObject(with: original) is [String: Any] else {
            throw ClaudeConfigError.invalidJSON
        }
        let patched: Data
        do {
            patched = try JSONByteSlicePatcher.replace(in: original,
                                                       key: "oauthAccount",
                                                       with: oauthAccountJSON)
        } catch JSONByteSlicePatcher.Error.keyNotFound {
            throw ClaudeConfigError.missingOAuthAccount
        }
        try AtomicFileWriter.write(patched, to: url, permissions: 0o600)
    }

    private func readRoot() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ClaudeConfigError.fileNotFound(url)
        }
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeConfigError.invalidJSON
        }
        return root
    }
}
