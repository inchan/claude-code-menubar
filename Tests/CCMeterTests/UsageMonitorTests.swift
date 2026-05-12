import XCTest
@testable import CCMeter
import Foundation

// MARK: - Mocks

private final class MockUsageClient: UsageClientProtocol, @unchecked Sendable {
    enum Mode {
        case success(UsageSnapshot)
        case unauthorized
        case rateLimited(retry: TimeInterval?)
        case error(Swift.Error)
    }
    var mode: Mode
    var lastToken: String?
    private(set) var callCount = 0
    init(mode: Mode) { self.mode = mode }

    func fetch(accessToken: String) async throws -> UsageSnapshot {
        callCount += 1
        lastToken = accessToken
        switch mode {
        case .success(let s): return s
        case .unauthorized: throw UsageClientError.unauthorized
        case .rateLimited(let r): throw UsageClientError.rateLimited(retryAfter: r)
        case .error(let e): throw e
        }
    }
}

private final class InMemorySnap: ProfileSnapshotStoreProtocol {
    var snapshots: [AccountID: ClaudeProfileSnapshot] = [:]
    var usages: [AccountID: UsageSnapshot] = [:]
    func read(for id: AccountID) throws -> ClaudeProfileSnapshot? { snapshots[id] }
    func write(_ s: ClaudeProfileSnapshot, for id: AccountID) throws { snapshots[id] = s }
    func writeUsage(_ u: UsageSnapshot, for id: AccountID) throws { usages[id] = u }
    func readUsage(for id: AccountID) throws -> UsageSnapshot? { usages[id] }
    func remove(for id: AccountID) throws { snapshots[id] = nil; usages[id] = nil }
}

private final class InMemoryRepo: AccountRepositoryProtocol {
    var accounts: [Account] = []
    func load() throws -> [Account] { accounts }
    func save(_ accounts: [Account]) throws { self.accounts = accounts }
}

private struct StubGuard: ClaudeProcessGuardProtocol {
    func isClaudeRunning() -> Bool { false }
}

private final class StubConfigFile: ClaudeConfigFileProtocol, @unchecked Sendable {
    var rawData: Data
    init(json: String) { self.rawData = Data(json.utf8) }
    func readRaw() throws -> Data { rawData }
    func readOAuthAccountJSON() throws -> Data {
        guard let r = try JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              let o = r["oauthAccount"] else {
            throw ClaudeConfigError.missingOAuthAccount
        }
        return try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])
    }
    func readOAuthAccount() throws -> ClaudeOAuthAccount {
        try JSON.decode(ClaudeOAuthAccount.self, from: readOAuthAccountJSON())
    }
    func patchOAuthAccount(_: Data) throws {}
}

private final class StubClock: ClockProtocol, @unchecked Sendable {
    var current: Date
    init(_ d: Date = Date(timeIntervalSince1970: 1_700_000_000)) { self.current = d }
    func now() -> Date { current }
}

// MARK: - UsageMonitor tests

@MainActor
final class UsageMonitorTests: XCTestCase {
    private var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccm-mon-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    private let activeConfig = """
    {"oauthAccount":{"accountUuid":"UUID-A","emailAddress":"a@e.com","organizationUuid":"O-A"}}
    """
    private let credsJSON = #"{"claudeAiOauth":{"accessToken":"TOK-LIVE","refreshToken":"r","expiresAt":0,"scopes":[]}}"#

    private func makeEnv(clientMode: MockUsageClient.Mode) ->
        (am: AccountManager, mon: UsageMonitor, repo: InMemoryRepo,
         snap: InMemorySnap, client: MockUsageClient, settings: SettingsStore) {
        let repo = InMemoryRepo()
        let snap = InMemorySnap()
        let cfg = StubConfigFile(json: activeConfig)
        let credsData = Data(credsJSON.utf8)
        let am = AccountManager(
            repo: repo, snapshots: snap,
            configFile: cfg, processGuard: StubGuard(),
            backups: BackupRotator(directory: tmp.appendingPathComponent("b"), keep: 1),
            liveCredsReadRaw: { credsData }
        )
        _ = try? am.importCurrent()
        let client = MockUsageClient(mode: clientMode)
        let settings = SettingsStore(url: tmp.appendingPathComponent("settings.json"))
        let mon = UsageMonitor(accountManager: am,
                               client: client,
                               snapshotStore: snap,
                               settingsStore: settings,
                               clock: SystemClock(),
                               liveCredsReadRaw: { credsData })
        return (am, mon, repo, snap, client, settings)
    }

    private func successSnapshot() -> UsageSnapshot {
        UsageSnapshot(fiveHourUtilization: 50, fiveHourResetsAt: Date(timeIntervalSince1970: 1),
                      sevenDayUtilization: 20, sevenDayResetsAt: Date(timeIntervalSince1970: 2),
                      fetchedAt: Date())
    }

    // MARK: refresh active

    func testRefreshActiveSuccess() async throws {
        let snap = successSnapshot()
        let env = makeEnv(clientMode: .success(snap))
        await env.mon.refreshActiveOnce()
        let activeID = env.am.activeAccountID!
        XCTAssertEqual(env.mon.snapshots[activeID]?.fiveHourUtilization, 50)
        // 활성 계정은 live token 사용
        XCTAssertEqual(env.client.lastToken, "TOK-LIVE")
        XCTAssertEqual(env.mon.lastError[activeID], nil)
    }

