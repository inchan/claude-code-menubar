import XCTest
@testable import CCMeter
import Foundation

// MARK: - In-memory mocks

private final class MockClaudeConfigFile: ClaudeConfigFileProtocol, @unchecked Sendable {
    var rawData: Data
    var patchError: Swift.Error?
    var readJSONError: Swift.Error?

    init(initial: String) {
        self.rawData = Data(initial.utf8)
    }

    func readRaw() throws -> Data { rawData }

    func readOAuthAccountJSON() throws -> Data {
        if let e = readJSONError { throw e }
        guard let root = try JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              let oauth = root["oauthAccount"] else {
            throw ClaudeConfigError.missingOAuthAccount
        }
        return try JSONSerialization.data(withJSONObject: oauth, options: [.sortedKeys])
    }

    func readOAuthAccount() throws -> ClaudeOAuthAccount {
        try JSON.decode(ClaudeOAuthAccount.self, from: readOAuthAccountJSON())
    }

    func patchOAuthAccount(_ oauthAccountJSON: Data) throws {
        if let e = patchError { throw e }
        rawData = try JSONByteSlicePatcher.replace(in: rawData,
                                                    key: "oauthAccount",
                                                    with: oauthAccountJSON)
    }
}

private final class MockClaudeCredentialsFile: ClaudeCredentialsFileProtocol, @unchecked Sendable {
    var rawData: Data
    var writeError: Swift.Error?

    init(initial: Data) { self.rawData = initial }

    func readRaw() throws -> Data { rawData }
    func read() throws -> ClaudeCredentialsRoot {
        try JSON.decode(ClaudeCredentialsRoot.self, from: rawData)
    }
    func writeRaw(_ data: Data) throws {
        if let e = writeError { throw e }
        rawData = data
    }
}

private struct MockProcessGuard: ClaudeProcessGuardProtocol {
    let isRunning: Bool
    func isClaudeRunning() -> Bool { isRunning }
}

private final class InMemoryAccountRepo: AccountRepositoryProtocol {
    var accounts: [Account] = []
    func load() throws -> [Account] { accounts }
    func save(_ accounts: [Account]) throws { self.accounts = accounts }
}

private final class InMemorySnapshotStore: ProfileSnapshotStoreProtocol {
    var snapshots: [AccountID: ClaudeProfileSnapshot] = [:]
    var usages: [AccountID: UsageSnapshot] = [:]

    func read(for id: AccountID) throws -> ClaudeProfileSnapshot? { snapshots[id] }
    func write(_ snapshot: ClaudeProfileSnapshot, for id: AccountID) throws {
        snapshots[id] = snapshot
    }
    func writeUsage(_ usage: UsageSnapshot, for id: AccountID) throws {
        usages[id] = usage
    }
    func readUsage(for id: AccountID) throws -> UsageSnapshot? { usages[id] }
    func remove(for id: AccountID) throws {
        snapshots[id] = nil
        usages[id] = nil
    }
}

// MARK: - SwitchTransaction integration

final class SwitchTransactionIntegrationTests: XCTestCase {
    private var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccm-switch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    private let activeConfigJSON = """
    {"a":1,"oauthAccount":{"accountUuid":"OLD","emailAddress":"o@e","organizationUuid":"OO"},"b":2}
    """

    private let activeCredsJSON = #"{"claudeAiOauth":{"accessToken":"OLD-T","refreshToken":"OLD-R","expiresAt":111,"scopes":[]}}"#

    private let targetOauthJSON = #"{"accountUuid":"NEW","emailAddress":"n@e","organizationUuid":"NN"}"#

    private let targetCredsJSON = #"{"claudeAiOauth":{"accessToken":"NEW-T","refreshToken":"NEW-R","expiresAt":222,"scopes":[]}}"#

