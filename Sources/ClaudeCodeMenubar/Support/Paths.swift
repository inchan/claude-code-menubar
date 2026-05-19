import Foundation

enum Paths {
    static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static var claudeConfig: URL { home.appendingPathComponent(".claude.json") }
    static var claudeCredentials: URL {
        home.appendingPathComponent(".claude/.credentials.json")
    }

    static var appRoot: URL { home.appendingPathComponent(".claude-code-menubar") }
    static var legacyAppRoot: URL { home.appendingPathComponent(".ccmeter") }
    static var accountsFile: URL { appRoot.appendingPathComponent("accounts.json") }
    static var settingsFile: URL { appRoot.appendingPathComponent("settings.json") }
    static var snapshotsDir: URL { appRoot.appendingPathComponent("snapshots") }
    static var backupsDir: URL { appRoot.appendingPathComponent("backups") }
    static var lockFile: URL { appRoot.appendingPathComponent(".lock") }
    static var appInstanceLockFile: URL { appRoot.appendingPathComponent(".app.lock") }

    static func snapshotDir(for id: AccountID) -> URL {
        snapshotsDir.appendingPathComponent(id, isDirectory: true)
    }

    /// 첫 실행 시 옛 `~/.ccmeter` 데이터를 새 경로로 1회 이동.
    /// 새 경로가 비어있지 않으면 skip (이미 마이그레이션 됨). 옛 경로가 없으면 skip (새 설치).
    /// 새 경로가 빈 디렉터리면 제거 후 rename (mkdir 만 된 상태일 수 있음).
    static func migrateLegacyAppRootIfNeeded() {
        let fm = FileManager.default
        let new = appRoot.path
        let old = legacyAppRoot.path
        guard fm.fileExists(atPath: old) else { return }
        if fm.fileExists(atPath: new) {
            let contents = (try? fm.contentsOfDirectory(atPath: new)) ?? []
            if !contents.isEmpty { return }
            try? fm.removeItem(atPath: new)
        }
        do {
            try fm.moveItem(atPath: old, toPath: new)
            Log.app.info("[MIGRATE] \(old) → \(new)")
        } catch {
            Log.app.error("[MIGRATE-FAIL] \(String(describing: error), privacy: .public)")
        }
    }
}
