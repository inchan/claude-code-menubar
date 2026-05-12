import XCTest
@testable import CCMeter
import Foundation

/// 커버리지 확장 — Storage/Network/ClaudeIntegration 의 IO 의존 유닛.
/// 모든 디스크 접근은 temp 디렉토리, 네트워크는 URLProtocol mock 으로 격리.

// MARK: - Helpers

private func makeTempDir(prefix: String = "ccm-cov") -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func sampleAccount(id: String = "id-1", label: String = "x") -> Account {
    Account(id: id, label: label, emailAddress: "x@e.com",
            accountUuid: "u-\(id)", organizationUuid: "o", colorHex: "#000000",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastUsedAt: nil, subscriptionType: nil)
}

private func sampleSnapshot(oauth: String = #"{"accountUuid":"u-1"}"#,
                            creds: String = #"{"claudeAiOauth":{"accessToken":"t","refreshToken":"r","expiresAt":0,"scopes":[]}}"#) -> ClaudeProfileSnapshot {
    ClaudeProfileSnapshot(oauthAccountJSON: Data(oauth.utf8),
                          credentialsJSON: Data(creds.utf8))
}

// MARK: - Paths trivial

final class PathsTests: XCTestCase {
    func testAllPathsExposed() {
        XCTAssertFalse(Paths.home.path.isEmpty)
        XCTAssertTrue(Paths.claudeConfig.path.hasSuffix(".claude.json"))
        XCTAssertTrue(Paths.claudeCredentials.path.hasSuffix(".credentials.json"))
        XCTAssertTrue(Paths.appRoot.path.hasSuffix("/.ccmeter"))
        XCTAssertTrue(Paths.accountsFile.path.hasSuffix("/accounts.json"))
        XCTAssertTrue(Paths.settingsFile.path.hasSuffix("/settings.json"))
        XCTAssertTrue(Paths.snapshotsDir.path.hasSuffix("/snapshots"))
        XCTAssertTrue(Paths.backupsDir.path.hasSuffix("/backups"))
        XCTAssertTrue(Paths.lockFile.path.hasSuffix("/.lock"))
        XCTAssertTrue(Paths.appInstanceLockFile.path.hasSuffix("/.app.lock"))
        XCTAssertTrue(Paths.snapshotDir(for: "abc").path.hasSuffix("/snapshots/abc"))
    }
}

// MARK: - Clock

final class ClockTests: XCTestCase {
    func testSystemClockReturnsCurrentDate() {
        let c = SystemClock()
        let a = c.now()
        let b = c.now()
        XCTAssertLessThanOrEqual(a.timeIntervalSinceNow, 1)
        XCTAssertLessThanOrEqual(b.timeIntervalSince(a), 1)
    }
}

// MARK: - Log.mask

final class LogMaskTests: XCTestCase {
    func testNilMaskedAsPlaceholder() {
        XCTAssertEqual(Log.mask(nil), "<nil>")
        XCTAssertEqual(Log.mask(""), "<nil>")
    }
    func testNonEmptyMasked() {
        let m = Log.mask("supersecret")
        XCTAssertTrue(m.hasPrefix("<token:"))
        XCTAssertTrue(m.hasSuffix(">"))
        XCTAssertFalse(m.contains("supersecret"))
        // 같은 입력 → 같은 마스크
        XCTAssertEqual(Log.mask("a"), Log.mask("a"))
    }
}

// MARK: - Models extra coverage

