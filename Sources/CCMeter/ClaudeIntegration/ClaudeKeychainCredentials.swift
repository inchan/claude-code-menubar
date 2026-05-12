import Foundation
import Security

/// macOS Keychain "Claude Code-credentials" 항목 R/W.
///
/// macOS Claude Code 는 토큰 refresh / 새 로그인 시 Keychain 만 갱신하고
/// `~/.claude/.credentials.json` 파일은 stale 로 남기는 동작이 관찰됨.
/// 따라서:
/// - read: Keychain 우선 → 파일 fallback (ClaudeLiveCredentials 단일 정의원)
/// - write (스위치): 파일 + Keychain 동시 갱신 (둘 다 안 맞추면 read 가 stale 토큰 사용)
enum ClaudeKeychainCredentials {
    static let serviceName = "Claude Code-credentials"

    enum Error: Swift.Error, CustomStringConvertible {
        case writeFailed(OSStatus)
        var description: String {
            switch self {
            case .writeFailed(let s): return "Keychain write failed: OSStatus=\(s)"
            }
        }
    }

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

    /// "Claude Code-credentials" generic password 항목을 `data` 로 교체.
    /// 항목이 없으면 생성. Claude Code 본체가 만든 ACL/접근권한은 SecItemUpdate 가 보존한다.
    /// 회귀 진단을 위해 `[KEYCHAIN-WRITE]` 소스 로깅 — read 의 `[CRED-SRC]` 와 짝.
    static func writeRaw(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            Log.switching.info("[KEYCHAIN-WRITE] update ok")
            return
        }
        if updateStatus == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus == errSecSuccess {
                Log.switching.info("[KEYCHAIN-WRITE] add ok")
                return
            }
            Log.switching.error("[KEYCHAIN-WRITE] add failed OSStatus=\(addStatus)")
            throw Error.writeFailed(addStatus)
        }
        Log.switching.error("[KEYCHAIN-WRITE] update failed OSStatus=\(updateStatus)")
        throw Error.writeFailed(updateStatus)
    }
}
