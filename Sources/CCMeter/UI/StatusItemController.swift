import AppKit
import SwiftUI
import Combine

/// AppKit NSStatusItem 직접 제어. SwiftUI MenuBarExtra 의 NSImage 라이프사이클 이슈 회피.
/// AccountManager / UsageMonitor / AppSettingsStore 변경 시 button.image 를 재생성.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let manager: AccountManager
    private let monitor: UsageMonitor
    private let settings: AppSettingsStore
    private var cancellables: Set<AnyCancellable> = []
    private var lastImageKey: String?

    init(manager: AccountManager, monitor: UsageMonitor, settings: AppSettingsStore) {
        self.manager = manager
        self.monitor = monitor
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.animates = true
        // 모든 NSHostingController 는 .sized factory 사용. sizingOptions 누락 차단.
        self.popover.contentViewController = HostingFactory.make(
            AccountMenuView(manager: manager, monitor: monitor, settings: settings)
        )

        configureButton()
        bindUpdates()
        refreshImage()
        scheduleSelfCheck()
    }

    /// 1초 후 button.image 가 정상 size 인지 자가 검증. 실패 시 ERROR 로깅.
    /// 추후 회귀(라이프사이클/render path)를 즉시 알 수 있도록.
    private func scheduleSelfCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let size = self.statusItem.button?.image?.size ?? .zero
            if size.width < 10 || size.height < 10 {
                Log.app.error("[SELF-CHECK FAIL] status bar image size=\(size.debugDescription, privacy: .public) — 라벨이 보이지 않을 가능성")
            } else {
                Log.app.info("[SELF-CHECK OK] status bar image size=\(size.debugDescription, privacy: .public)")
            }
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
    }

    private func bindUpdates() {
        // 데이터 변경 시 메뉴바 라벨 재생성
        manager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshImage() }
            .store(in: &cancellables)
        monitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshImage() }
            .store(in: &cancellables)
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // 설정 변경 시 cache key 강제 무효화 — 즉시 라벨 재렌더.
                self?.lastImageKey = nil
                self?.refreshImage()
            }
            .store(in: &cancellables)
    }

    private func refreshImage() {
        guard let button = statusItem.button else { return }
        let acc = activeAccount
        let snap = activeUsage
        let s = settings.settings
        let fiveDisplay: Int? = (s.usageVisibility.showsSession ? snap : nil)
            .map { s.usageDisplayMode.display(utilization: $0.fiveHourUtilization) }
        let sevenDisplay: Int? = (s.usageVisibility.showsWeekly ? snap : nil)
            .flatMap { sn in sn.sevenDayUtilization.map { s.usageDisplayMode.display(utilization: $0) } }
        let fLevel = (s.usageVisibility.showsSession ? snap : nil).map(\.fiveHourLevel.rawValue) ?? "-"
        let sLevel = (s.usageVisibility.showsWeekly ? snap : nil).map(\.sevenDayLevel.rawValue) ?? "-"
        let warning = activeNeedsAttention
        let key = "\(acc?.initial ?? "?")|\(acc?.colorHex ?? "")|\(s.menuBarStyle.rawValue)|\(fiveDisplay.map(String.init) ?? "-")|\(fLevel)|\(sevenDisplay.map(String.init) ?? "-")|\(sLevel)|\(s.colorOverrides.description)|w=\(warning)"
        if key == lastImageKey { return }
        lastImageKey = key
        button.image = StatusIconRenderer.renderStatusBar(
            initial: acc?.initial ?? "?",
            hex: acc?.colorHex ?? "#888888",
            fiveHour: fiveDisplay,
            fiveLevel: s.usageVisibility.showsSession ? snap?.fiveHourLevel : nil,
            sevenDay: sevenDisplay,
            sevenLevel: s.usageVisibility.showsWeekly ? snap?.sevenDayLevel : nil,
            style: s.menuBarStyle,
            colorOverrides: s.colorOverrides,
            warning: warning
        )
        button.toolTip = warning
            ? "🔐 Keychain 접근 권한 필요 — 메뉴를 열어 새로고침으로 다시 요청하세요"
            : nil
    }

    /// 활성 계정에 사용자 개입이 필요한 상태 (현재는 Keychain 권한 거부).
    private var activeNeedsAttention: Bool {
        guard let id = manager.activeAccountID else { return false }
        return monitor.lastError[id] == "keychain_denied"
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        manager.reload()
        Task { await monitor.refreshActiveOnce() }
    }

    private var activeAccount: Account? {
        guard let id = manager.activeAccountID else { return nil }
        return manager.accounts.first { $0.id == id }
    }

    private var activeUsage: UsageSnapshot? {
        guard let id = manager.activeAccountID else { return nil }
        return monitor.snapshots[id]
    }
}
