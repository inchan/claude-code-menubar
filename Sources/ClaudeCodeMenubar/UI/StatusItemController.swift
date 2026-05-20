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
    private var pulseTimer: Timer?
    private var pulsePhase: Double = 0

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
        let cfg = s.thresholdConfig
        let fiveLv = (s.usageVisibility.showsSession ? snap : nil)
            .map { ThresholdLevel.from(percent: $0.fiveHourUtilization, thresholds: cfg) }
        let sevenLv = (s.usageVisibility.showsWeekly ? snap : nil)
            .flatMap { sn in sn.sevenDayUtilization.map { ThresholdLevel.from(percent: $0, thresholds: cfg) } }
        let fLevel = fiveLv?.rawValue ?? "-"
        let sLevel = sevenLv?.rawValue ?? "-"
        let warning = activeNeedsAttention
        let key = "\(acc?.initial ?? "?")|\(acc?.colorHex ?? "")|\(s.menuBarStyle.rawValue)|\(fiveDisplay.map(String.init) ?? "-")|\(fLevel)|\(sevenDisplay.map(String.init) ?? "-")|\(sLevel)|\(s.colorOverrides.description)|\(cfg.caution)/\(cfg.warning)/\(cfg.critical)|w=\(warning)"
        // Behavior 토글 효과는 매번 적용 (key 변동과 무관) — pulse on/off, tooltip 갱신
        applyBehavior(button: button, account: acc, usage: snap,
                      fiveLv: fiveLv, sevenLv: sevenLv,
                      fiveDisplay: fiveDisplay, sevenDisplay: sevenDisplay,
                      warning: warning, settings: s)
        if key == lastImageKey { return }
        let prevKey = lastImageKey
        lastImageKey = key
        button.image = StatusIconRenderer.renderStatusBar(
            initial: acc?.initial ?? "?",
            hex: acc?.colorHex ?? "#888888",
            fiveHour: fiveDisplay,
            fiveLevel: fiveLv,
            sevenDay: sevenDisplay,
            sevenLevel: sevenLv,
            style: s.menuBarStyle,
            colorOverrides: s.colorOverrides,
            warning: warning
        )
        // blinkOnChange — 첫 렌더(prevKey nil) 가 아니라 데이터/설정 변동 시에만 깜빡
        if s.blinkOnChange, prevKey != nil {
            button.alphaValue = 0.25
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.allowsImplicitAnimation = true
                button.animator().alphaValue = pulseTimer == nil ? 1.0 : currentPulseAlpha()
            }
        }
    }

    /// Behavior 카드 토글 3개 효과 적용.
    private func applyBehavior(button: NSStatusBarButton,
                               account: Account?,
                               usage: UsageSnapshot?,
                               fiveLv: ThresholdLevel?,
                               sevenLv: ThresholdLevel?,
                               fiveDisplay: Int?,
                               sevenDisplay: Int?,
                               warning: Bool,
                               settings s: AppSettings) {
        // warning(Keychain 권한 거부 등) 시 tooltip override — hoverDetail 보다 우선.
        if warning {
            button.toolTip = "🔐 Keychain 접근 권한 필요 — 메뉴를 열어 새로고침으로 다시 요청하세요"
        } else {
            button.toolTip = makeTooltip(account: account, usage: usage,
                                         fiveLv: fiveLv, sevenLv: sevenLv,
                                         fiveDisplay: fiveDisplay, sevenDisplay: sevenDisplay,
                                         detail: s.hoverDetail, timeFormat: s.timeFormat)
        }

        // iconAnimation — 1.6s 호흡 펄스. off면 정지.
        if s.iconAnimation {
            if pulseTimer == nil { startPulse(button: button) }
        } else {
            stopPulse(button: button)
        }
    }

    /// 활성 계정에 사용자 개입이 필요한 상태 (현재는 Keychain 권한 거부).
    private var activeNeedsAttention: Bool {
        guard let id = manager.activeAccountID else { return false }
        return monitor.lastError[id] == .keychainDenied
    }

    private func startPulse(button: NSStatusBarButton) {
        pulsePhase = 0
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let btn = self.statusItem.button else { return }
                self.pulsePhase += 1.0 / 30.0
                btn.alphaValue = self.currentPulseAlpha()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        pulseTimer = t
    }

    private func stopPulse(button: NSStatusBarButton) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulsePhase = 0
        button.alphaValue = 1.0
    }

    /// 1.6s 주기 sin 펄스. 진폭 0.55..1.0.
    private func currentPulseAlpha() -> Double {
        let period = 1.6
        let phase = (pulsePhase.truncatingRemainder(dividingBy: period)) / period
        // sin 0..2π
        let s = sin(phase * 2 * .pi)
        return 0.775 + 0.225 * s   // 0.55 .. 1.0
    }

    private func makeTooltip(account: Account?,
                             usage: UsageSnapshot?,
                             fiveLv: ThresholdLevel?,
                             sevenLv: ThresholdLevel?,
                             fiveDisplay: Int?,
                             sevenDisplay: Int?,
                             detail: Bool,
                             timeFormat: TimeFormatStyle) -> String {
        let name = account?.label ?? "Claude Code Menubar"
        if !detail {
            return name
        }
        var lines: [String] = [name]
        if let p = fiveDisplay {
            var line = "Session: \(p)%"
            if let r = usage?.fiveHourResetsAt {
                line += " · reset \(TimeFormat.format(r, style: timeFormat))"
            }
            lines.append(line)
        }
        if let p = sevenDisplay {
            var line = "Weekly: \(p)%"
            if let r = usage?.sevenDayResetsAt {
                line += " · reset \(TimeFormat.format(r, style: timeFormat))"
            }
            lines.append(line)
        }
        _ = fiveLv; _ = sevenLv  // 색 매핑은 메뉴바 image에서. tooltip은 텍스트만.
        return lines.joined(separator: "\n")
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
