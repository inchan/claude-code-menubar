import AppKit
import SwiftUI

extension ThresholdLevel {
    /// 시스템 기본 색.
    var defaultNSColor: NSColor {
        switch self {
        case .healthy: return .systemGreen
        case .caution: return .systemYellow
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    /// override 가 있으면 우선, 없으면 default.
    func nsColor(overrides: [String: String]) -> NSColor {
        if let hex = overrides[rawValue], let c = NSColor(hex: hex) { return c }
        return defaultNSColor
    }

    func color(overrides: [String: String]) -> Color {
        Color(nsColor(overrides: overrides))
    }

    /// 단순 호출(설정 미참조) — 시스템 기본.
    var nsColor: NSColor { defaultNSColor }
    var color: Color { Color(defaultNSColor) }
}
