import AppKit
import SwiftUI

/// 메뉴바 전용 앱에서 NSHostingController 생성을 일원화. 직접 생성자 호출 금지.
///
/// macOS 13+ default 는 SwiftUI ideal size 를 host.preferredContentSize 로
/// 자동 채택하지 않음 → preferredContentSize=(0,0) → NSPopover anchor 깨짐.
/// `sizingOptions = [.preferredContentSize]` 를 항상 적용해 이 결함을 원천 차단.
@MainActor
enum HostingFactory {
    static func make<V: View>(_ view: V) -> NSHostingController<V> {
        let h = NSHostingController(rootView: view)
        h.sizingOptions = [.preferredContentSize]
        return h
    }
}
