import AppKit
import SwiftUI

/// 앱 전체 폰트 단일 정의원.
/// 본문은 SF Pro (system), 패널 헤딩은 rounded design 으로 Claude 분위기에 맞춘다.
enum AppFonts {
    static let menuBarSize: CGFloat = 12

    // MARK: - AppKit (NSImage drawing 등)

    static func ns(size: CGFloat, bold: Bool = false) -> NSFont {
        let weight: NSFont.Weight = bold ? .semibold : .regular
        return .systemFont(ofSize: size, weight: weight)
    }

    // MARK: - SwiftUI

    /// 본문/캡션용. SF Pro.
    static func swiftUI(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// 패널 헤더/타이틀용. SF Pro Rounded — Claude 시그니처 톤.
    static func heading(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// 숫자/배지용. 모노 폭. 사용률 % 정렬에 사용.
    static func mono(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
