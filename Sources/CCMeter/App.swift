import AppKit

/// SwiftUI App 폐기 — 메뉴바 전용(LSUIElement) 앱은 NSApplication 직접 사용이 가장 안정.
/// SwiftUI App + Settings scene 조합이 macOS 26 에서 AppDelegate 콜백을 호출하지 않는
/// 케이스가 발생했음.
@main
enum CCMeterMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // 메뉴바 전용 — Dock/메뉴바 메뉴 비표시
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var instanceLock: FileLock?
    private var manager: AccountManager!
    private var monitor: UsageMonitor!
    private var settings: AppSettingsStore!
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        prepareAppRoot()
        enforceSingleInstance()

        manager = AccountManager()
        // 순서 중요: monitor.init 의 loadCachedSnapshots 가 accounts 를 읽으므로
        // manager.reload() 가 monitor 생성보다 먼저 호출돼야 캐시된 usage.json 이 로드됨.
        manager.reload()
        monitor = UsageMonitor(accountManager: manager)
        settings = AppSettingsStore()
        statusItemController = StatusItemController(
            manager: manager, monitor: monitor, settings: settings
        )
        monitor.start()

        Log.app.info("CCMeter started (bundleId=\(Bundle.main.bundleIdentifier ?? "?"))")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.teardown()
    }

    private func enforceSingleInstance() {
        do {
            instanceLock = try FileLock.acquire(at: Paths.appInstanceLockFile.path,
                                                blocking: false)
        } catch FileLockError.busy {
            Log.app.warning("Another instance holds .app.lock — quitting self.")
            activateExistingInstance()
            NSApp.terminate(nil)
            return
        } catch {
            Log.app.error("FileLock acquire failed: \(String(describing: error))")
        }

        if let bundleId = Bundle.main.bundleIdentifier {
            let myPid = ProcessInfo.processInfo.processIdentifier
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                .filter { $0.processIdentifier != myPid }
            if !others.isEmpty {
                others.first?.activate(options: [.activateIgnoringOtherApps])
                NSApp.terminate(nil)
            }
        }
    }

    private func activateExistingInstance() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
            .activate(options: [.activateIgnoringOtherApps])
    }

    private func prepareAppRoot() {
        Paths.migrateLegacyAppRootIfNeeded()
        let dirs = [Paths.appRoot, Paths.snapshotsDir, Paths.backupsDir]
        for dir in dirs {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            chmod(dir.path, 0o700)
        }
    }
}