    private func makeTx(claudeRunning: Bool = false,
                        keychainBoxBox: (Data?) -> Void = { _ in },
                        target: ClaudeProfileSnapshot? = nil,
                        existingAccountForOld: Bool = true)
        -> (tx: SwitchTransaction,
            cfg: MockClaudeConfigFile,
            cred: MockClaudeCredentialsFile,
            snap: InMemorySnapshotStore,
            repo: InMemoryAccountRepo,
            kc: KeychainBox,
            backupDir: URL) {
        let cfg = MockClaudeConfigFile(initial: activeConfigJSON)
        let cred = MockClaudeCredentialsFile(initial: Data(activeCredsJSON.utf8))
        let snap = InMemorySnapshotStore()
        let repo = InMemoryAccountRepo()
        let backupDir = tmp.appendingPathComponent("backups", isDirectory: true)
        let lockPath = tmp.appendingPathComponent(".lock").path
        if existingAccountForOld {
            repo.accounts = [
                Account(id: "old-id", label: "old", emailAddress: "o@e",
                        accountUuid: "OLD", organizationUuid: "OO", colorHex: "#000000",
                        addedAt: Date(timeIntervalSince1970: 1), lastUsedAt: nil,
                        subscriptionType: nil),
                Account(id: "new-id", label: "new", emailAddress: "n@e",
                        accountUuid: "NEW", organizationUuid: "NN", colorHex: "#000000",
                        addedAt: Date(timeIntervalSince1970: 2), lastUsedAt: nil,
                        subscriptionType: nil)
            ]
        }
        if let target {
            snap.snapshots["new-id"] = target
        }
        let kc = KeychainBox(data: Data(activeCredsJSON.utf8))
        let tx = SwitchTransaction(
            configFile: cfg,
            credFile: cred,
            snapshotStore: snap,
            backups: BackupRotator(directory: backupDir, keep: 3),
            processGuard: MockProcessGuard(isRunning: claudeRunning),
            accountRepo: repo,
            keychainWrite: { [kc] in try kc.set($0) },
            keychainReadRaw: { [kc] in kc.get() },
            liveCredsReadRaw: { [kc] in kc.get() ?? Data() },
            lockFilePath: lockPath
        )
        return (tx, cfg, cred, snap, repo, kc, backupDir)
    }

    // 키체인 mock box — closure capture 용
    final class KeychainBox: @unchecked Sendable {
        private var value: Data?
        private let lock = NSLock()
        var writeError: Swift.Error?
        init(data: Data?) { self.value = data }
        func set(_ d: Data) throws {
            if let e = writeError { throw e }
            lock.lock(); defer { lock.unlock() }
            value = d
        }
        func get() -> Data? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    private func targetSnapshot() -> ClaudeProfileSnapshot {
        ClaudeProfileSnapshot(oauthAccountJSON: Data(targetOauthJSON.utf8),
                              credentialsJSON: Data(targetCredsJSON.utf8))
    }

    // MARK: success

    func testSuccessfulSwitchUpdatesAllSurfaces() throws {
        let e = makeTx(target: targetSnapshot())
        try e.tx.execute(targetID: "new-id")

        // config file 의 oauthAccount 영역이 NEW 로 교체
        XCTAssertTrue(String(data: e.cfg.rawData, encoding: .utf8)!.contains("NEW"))
        // credentials file 이 새 토큰
        XCTAssertEqual(e.cred.rawData, Data(targetCredsJSON.utf8))
        // keychain 도 같이 갱신
        XCTAssertEqual(e.kc.get(), Data(targetCredsJSON.utf8))
        // lastUsedAt 갱신됨
        let newAcc = e.repo.accounts.first { $0.id == "new-id" }!
        XCTAssertNotNil(newAcc.lastUsedAt)
        // 기존 active 스냅샷 백업 (active=old-id) 도 갱신
        XCTAssertNotNil(e.snap.snapshots["old-id"])
    }

    // MARK: guard

    func testClaudeRunningThrows() {
        let e = makeTx(claudeRunning: true, target: targetSnapshot())
        XCTAssertThrowsError(try e.tx.execute(targetID: "new-id")) { err in
            guard case SwitchError.claudeRunning = err else {
                return XCTFail("unexpected: \(err)")
            }
        }
        // config 가 바뀌지 않았어야 함
        XCTAssertTrue(String(data: e.cfg.rawData, encoding: .utf8)!.contains("OLD"))
    }

