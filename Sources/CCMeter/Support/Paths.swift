import Foundation

enum Paths {
    static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static var claudeConfig: URL { home.appendingPathComponent(".claude.json") }
    static var claudeCredentials: URL {
        home.appendingPathComponent(".claude/.credentials.json")
    }

    static var appRoot: URL { home.appendingPathComponent(".ccmeter") }
    static var legacyAppRoot: URL { home.appendingPathComponent(".cc-account-manager") }
    static var accountsFile: URL { appRoot.appendingPathComponent("accounts.json") }
    static var settingsFile: URL { appRoot.appendingPathComponent("settings.json") }
    static var snapshotsDir: URL { appRoot.appendingPathComponent("snapshots") }
    static var backupsDir: URL { appRoot.appendingPathComponent("backups") }
    static var lockFile: URL { appRoot.appendingPathComponent(".lock") }
    static var appInstanceLockFile: URL { appRoot.appendingPathComponent(".app.lock") }

    static func snapshotDir(for id: AccountID) -> URL {
        snapshotsDir.appendingPathComponent(id, isDirectory: true)
    }

    /// 구버전 데이터 디렉터리(~/.cc-account-manager)가 존재하고 신버전이 비어있으면 한 번 이동.
    /// 실패해도 throw 하지 않음 — 호출자는 이어서 createDirectory 로 신규 생성을 보장.
    static func migrateLegacyAppRootIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyAppRoot.path),
              !fm.fileExists(atPath: appRoot.path) else { return }
        do {
            try fm.moveItem(at: legacyAppRoot, to: appRoot)
            Log.app.info("Migrated legacy app root: \(legacyAppRoot.path) -> \(appRoot.path)")
        } catch {
            Log.app.error("Legacy app root migration failed: \(String(describing: error))")
        }
    }
}
