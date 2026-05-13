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

    /// Keychain access 상태 — 항목 없음 / 권한 거부 / 기타 실패 구분.
    /// 권한 거부는 시작 시 사용자가 "Don't Allow" 누른 경우. read 만 봐서는
    /// "항목 없음" 과 "권한 거부" 가 둘 다 nil 로 합쳐져 UI 가 stale 토큰 fallback 으로
    /// 흘러가므로 별도 분기 필요.
    enum AccessState: Equatable {
        case ok(Data)
        case notFound
        case accessDenied(OSStatus)
        case otherFailure(OSStatus)
    }

    /// Keychain 의 plaintext (JSON bytes) 반환. 항목 없거나 권한 거부 시 nil.
    /// 호출자가 두 케이스를 구분해야 하면 `readDetailed()` 사용.
    static func readRaw() -> Data? {
        if case .ok(let data) = readDetailed() { return data }
        return nil
    }

    /// 상태 분기가 필요한 호출자(예: UsageMonitor) 용. ACL 권한 거부를 별도 케이스로.
    static func readDetailed() -> AccessState {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            if let data = item as? Data { return .ok(data) }
            return .otherFailure(status)
        case errSecItemNotFound:
            return .notFound
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            return .accessDenied(status)
        default:
            return .otherFailure(status)
        }
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
