import AppKit
import SwiftUI

/// 메뉴바 popover 와 분리된 설정 NSWindow.
///
/// LSUIElement(.accessory) 앱은 default 로 Cmd+Tab 미노출. 설정창 열린 동안만 활성화
/// 정책을 .regular 로 올려서 Dock + Cmd+Tab 에 표시되게 하고, 창 닫히면 다시 .accessory.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    private override init() { super.init() }

    func show(manager: AccountManager, monitor: UsageMonitor, settings: AppSettingsStore) {
        if let win = window {
            elevateActivationPolicy()
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }

        let host = HostingFactory.make(
            SettingsView(manager: manager, monitor: monitor, settings: settings)
        )
        let win = NSWindow(contentViewController: host)
        win.title = "CC Account Manager 설정"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 820, height: 560))
        win.minSize = NSSize(width: 760, height: 500)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        self.window = win

        elevateActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            // 창 닫힘 → 다시 메뉴바 전용으로 복귀.
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func elevateActivationPolicy() {
        // .regular 로 올려야 Dock 아이콘 + Cmd+Tab 노출됨.
        NSApp.setActivationPolicy(.regular)
    }
}
