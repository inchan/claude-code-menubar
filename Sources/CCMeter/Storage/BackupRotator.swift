import Foundation

/// 활성 자료 timestamp 백업 보관. 최근 N개만 유지.
struct BackupRotator {
    let directory: URL
    let keep: Int

    enum Label: String, CaseIterable {
        case claudeConfigOAuthAccount = "claude-config-oauthAccount"
        case claudeCredentials = "claude-credentials"
    }

    init(directory: URL = Paths.backupsDir, keep: Int = 5) {
        self.directory = directory
        self.keep = keep
    }

    @discardableResult
    func write(label: Label, data: Data) throws -> URL {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        // ms + UUID8 suffix 로 동일 ms 충돌도 회피
        let stamp = Self.timestampFormatter.string(from: Date())
        let unique = String(UUID().uuidString.prefix(8))
        let url = directory.appendingPathComponent("\(label.rawValue).\(stamp).\(unique).bak")
        try AtomicFileWriter.write(data, to: url, permissions: 0o600)
        try rotate(prefix: label.rawValue)
        return url
    }

    private func rotate(prefix: String) throws {
        let entries = try FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)
        let backups = entries
            .filter { $0.lastPathComponent.hasPrefix("\(prefix).") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for stale in backups.dropFirst(keep) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"  // ms 포함
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