final class ModelsLabelTests: XCTestCase {
    func testUsageDisplayModeLabels() {
        XCTAssertEqual(UsageDisplayMode.used.label, "사용 퍼센트")
        XCTAssertEqual(UsageDisplayMode.remaining.label, "남은 퍼센트")
    }
    func testUsageVisibilityLabels() {
        XCTAssertEqual(UsageVisibility.sessionOnly.label, "세션만")
        XCTAssertEqual(UsageVisibility.weeklyOnly.label, "주간만")
        XCTAssertEqual(UsageVisibility.both.label, "세션 + 주간")
    }
    func testMenuBarStyleLabels() {
        XCTAssertEqual(MenuBarStyle.percent.label, "숫자(%)")
        XCTAssertEqual(MenuBarStyle.progress.label, "진행률 바")
    }
    func testTimeFormatStyleLabels() {
        XCTAssertEqual(TimeFormatStyle.twelveHour.label, "12시간 (AM/PM)")
        XCTAssertEqual(TimeFormatStyle.twentyFourHour.label, "24시간")
    }
    func testUsageSnapshotEmpty() {
        let e = UsageSnapshot.empty
        XCTAssertEqual(e.fiveHourUtilization, 0)
        XCTAssertEqual(e.fiveHourLevel, .healthy)
        XCTAssertNil(e.sevenDayUtilization)
    }
    func testCCAccountChangedKindRawValues() {
        XCTAssertEqual(CCAccountChangedKind.imported.rawValue, "imported")
        XCTAssertEqual(CCAccountChangedKind.switched.rawValue, "switched")
        XCTAssertEqual(CCAccountChangedKind.removed.rawValue, "removed")
        XCTAssertEqual(CCAccountChangedKind.renamed.rawValue, "renamed")
    }
    func testNotificationName() {
        XCTAssertEqual(Notification.Name.ccAccountChanged.rawValue, "CCAccountChanged")
    }
}

// MARK: - JSON helper

final class JSONHelperTests: XCTestCase {
    struct S: Codable, Equatable { let a: Int; let b: String }

    func testEncodeDecodeRoundtrip() throws {
        let v = S(a: 1, b: "x")
        let data = try JSON.encode(v)
        let decoded = try JSON.decode(S.self, from: data)
        XCTAssertEqual(decoded, v)
    }

    func testDecodeInvalidThrows() {
        XCTAssertThrowsError(try JSON.decode(S.self, from: Data("not json".utf8)))
    }
}

// MARK: - AccountRepository (with url injection)

final class AccountRepositoryUnitTests: XCTestCase {
    private var tmp: URL!
    private var url: URL { tmp.appendingPathComponent("accounts.json") }
    private var repo: AccountRepository!

    override func setUp() {
        tmp = makeTempDir()
        repo = AccountRepository(url: url)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testLoadEmptyWhenFileMissing() throws {
        XCTAssertTrue(try repo.load().isEmpty)
    }

    func testSaveAndReload() throws {
        let acc = sampleAccount()
        try repo.save([acc])
        let loaded = try repo.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, acc.id)
    }

    func testLoadEmptyFileReturnsEmptyArray() throws {
        try Data().write(to: url)
        XCTAssertTrue(try repo.load().isEmpty)
    }

    func testSavePermissions() throws {
        try repo.save([sampleAccount()])
        let perm = (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        XCTAssertEqual(perm & 0o777, 0o600)
    }
}

// MARK: - SettingsStore (with url injection)

final class SettingsStoreUnitTests: XCTestCase {
    private var tmp: URL!
    private var url: URL { tmp.appendingPathComponent("settings.json") }
    private var store: SettingsStore!

    override func setUp() {
        tmp = makeTempDir()
        store = SettingsStore(url: url)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testLoadDefaultsWhenMissing() {
        let s = store.load()
        XCTAssertEqual(s.pollIntervalActiveSeconds, 60)
        XCTAssertEqual(s.usageDisplayMode, .used)
    }

    func testSaveAndLoad() throws {
        var s = AppSettings()
        s.thresholdWarning = 70
        s.menuBarStyle = .progress
        s.colorOverrides = ["healthy": "#abcdef"]
        try store.save(s)
        let loaded = store.load()
        XCTAssertEqual(loaded.thresholdWarning, 70)
        XCTAssertEqual(loaded.menuBarStyle, .progress)
        XCTAssertEqual(loaded.colorOverrides["healthy"], "#abcdef")
    }

    func testCorruptFileFallsBackToDefaults() throws {
        try Data("not json".utf8).write(to: url)
        let s = store.load()
        XCTAssertEqual(s.thresholdWarning, 80) // default
    }
}

// MARK: - AppSettingsStore (@MainActor)

final class AppSettingsStoreTests: XCTestCase {
    private func env() -> (tmp: URL, store: AppSettingsStore, inner: SettingsStore) {
        let tmp = makeTempDir()
        let inner = SettingsStore(url: tmp.appendingPathComponent("settings.json"))
        let store = MainActor.assumeIsolated { AppSettingsStore(store: inner) }
        return (tmp, store, inner)
    }

    @MainActor
    func testInitialSettingsAreDefaults() {
        let e = env(); defer { try? FileManager.default.removeItem(at: e.tmp) }
        XCTAssertEqual(e.store.settings.usageDisplayMode, .used)
    }