    func testAllowWhileClaudeRunningBypasses() throws {
        let e = makeTx(claudeRunning: true, target: targetSnapshot())
        try e.tx.execute(targetID: "new-id", allowWhileClaudeRunning: true)
        XCTAssertTrue(String(data: e.cfg.rawData, encoding: .utf8)!.contains("NEW"))
    }

    // MARK: target missing

    func testTargetNotFoundThrows() {
        let e = makeTx(target: nil)
        XCTAssertThrowsError(try e.tx.execute(targetID: "new-id")) { err in
            guard case SwitchError.targetNotFound(let id) = err else {
                return XCTFail("unexpected: \(err)")
            }
            XCTAssertEqual(id, "new-id")
        }
    }

    func testCorruptTargetCredentialsThrows() {
        let bad = ClaudeProfileSnapshot(oauthAccountJSON: Data(targetOauthJSON.utf8),
                                        credentialsJSON: Data("not json".utf8))
        let e = makeTx(target: bad)
        XCTAssertThrowsError(try e.tx.execute(targetID: "new-id"))
    }

    func testCorruptTargetOauthThrows() {
        let bad = ClaudeProfileSnapshot(oauthAccountJSON: Data("not json".utf8),
                                        credentialsJSON: Data(targetCredsJSON.utf8))
        let e = makeTx(target: bad)
        XCTAssertThrowsError(try e.tx.execute(targetID: "new-id"))
    }

    // MARK: noActiveProfile (live read fails)

    func testNoActiveProfileWhenLiveReadFails() {
        let cfg = MockClaudeConfigFile(initial: activeConfigJSON)
        let cred = MockClaudeCredentialsFile(initial: Data(activeCredsJSON.utf8))
        let snap = InMemorySnapshotStore()
        snap.snapshots["new-id"] = targetSnapshot()
        let repo = InMemoryAccountRepo()
        repo.accounts = [
            Account(id: "new-id", label: "new", emailAddress: "n@e",
                    accountUuid: "NEW", organizationUuid: "NN", colorHex: "#0",
                    addedAt: Date(), lastUsedAt: nil, subscriptionType: nil)
        ]
        struct LiveError: Swift.Error {}
        let targetCreds = Data(targetCredsJSON.utf8)
        let backupDir = tmp.appendingPathComponent("b")
        let lockPath = tmp.appendingPathComponent(".lock").path
        let tx = SwitchTransaction(
            configFile: cfg, credFile: cred, snapshotStore: snap,
            backups: BackupRotator(directory: backupDir, keep: 1),
            processGuard: MockProcessGuard(isRunning: false),
            accountRepo: repo,
            keychainWrite: { _ in }, keychainReadRaw: { targetCreds },
            liveCredsReadRaw: { throw LiveError() },
            lockFilePath: lockPath
        )
        XCTAssertThrowsError(try tx.execute(targetID: "new-id")) { err in
            guard case SwitchError.noActiveProfile = err else {
                return XCTFail("unexpected: \(err)")
            }
        }
    }

    // MARK: verification failures + rollback

    func testKeychainReadbackMissingTriggersRollback() throws {
        let cfg = MockClaudeConfigFile(initial: activeConfigJSON)
        let cred = MockClaudeCredentialsFile(initial: Data(activeCredsJSON.utf8))
        let snap = InMemorySnapshotStore()
        snap.snapshots["new-id"] = targetSnapshot()
        let repo = InMemoryAccountRepo()
        repo.accounts = [
            Account(id: "new-id", label: "new", emailAddress: "n@e",
                    accountUuid: "NEW", organizationUuid: "NN", colorHex: "#0",
                    addedAt: Date(), lastUsedAt: nil, subscriptionType: nil)
        ]
        let activeData = Data(activeCredsJSON.utf8)
        let backupDir = tmp.appendingPathComponent("b")
        let lockPath = tmp.appendingPathComponent(".lock").path
        let tx = SwitchTransaction(
            configFile: cfg, credFile: cred, snapshotStore: snap,
            backups: BackupRotator(directory: backupDir, keep: 1),
            processGuard: MockProcessGuard(isRunning: false),
            accountRepo: repo,
            keychainWrite: { _ in },
            keychainReadRaw: { nil }, // <- 검증에서 실패
            liveCredsReadRaw: { activeData },
            lockFilePath: lockPath
        )
        XCTAssertThrowsError(try tx.execute(targetID: "new-id")) { err in
            guard case SwitchError.verificationFailed(let m) = err else {
                return XCTFail("unexpected: \(err)")
            }
            XCTAssertTrue(m.contains("keychain"))
        }
        XCTAssertTrue(String(data: cfg.rawData, encoding: .utf8)!.contains("OLD"))
    }

