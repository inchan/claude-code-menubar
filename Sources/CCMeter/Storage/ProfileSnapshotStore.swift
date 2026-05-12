import Foundation

protocol ProfileSnapshotStoreProtocol: AnyObject {
    func read(for id: AccountID) throws -> ClaudeProfileSnapshot?
    func write(_ snapshot: ClaudeProfileSnapshot, for id: AccountID) throws
    func writeUsage(_ usage: UsageSnapshot, for id: AccountID) throws
    func readUsage(for id: AccountID) throws -> UsageSnapshot?
    func remove(for id: AccountID) throws
}

final class ProfileSnapshotStore: ProfileSnapshotStoreProtocol {
    private let configFileName = "claude-config.json"
    private let credentialsFileName = "claude-credentials.json"
    private let usageFileName = "usage.json"
    private let root: URL

    init(root: URL = Paths.snapshotsDir) { self.root = root }

    private func dir(for id: AccountID) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    func read(for id: AccountID) throws -> ClaudeProfileSnapshot? {
        let dir = dir(for: id)
        let configURL = dir.appendingPathComponent(configFileName)
        let credURL = dir.appendingPathComponent(credentialsFileName)
        guard FileManager.default.fileExists(atPath: configURL.path),
              FileManager.default.fileExists(atPath: credURL.path) else {
            return nil
        }
        let configData = try Data(contentsOf: configURL)
        let credData = try Data(contentsOf: credURL)
        return ClaudeProfileSnapshot(oauthAccountJSON: configData, credentialsJSON: credData)
    }

    /// 두 파일 동시 커밋. staging tmp 두 개를 모두 성공적으로 작성한 뒤
    /// rename 두 번을 연속 호출. 첫 rename 성공 + 둘째 실패 시 첫 파일을 즉시 백업본으로 복원.
    func write(_ snapshot: ClaudeProfileSnapshot, for id: AccountID) throws {
        let dir = dir(for: id)
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])

        let configURL = dir.appendingPathComponent(configFileName)
        let credURL = dir.appendingPathComponent(credentialsFileName)

        // 기존 값 백업 (둘 중 하나라도 실패 시 복원용)
        let prevConfig = (try? Data(contentsOf: configURL))
        let prevCreds = (try? Data(contentsOf: credURL))

        do {
            try AtomicFileWriter.write(snapshot.oauthAccountJSON, to: configURL, permissions: 0o600)
            try AtomicFileWriter.write(snapshot.credentialsJSON, to: credURL, permissions: 0o600)
        } catch {
            // 부분 실패 복원
            if let prev = prevConfig {
                try? AtomicFileWriter.write(prev, to: configURL, permissions: 0o600)
            } else {
                try? FileManager.default.removeItem(at: configURL)
            }
            if let prev = prevCreds {
                try? AtomicFileWriter.write(prev, to: credURL, permissions: 0o600)
            } else {
                try? FileManager.default.removeItem(at: credURL)
            }
            throw error
        }
    }

    func writeUsage(_ usage: UsageSnapshot, for id: AccountID) throws {
        let dir = dir(for: id)
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let url = dir.appendingPathComponent(usageFileName)
        try AtomicFileWriter.write(JSON.encode(usage), to: url, permissions: 0o600)
    }

    func readUsage(for id: AccountID) throws -> UsageSnapshot? {
        let url = dir(for: id).appendingPathComponent(usageFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSON.decode(UsageSnapshot.self, from: data)
    }

    func remove(for id: AccountID) throws {
        let dir = dir(for: id)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }
}