    @MainActor
    func testSetDisplayModePersists() throws {
        let e = env(); defer { try? FileManager.default.removeItem(at: e.tmp) }
        e.store.setDisplayMode(.remaining)
        XCTAssertEqual(e.store.settings.usageDisplayMode, .remaining)
        XCTAssertEqual(e.inner.load().usageDisplayMode, .remaining)
    }

    @MainActor
    func testSetVisibilityAndStylePersists() {
        let e = env(); defer { try? FileManager.default.removeItem(at: e.tmp) }
        e.store.setVisibility(.weeklyOnly)
        e.store.setMenuBarStyle(.progress)
        e.store.setTimeFormat(.twentyFourHour)
        XCTAssertEqual(e.store.settings.usageVisibility, .weeklyOnly)
        XCTAssertEqual(e.store.settings.menuBarStyle, .progress)
        XCTAssertEqual(e.store.settings.timeFormat, .twentyFourHour)
    }

    @MainActor
    func testSetLaunchAtLogin() {
        let e = env(); defer { try? FileManager.default.removeItem(at: e.tmp) }
        e.store.setLaunchAtLogin(true)
        XCTAssertTrue(e.store.settings.launchAtLogin)
        e.store.setLaunchAtLogin(false)
        XCTAssertFalse(e.store.settings.launchAtLogin)
    }

    @MainActor
    func testColorOverridesAddAndRemove() {
        let e = env(); defer { try? FileManager.default.removeItem(at: e.tmp) }
        e.store.setColorOverride(.warning, hex: "#123456")
        XCTAssertEqual(e.store.settings.colorOverrides["warning"], "#123456")
        e.store.setColorOverride(.warning, hex: nil)
        XCTAssertNil(e.store.settings.colorOverrides["warning"])
    }

    @MainActor
    func testResetColorOverrides() {
        let e = env(); defer { try? FileManager.default.removeItem(at: e.tmp) }
        e.store.setColorOverride(.healthy, hex: "#000000")
        e.store.setColorOverride(.critical, hex: "#ffffff")
        e.store.resetColorOverrides()
        XCTAssertTrue(e.store.settings.colorOverrides.isEmpty)
    }
}

// MARK: - ProfileSnapshotStore (with root injection)

final class ProfileSnapshotStoreUnitTests: XCTestCase {
    private var tmp: URL!
    private var store: ProfileSnapshotStore!

