import AppKit
import SwiftUI

/// 앱 전체 폰트 단일 정의원. Tahoma 부재 시 system 폰트로 fallback.
enum AppFonts {
    static let family = "Tahoma"
    static let menuBarSize: CGFloat = 12   // 기존 11 → +1pt

    // MARK: - AppKit (NSImage drawing 등)

    static func ns(size: CGFloat, bold: Bool = false) -> NSFont {
        let weight: NSFont.Weight = bold ? .bold : .regular
        if let f = NSFont(name: bold ? "\(family) Bold" : family, size: size) {
            return f
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    // MARK: - SwiftUI

    static func swiftUI(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(family, size: size).weight(weight)
    }
}
