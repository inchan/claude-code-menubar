import AppKit
import SwiftUI

extension ThresholdLevel {
    /// Mock 시안(docs/settings-mockups.html) 정확값 매핑.
    /// healthy → green #57C28B / caution → warn #E0A961 / warning → clay #D97757 / critical → red #E5484D.
    var defaultNSColor: NSColor {
        switch self {
        case .healthy:  return NSColor(srgbRed: 0x57/255.0, green: 0xC2/255.0, blue: 0x8B/255.0, alpha: 1)
        case .caution:  return NSColor(srgbRed: 0xE0/255.0, green: 0xA9/255.0, blue: 0x61/255.0, alpha: 1)
        case .warning:  return NSColor(srgbRed: 0xD9/255.0, green: 0x77/255.0, blue: 0x57/255.0, alpha: 1)
        case .critical: return NSColor(srgbRed: 0xE5/255.0, green: 0x48/255.0, blue: 0x4D/255.0, alpha: 1)
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
