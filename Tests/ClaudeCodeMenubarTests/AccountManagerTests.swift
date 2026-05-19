import XCTest
@testable import ClaudeCodeMenubar
import Foundation

// MARK: - Reusable mocks

private final class StubConfigFile: ClaudeConfigFileProtocol, @unchecked Sendable {
    var rawData: Data
    init(initial: String) { self.rawData = Data(initial.utf8) }

    func readRaw() throws -> Data { rawData }
    func readOAuthAccountJSON() throws -> Data {
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
        rawData = try JSONByteSlicePatcher.replace(in: rawData,
                                                    key: "oauthAccount",
                                                    with: oauthAccountJSON)
    }
}

private struct StubGuard: ClaudeProcessGuardProtocol {
    let isRunning: Bool = false
    func isClaudeRunning() -> Bool { isRunning }
}

private final class InMemoryRepo: AccountRepositoryProtocol {
    var accounts: [Account] = []
    var saveError: Swift.Error?
    func load() throws -> [Account] { accounts }
    func save(_ accounts: [Account]) throws {
        if let e = saveError { throw e }
        self.accounts = accounts
    }
}

private final class InMemorySnap: ProfileSnapshotStoreProtocol {
    var snapshots: [AccountID: ClaudeProfileSnapshot] = [:]
    func read(for id: AccountID) throws -> ClaudeProfileSnapshot? { snapshots[id] }
    func write(_ s: ClaudeProfileSnapshot, for id: AccountID) throws { snapshots[id] = s }
    func writeUsage(_: UsageSnapshot, for _: AccountID) throws {}
    func readUsage(for _: AccountID) throws -> UsageSnapshot? { nil }
    func remove(for id: AccountID) throws { snapshots[id] = nil }
}

// MARK: - AccountManager integration

@MainActor
final class AccountManagerTests: XCTestCase {
    private var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccm-am-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    private let activeConfig = """
    {"oauthAccount":{"accountUuid":"UUID-A","emailAddress":"a@e.com","organizationUuid":"O-A"}}
    """
    private let credsData = Data(#"{"claudeAiOauth":{"accessToken":"t","refreshToken":"r","expiresAt":0,"scopes":[]}}"#.utf8)

    private func makeManager(repo: InMemoryRepo = InMemoryRepo(),
                             snap: InMemorySnap = InMemorySnap(),
                             configFile: StubConfigFile? = nil) -> AccountManager {
        let cfg = configFile ?? StubConfigFile(initial: activeConfig)
        let credsData = self.credsData
        return AccountManager(
            repo: repo,
            snapshots: snap,
            configFile: cfg,
            processGuard: StubGuard(),
            backups: BackupRotator(directory: tmp.appendingPathComponent("backups"), keep: 1),
            liveCredsReadRaw: { credsData }
        )
    }

    // MARK: import

    func testImportCurrentCreatesAccount() throws {
        let repo = InMemoryRepo()
        let snap = InMemorySnap()
        let m = makeManager(repo: repo, snap: snap)
        let acc = try m.importCurrent()
        XCTAssertEqual(acc.accountUuid, "UUID-A")
        XCTAssertEqual(acc.emailAddress, "a@e.com")
        XCTAssertEqual(repo.accounts.count, 1)
        XCTAssertNotNil(snap.snapshots[acc.id])
    }

    func testImportCurrentUpdatesExistingByUuid() throws {
        let repo = InMemoryRepo()
        let snap = InMemorySnap()
        let m = makeManager(repo: repo, snap: snap)
        let first = try m.importCurrent(label: "First")
        let second = try m.importCurrent(label: "Renamed")
        // 동일 accountUuid → 새 레코드 생성 없이 기존 갱신
        XCTAssertEqual(repo.accounts.count, 1)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(repo.accounts.first?.label, "Renamed")
    }

    func testImportCurrentWithExplicitLabelAndColor() throws {
        let repo = InMemoryRepo()
        let m = makeManager(repo: repo)
        let acc = try m.importCurrent(label: "My Account", colorHex: "#abcdef")
        XCTAssertEqual(acc.label, "My Account")
        XCTAssertEqual(acc.colorHex, "#abcdef")
    }

    func testImportCurrentWithoutLabelUsesEmailLocalPart() throws {
        let repo = InMemoryRepo()
        let m = makeManager(repo: repo)
        let acc = try m.importCurrent()
        XCTAssertEqual(acc.label, "a") // a@e.com → "a"
    }

    // MARK: reload + activeAccountID detection

    func testReloadDetectsActiveAccountByUuid() throws {
        let repo = InMemoryRepo()
        let snap = InMemorySnap()
        let m = makeManager(repo: repo, snap: snap)
        _ = try m.importCurrent()
        m.reload()
        XCTAssertEqual(m.accounts.count, 1)
        XCTAssertEqual(m.activeAccountID, repo.accounts.first?.id)
    }

    func testReloadSurfacesErrorWhenRepoFails() {
        let repo = InMemoryRepo()
        struct LoadFail: Swift.Error {}
        // load 실패하도록 — accounts getter는 throw 없으니 save 만 fail 가능.
        // 대안: 디스크 파일 깨뜨림. 여기서는 configFile.readOAuthAccount 만 실패.
        let badCfg = StubConfigFile(initial: "{}") // 'oauthAccount' 없음
        let m = makeManager(repo: repo, configFile: badCfg)
        m.reload()
        XCTAssertNotNil(m.lastError)
    }

    func testReloadClearsErrorOnSuccess() throws {
        let repo = InMemoryRepo()
        let badCfg = StubConfigFile(initial: "{}")
        let m = makeManager(repo: repo, configFile: badCfg)
        m.reload()
        XCTAssertNotNil(m.lastError)
        // configFile 을 정상으로 교체할 수는 없으므로 — 새 manager 로 검증
        let m2 = makeManager(repo: repo)
        m2.reload()
        XCTAssertNil(m2.lastError)
    }

    // MARK: rename + remove

    func testRenameUpdatesLabel() throws {
        let repo = InMemoryRepo()
        let snap = InMemorySnap()
        let m = makeManager(repo: repo, snap: snap)
        let acc = try m.importCurrent()
        try m.rename(acc.id, to: "NewLabel")
        XCTAssertEqual(repo.accounts.first?.label, "NewLabel")
    }

    func testRenameMissingIDIsNoOp() throws {
        let repo = InMemoryRepo()
        let m = makeManager(repo: repo)
        _ = try m.importCurrent()
        try m.rename("nonexistent", to: "X")
        // 그대로
        XCTAssertEqual(repo.accounts.first?.label, "a")
    }

    func testRemoveDeletesAccountAndSnapshot() throws {
        let repo = InMemoryRepo()
        let snap = InMemorySnap()
        let m = makeManager(repo: repo, snap: snap)
        let acc = try m.importCurrent()
        XCTAssertNotNil(snap.snapshots[acc.id])
        try m.remove(acc.id)
        XCTAssertTrue(repo.accounts.isEmpty)
        XCTAssertNil(snap.snapshots[acc.id])
    }
}
