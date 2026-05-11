import Foundation
import OSLog

enum Log {
    private static let subsystem = "com.inchan.ccmeter"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let store = Logger(subsystem: subsystem, category: "storage")
    static let switching = Logger(subsystem: subsystem, category: "switch")
    static let usage = Logger(subsystem: subsystem, category: "usage")
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// 토큰 마스킹 — 길이/접두 노출 차단, 결정적 해시 hex 8자만.
    static func mask(_ token: String?) -> String {
        guard let t = token, !t.isEmpty else { return "<nil>" }
        return "<token:" + String(format: "%08x", FNV.hash32(t)) + ">"
    }
}