    func testKeychainExpiresAtMismatchTriggersRollback() throws {
        let cfg = MockClaudeConfigFile(initial: activeConfigJSON)
        let cred = MockClaudeCredentialsFile(initial: Data(activeCredsJSON.utf8))
        let snap = InMemorySnapshotStore()
        snap.snapshots["new-id"] = targetSnapshot()
        let repo = InMemoryAccountRepo()
        repo.accounts = [
            Account(id: "new-id", label: "new", emailAddress: "n@e",
                    accountUuid: "NEW", organizationUuid: "NN", colorHex: "#0",
                    addedAt: Date(), lastUsedAt: nil, subscriptionType: nil)
        ]
        let activeData = Data(activeCredsJSON.utf8)
        let backupDir = tmp.appendingPathComponent("b")
        let lockPath = tmp.appendingPathComponent(".lock").path
        let tx = SwitchTransaction(
            configFile: cfg, credFile: cred, snapshotStore: snap,
            backups: BackupRotator(directory: backupDir, keep: 1),
            processGuard: MockProcessGuard(isRunning: false),
            accountRepo: repo,
            keychainWrite: { _ in /* no-op */ },
            keychainReadRaw: { activeData },
            liveCredsReadRaw: { activeData },
            lockFilePath: lockPath
        )
        XCTAssertThrowsError(try tx.execute(targetID: "new-id")) { err in
            guard case SwitchError.verificationFailed(let m) = err else {
                return XCTFail("unexpected: \(err)")
            }
            XCTAssertTrue(m.contains("keychain"))
        }
        XCTAssertEqual(cred.rawData, Data(activeCredsJSON.utf8))
    }

    func testCredFileWriteFailureTriggersRollback() {
        let cfg = MockClaudeConfigFile(initial: activeConfigJSON)
        let cred = MockClaudeCredentialsFile(initial: Data(activeCredsJSON.utf8))
        struct WriteFail: Swift.Error {}
        cred.writeError = WriteFail()
        let snap = InMemorySnapshotStore()
        snap.snapshots["new-id"] = targetSnapshot()
        let repo = InMemoryAccountRepo()
        repo.accounts = [
            Account(id: "new-id", label: "new", emailAddress: "n@e",
                    accountUuid: "NEW", organizationUuid: "NN", colorHex: "#0",
                    addedAt: Date(), lastUsedAt: nil, subscriptionType: nil)
        ]
        let activeData = Data(activeCredsJSON.utf8)
        let targetData = Data(targetCredsJSON.utf8)
        let backupDir = tmp.appendingPathComponent("b")
        let lockPath = tmp.appendingPathComponent(".lock").path
        let tx = SwitchTransaction(
            configFile: cfg, credFile: cred, snapshotStore: snap,
            backups: BackupRotator(directory: backupDir, keep: 1),
            processGuard: MockProcessGuard(isRunning: false),
            accountRepo: repo,
            keychainWrite: { _ in },
            keychainReadRaw: { targetData },
            liveCredsReadRaw: { activeData },
            lockFilePath: lockPath
        )
        XCTAssertThrowsError(try tx.execute(targetID: "new-id")) { err in
            guard case SwitchError.underlying = err else {
                return XCTFail("unexpected: \(err)")
            }
        }
        XCTAssertTrue(String(data: cfg.rawData, encoding: .utf8)!.contains("OLD"))
    }
}