    override func setUp() {
        tmp = makeTempDir()
        store = ProfileSnapshotStore(root: tmp)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testReadMissingReturnsNil() throws {
        XCTAssertNil(try store.read(for: "missing"))
        XCTAssertNil(try store.readUsage(for: "missing"))
    }

    func testWriteAndReadProfile() throws {
        let snap = sampleSnapshot()
        try store.write(snap, for: "a")
        let loaded = try store.read(for: "a")
        XCTAssertEqual(loaded?.oauthAccountJSON, snap.oauthAccountJSON)
        XCTAssertEqual(loaded?.credentialsJSON, snap.credentialsJSON)
    }

    func testWriteUsageAndReadback() throws {
        let usage = UsageSnapshot(fiveHourUtilization: 42, fiveHourResetsAt: nil,
                                  sevenDayUtilization: 10, sevenDayResetsAt: nil,
                                  fetchedAt: Date(timeIntervalSince1970: 1))
        try store.writeUsage(usage, for: "a")
        let loaded = try store.readUsage(for: "a")
        XCTAssertEqual(loaded?.fiveHourUtilization, 42)
        XCTAssertEqual(loaded?.sevenDayUtilization, 10)
    }

    func testRemoveDeletesDirectory() throws {
        try store.write(sampleSnapshot(), for: "a")
        XCTAssertNotNil(try store.read(for: "a"))
        try store.remove(for: "a")
        XCTAssertNil(try store.read(for: "a"))
        // 멱등: 다시 호출해도 throw 없음
        try store.remove(for: "a")
    }

    func testOverwriteReplacesContent() throws {
        try store.write(sampleSnapshot(oauth: #"{"v":1}"#), for: "a")
        try store.write(sampleSnapshot(oauth: #"{"v":2}"#), for: "a")
        let loaded = try store.read(for: "a")
        XCTAssertEqual(loaded?.oauthAccountJSON, Data(#"{"v":2}"#.utf8))
    }
}

// MARK: - ClaudeConfigFile (with url injection)

final class ClaudeConfigFileTests: XCTestCase {
    private var tmp: URL!
    private var url: URL { tmp.appendingPathComponent(".claude.json") }
    private var f: ClaudeConfigFile!

    override func setUp() {
        tmp = makeTempDir()
        f = ClaudeConfigFile(url: url)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testReadRawMissingThrows() {
        XCTAssertThrowsError(try f.readRaw()) { e in
            guard case ClaudeConfigError.fileNotFound = e else {
                return XCTFail("unexpected: \(e)")
            }
        }
    }

    func testReadOAuthAccountWhenMissingKey() throws {
        try Data(#"{"x":1}"#.utf8).write(to: url)
        XCTAssertThrowsError(try f.readOAuthAccountJSON()) { e in
            guard case ClaudeConfigError.missingOAuthAccount = e else {
                return XCTFail("unexpected: \(e)")
            }
        }
    }

    func testReadOAuthAccountDecodes() throws {
        let json = #"{"oauthAccount":{"accountUuid":"u-1","emailAddress":"x@y.com","organizationUuid":"o-1"}}"#
        try Data(json.utf8).write(to: url)
        let raw = try f.readOAuthAccountJSON()
        XCTAssertTrue(String(data: raw, encoding: .utf8)!.contains("u-1"))
        let decoded = try f.readOAuthAccount()
        XCTAssertEqual(decoded.accountUuid, "u-1")
    }

    func testPatchPreservesOtherKeys() throws {
        let original = #"{"a":1,"oauthAccount":{"accountUuid":"OLD","emailAddress":"o@e","organizationUuid":"OO"},"b":2}"#
        try Data(original.utf8).write(to: url)
        let newOauth = Data(#"{"accountUuid":"NEW","emailAddress":"n@e","organizationUuid":"NN"}"#.utf8)
        try f.patchOAuthAccount(newOauth)
        let raw = try f.readRaw()
        let s = String(data: raw, encoding: .utf8)!
        XCTAssertTrue(s.contains("NEW"))
        XCTAssertTrue(s.contains("\"a\":1"))
        XCTAssertTrue(s.contains("\"b\":2"))
    }

    func testPatchFileMissingThrows() {
        XCTAssertThrowsError(try f.patchOAuthAccount(Data("{}".utf8))) { e in
            guard case ClaudeConfigError.fileNotFound = e else { return XCTFail("unexpected: \(e)") }
        }
    }

    func testPatchInvalidRootThrows() throws {
        try Data("not json".utf8).write(to: url)
        XCTAssertThrowsError(try f.patchOAuthAccount(Data("{}".utf8)))
    }

    func testPatchMissingKeyThrows() throws {
        try Data(#"{"other":1}"#.utf8).write(to: url)
        XCTAssertThrowsError(try f.patchOAuthAccount(Data("{}".utf8))) { e in
            guard case ClaudeConfigError.missingOAuthAccount = e else { return XCTFail("unexpected: \(e)") }
        }
    }

    func testErrorDescriptions() {
        XCTAssertTrue(ClaudeConfigError.fileNotFound(URL(fileURLWithPath: "/x")).description.contains("/x"))
        XCTAssertTrue(ClaudeConfigError.invalidJSON.description.contains("not a valid JSON"))
        XCTAssertTrue(ClaudeConfigError.missingOAuthAccount.description.contains("oauthAccount"))
    }
}

// MARK: - ClaudeCredentialsFile (with url injection)

final class ClaudeCredentialsFileTests: XCTestCase {
    private var tmp: URL!
    private var url: URL { tmp.appendingPathComponent(".credentials.json") }
    private var f: ClaudeCredentialsFile!

    override func setUp() {
        tmp = makeTempDir()
        f = ClaudeCredentialsFile(url: url)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testReadRawMissingThrows() {
        XCTAssertThrowsError(try f.readRaw()) { e in
            guard case ClaudeCredentialsError.fileNotFound = e else {
                return XCTFail("unexpected: \(e)")
            }
        }
    }

    func testWriteThenReadRaw() throws {
        let payload = Data(#"{"claudeAiOauth":{"accessToken":"t","refreshToken":"r","expiresAt":0,"scopes":[]}}"#.utf8)
        try f.writeRaw(payload)
        XCTAssertEqual(try f.readRaw(), payload)
    }

    func testReadDecodes() throws {
        let payload = Data(#"{"claudeAiOauth":{"accessToken":"a","refreshToken":"b","expiresAt":123,"scopes":["x"]}}"#.utf8)
        try f.writeRaw(payload)
        let decoded = try f.read()
        XCTAssertEqual(decoded.claudeAiOauth.accessToken, "a")
        XCTAssertEqual(decoded.claudeAiOauth.expiresAt, 123)
    }

    func testReadDecodeFailedThrows() throws {
        try Data("not json".utf8).write(to: url)
        XCTAssertThrowsError(try f.read()) { e in
            guard case ClaudeCredentialsError.decodeFailed = e else {
                return XCTFail("unexpected: \(e)")
            }
        }
    }

    func testErrorDescriptions() {
        XCTAssertTrue(ClaudeCredentialsError.fileNotFound(URL(fileURLWithPath: "/x")).description.contains("/x"))
        XCTAssertTrue(ClaudeCredentialsError.decodeFailed("z").description.contains("z"))
    }
}

// MARK: - ClaudeLiveCredentials error descriptions

final class ClaudeLiveCredentialsErrorTests: XCTestCase {
    func testNotFoundDescription() {
        XCTAssertTrue(ClaudeLiveCredentials.Error.notFound.description.contains("찾지 못함"))
    }
    func testDecodeFailedDescription() {
        XCTAssertTrue(ClaudeLiveCredentials.Error.decodeFailed("z").description.contains("z"))
    }
}

// MARK: - ClaudeProcessGuard.matchesClaudeProcess

final class ClaudeProcessGuardMatcherTests: XCTestCase {
    private let g = ClaudeProcessGuard()

    func testMatchesPlainSlashClaude() {
        XCTAssertTrue(g.matchesClaudeProcess("/usr/local/bin/claude"))
        XCTAssertTrue(g.matchesClaudeProcess("/opt/homebrew/bin/claude"))
    }

    func testMatchesNodeCli() {
        XCTAssertTrue(g.matchesClaudeProcess("node /opt/claude/cli.js --some-flag"))
        XCTAssertTrue(g.matchesClaudeProcess("/usr/local/bin/node /opt/claude/cli.js"))
    }

    func testRejectsCCMeter() {
        XCTAssertFalse(g.matchesClaudeProcess("/Users/x/Applications/CCMeter.app/Contents/MacOS/CCMeter"))
    }

    func testRejectsClaudeDotAppDesktop() {
        XCTAssertFalse(g.matchesClaudeProcess("/Applications/Claude.app/Contents/MacOS/Claude Code"))
    }

    func testRejectsUnrelated() {
        XCTAssertFalse(g.matchesClaudeProcess("/bin/zsh -l"))
        XCTAssertFalse(g.matchesClaudeProcess(""))
    }

    func testIsClaudeRunningDoesNotCrash() {
        // 실제 ps 결과에 따라 true/false. 호출 자체가 안전한지만 검증.
        _ = g.isClaudeRunning()
    }
}

// MARK: - SwitchError descriptions

final class SwitchErrorTests: XCTestCase {
    func testAllErrorDescriptionsNonEmpty() {
        XCTAssertFalse(SwitchError.claudeRunning.description.isEmpty)
        XCTAssertFalse(SwitchError.targetNotFound("x").description.isEmpty)
        XCTAssertFalse(SwitchError.noActiveProfile.description.isEmpty)
        XCTAssertFalse(SwitchError.verificationFailed("y").description.isEmpty)
        struct Boom: Error {}
        XCTAssertFalse(SwitchError.underlying(Boom()).description.isEmpty)
    }
}

// MARK: - UsageClient (URLProtocol mock)

/// 테스트용 URLProtocol — `MockURLProtocol.handler` 에 set 한 closure 로 응답 합성.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "Mock", code: -1))
            return
        }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class UsageClientTests: XCTestCase {
    private let endpoint = URL(string: "https://test.invalid/api/oauth/usage")!
    private var session: URLSession!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
    }

    private func client() -> UsageClient {
        UsageClient(endpoint: endpoint, session: session, clock: SystemClock())
    }

    private func makeResponse(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: endpoint, statusCode: status, httpVersion: "HTTP/1.1",
                        headerFields: headers)!
    }

    func testFetchSuccess() async throws {
        MockURLProtocol.handler = { [endpoint] req in
            XCTAssertEqual(req.url, endpoint)
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer TOK")
            XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
            let body = #"""
            {"five_hour":{"utilization":42.6,"resets_at":"2026-05-12T01:00:00Z"},
             "seven_day":{"utilization":10.0,"resets_at":"2026-05-15T00:00:00.123Z"}}
            """#
            return (HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: "HTTP/1.1",
                                    headerFields: nil)!,
                    Data(body.utf8))
        }
        let snap = try await client().fetch(accessToken: "TOK")
        XCTAssertEqual(snap.fiveHourUtilization, 43)   // 42.6 → 43
        XCTAssertEqual(snap.sevenDayUtilization, 10)
        XCTAssertNotNil(snap.fiveHourResetsAt)
        XCTAssertNotNil(snap.sevenDayResetsAt)
    }

    func testFetchUnauthorized() async {
        MockURLProtocol.handler = { [endpoint] _ in
            (HTTPURLResponse(url: endpoint, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             Data())
        }
        do {
            _ = try await client().fetch(accessToken: "T")
            XCTFail("expected throw")
        } catch UsageClientError.unauthorized {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testFetchRateLimitedWithRetryAfterHeader() async {
        MockURLProtocol.handler = { [endpoint] _ in
            (HTTPURLResponse(url: endpoint, statusCode: 429, httpVersion: nil,
                             headerFields: ["Retry-After": "120"])!,
             Data())
        }
        do {
            _ = try await client().fetch(accessToken: "T")
            XCTFail("expected throw")
        } catch UsageClientError.rateLimited(let retry) {
            XCTAssertEqual(retry, 120)
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testFetchRateLimitedFromBody() async {
        MockURLProtocol.handler = { [endpoint] _ in
            (HTTPURLResponse(url: endpoint, statusCode: 429, httpVersion: nil, headerFields: nil)!,
             Data(#"{"rate_limited":true,"retry_after":45}"#.utf8))
        }
        do {
            _ = try await client().fetch(accessToken: "T")
            XCTFail("expected throw")
        } catch UsageClientError.rateLimited(let retry) {
            XCTAssertEqual(retry, 45)
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testFetchHttpError() async {
        MockURLProtocol.handler = { [endpoint] _ in
            (HTTPURLResponse(url: endpoint, statusCode: 500, httpVersion: nil, headerFields: nil)!,
             Data("server error".utf8))
        }
        do {
            _ = try await client().fetch(accessToken: "T")
            XCTFail("expected throw")
        } catch UsageClientError.http(let s, let b) {
            XCTAssertEqual(s, 500)
            XCTAssertTrue(b.contains("server error"))
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testFetchDecodeFailedOn200() async {
        MockURLProtocol.handler = { [endpoint] _ in
            (HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data("not json".utf8))
        }
        do {
            _ = try await client().fetch(accessToken: "T")
            XCTFail("expected throw")
        } catch UsageClientError.decodeFailed {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testFetchRateLimitedInBodyOf200() async {
        MockURLProtocol.handler = { [endpoint] _ in
            (HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"rate_limited":true,"retry_after":30}"#.utf8))
        }
        do {
            _ = try await client().fetch(accessToken: "T")
            XCTFail("expected throw")
        } catch UsageClientError.rateLimited(let retry) {
            XCTAssertEqual(retry, 30)
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testFetchTransportError() async {
        let url = URL(string: "https://nonexistent-domain-xyzzy.invalid")!
        let realSession = URLSession(configuration: .ephemeral)
        let c = UsageClient(endpoint: url, session: realSession, clock: SystemClock())
        do {
            _ = try await c.fetch(accessToken: "T")
            XCTFail("expected throw")
        } catch UsageClientError.transport {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testErrorDescriptionsCoverage() {
        XCTAssertFalse(UsageClientError.unauthorized.description.isEmpty)
        XCTAssertFalse(UsageClientError.rateLimited(retryAfter: nil).description.isEmpty)
        XCTAssertFalse(UsageClientError.http(status: 500, body: "x").description.isEmpty)
        XCTAssertFalse(UsageClientError.decodeFailed("z").description.isEmpty)
        struct Boom: Error {}
        XCTAssertFalse(UsageClientError.transport(Boom()).description.isEmpty)
    }
}