    func testRefreshUnauthorizedSetsBackoffAndError() async {
        let env = makeEnv(clientMode: .unauthorized)
        await env.mon.refreshActiveOnce()
        let id = env.am.activeAccountID!
        XCTAssertEqual(env.mon.lastError[id], "unauthorized")
        // 다음 refresh 는 backoff 로 skip → callCount 증가 없음
        let before = env.client.callCount
        await env.mon.refreshActiveOnce()
        XCTAssertEqual(env.client.callCount, before)
    }

    func testRefreshRateLimitedRespected() async {
        let env = makeEnv(clientMode: .rateLimited(retry: 90))
        await env.mon.refreshActiveOnce()
        let id = env.am.activeAccountID!
        XCTAssertEqual(env.mon.lastError[id], "rate_limited")
    }

    func testRefreshGenericErrorSetsBackoff() async {
        struct Boom: Swift.Error {}
        let env = makeEnv(clientMode: .error(Boom()))
        await env.mon.refreshActiveOnce()
        let id = env.am.activeAccountID!
        XCTAssertNotNil(env.mon.lastError[id])
    }

    // MARK: invalidateBackoff

    func testInvalidateBackoffClearsErrorAndRetries() async {
        let env = makeEnv(clientMode: .unauthorized)
        await env.mon.refreshActiveOnce()
        let id = env.am.activeAccountID!
        XCTAssertNotNil(env.mon.lastError[id])

        // 다음 호출은 성공으로 응답
        env.client.mode = .success(successSnapshot())
        env.mon.invalidateBackoff(for: id)
        // invalidateBackoff 내부에서 Task 가 비동기로 refresh 호출 — 짧게 yield
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(env.mon.lastError[id], nil)
        XCTAssertEqual(env.mon.snapshots[id]?.fiveHourUtilization, 50)
    }

    // MARK: notification observer

    func testAccountChangedNotificationTriggersInvalidate() async {
        let env = makeEnv(clientMode: .success(successSnapshot()))
        let id = env.am.activeAccountID!
        NotificationCenter.default.post(
            name: .ccAccountChanged,
            object: nil,
            userInfo: ["accountID": id, "kind": CCAccountChangedKind.switched.rawValue]
        )
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(env.mon.snapshots[id]?.fiveHourUtilization, 50)
    }

    // MARK: refresh all + inactive

    func testRefreshAllOnceFetchesEveryAccount() async throws {
        let env = makeEnv(clientMode: .success(successSnapshot()))
        // 두 번째 계정의 snapshot 을 강제로 추가 (inactive)
        let acc2 = Account(id: "id-2", label: "B", emailAddress: "b@e.com",
                           accountUuid: "U-B", organizationUuid: "O-B", colorHex: "#0",
                           addedAt: Date(timeIntervalSince1970: 3), lastUsedAt: nil,
                           subscriptionType: nil)
        env.repo.accounts.append(acc2)
        env.snap.snapshots["id-2"] = ClaudeProfileSnapshot(
            oauthAccountJSON: Data(#"{"accountUuid":"U-B"}"#.utf8),
            credentialsJSON: Data(#"{"claudeAiOauth":{"accessToken":"INACTIVE-TOK","refreshToken":"r","expiresAt":0,"scopes":[]}}"#.utf8)
        )
        env.am.reload()
        await env.mon.refreshAllOnce()
        XCTAssertEqual(env.mon.snapshots[env.am.activeAccountID!]?.fiveHourUtilization, 50)
        XCTAssertEqual(env.mon.snapshots["id-2"]?.fiveHourUtilization, 50)
    }

    // MARK: start / stop / teardown

    func testStartStopTeardownDoesNotCrash() async {
        let env = makeEnv(clientMode: .success(successSnapshot()))
        env.mon.start()
        env.mon.stop()
        env.mon.start()
        env.mon.teardown()
    }

    // MARK: cached snapshot load on account list change

    func testNewAccountAddedReloadsCachedUsage() async throws {
        let env = makeEnv(clientMode: .success(successSnapshot()))
        // 새 계정 추가 + 해당 usage snapshot 디스크에 존재
        let acc2 = Account(id: "id-2", label: "B", emailAddress: "b@e.com",
                           accountUuid: "U-B", organizationUuid: "O-B", colorHex: "#0",
                           addedAt: Date(timeIntervalSince1970: 3), lastUsedAt: nil,
                           subscriptionType: nil)
        env.repo.accounts.append(acc2)
        env.snap.usages["id-2"] = UsageSnapshot(
            fiveHourUtilization: 33, fiveHourResetsAt: nil,
            sevenDayUtilization: nil, sevenDayResetsAt: nil,
            fetchedAt: Date()
        )
        env.am.reload() // accounts $Published → observeAccountListChanges → loadCachedSnapshots
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(env.mon.snapshots["id-2"]?.fiveHourUtilization, 33)
    }

    func testRemovedAccountPrunesSnapshots() async throws {
        let env = makeEnv(clientMode: .success(successSnapshot()))
        let id = env.am.activeAccountID!
        await env.mon.refreshActiveOnce()
        XCTAssertNotNil(env.mon.snapshots[id])
        // 계정 삭제
        try env.am.remove(id)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(env.mon.snapshots[id])
    }
}
