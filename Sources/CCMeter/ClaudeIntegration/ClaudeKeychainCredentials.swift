import Foundation
import Security

/// macOS Keychain "Claude Code-credentials" 항목에서 OAuth credentials 를 읽는다.
///
/// macOS Claude Code 는 토큰 refresh 시 Keychain 만 갱신하고
/// `~/.claude/.credentials.json` 파일은 stale 로 남기는 동작이 관찰됨.
/// 따라서 활성 계정 토큰 조회는 Keychain 우선 → 파일 fallback 으로 동작해야 한다.
enum ClaudeKeychainCredentials {
    static let serviceName = "Claude Code-credentials"

    /// Keychain 의 plaintext (JSON bytes) 반환. 항목 없거나 권한 거부 시 nil.
    static func readRaw() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
}
