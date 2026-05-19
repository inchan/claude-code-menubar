import XCTest
@testable import ClaudeCodeMenubar

/// Production 디렉토리(Paths) 를 건드리지 않는 범위에서 가능한 통합 흐름 검증.
/// 진짜 UI(SwiftUI body) 와 SwitchTransaction 의 transactional 흐름은 hardcoded
/// 의존성(`ClaudeCredentialsFile`, `ClaudeProcessGuard`) 때문에 mock 곤란 — 별도 작업.

// MARK: - JSON byte slice patcher × ARCHITECTURE invariant

/// `~/.claude.json` 의 `oauthAccount` 영역을 통째로 교체할 때 알 수 없는 필드와
/// 들여쓰기, 다른 최상위 키, 후행 키들이 보존되어야 한다는 불변식 검증.
/// 회귀 위험: JSON.decode → re-encode 패턴으로 갈아엎으면 미지 필드 소실.
final class ClaudeConfigPatchInvariantTests: XCTestCase {
    private let original = """
    {
      "numStartups": 17,
      "mcpServers": {"github": {"command": "x"}},
      "oauthAccount": {
        "accountUuid": "OLD-UUID",
        "emailAddress": "old@example.com",
        "organizationUuid": "OLD-ORG",
        "billingType": "paid",
        "unknownFutureField": [1, 2, 3]
      },
      "telemetry": false
    }
    """

    private let newOauth = #"{"accountUuid":"NEW-UUID","emailAddress":"new@example.com","organizationUuid":"NEW-ORG"}"#

    func testReplaceOauthAccountPreservesOuterKeys() throws {
        let patched = try JSONByteSlicePatcher.replace(
            in: Data(original.utf8),
            key: "oauthAccount",
            with: Data(newOauth.utf8)
        )
        let s = String(data: patched, encoding: .utf8)!
        // 새 oauthAccount 영역 포함
        XCTAssertTrue(s.contains("NEW-UUID"))
        XCTAssertTrue(s.contains("new@example.com"))
        // 외부 최상위 키 보존
        XCTAssertTrue(s.contains("\"numStartups\": 17"))
        XCTAssertTrue(s.contains("\"mcpServers\""))
        XCTAssertTrue(s.contains("\"telemetry\": false"))
        // 들여쓰기 보존 (앞의 2-space)
        XCTAssertTrue(s.contains("\n  \"numStartups\""))
    }

    func testPatchedDocumentIsValidJSON() throws {
        let patched = try JSONByteSlicePatcher.replace(
            in: Data(original.utf8),
            key: "oauthAccount",
            with: Data(newOauth.utf8)
        )
        // JSONSerialization 으로 parse 가능해야 함
        let obj = try JSONSerialization.jsonObject(with: patched) as? [String: Any]
        XCTAssertNotNil(obj)
        XCTAssertEqual((obj?["numStartups"] as? Int), 17)
        let oauth = obj?["oauthAccount"] as? [String: Any]
        XCTAssertEqual(oauth?["accountUuid"] as? String, "NEW-UUID")
    }

    func testOldUnknownFieldGone_NewFieldsApplied() throws {
        let patched = try JSONByteSlicePatcher.replace(
            in: Data(original.utf8),
            key: "oauthAccount",
            with: Data(newOauth.utf8)
        )
        let s = String(data: patched, encoding: .utf8)!
        // 새 oauthAccount 가 들고 오지 않은 필드는 사라짐 — 의도된 동작
        // (oauthAccount 안쪽 미지 필드는 새 값으로 교체되므로 소실 정상)
        XCTAssertFalse(s.contains("unknownFutureField"))
        XCTAssertFalse(s.contains("OLD-UUID"))
        XCTAssertFalse(s.contains("\"billingType\": \"paid\""))
    }
}

// MARK: - Domain model serialization roundtrip

final class DomainModelCodableTests: XCTestCase {
    func testAccountRoundtripWithOptionals() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Account(id: "id-1", label: "alice", emailAddress: "a@x.com",
                        accountUuid: "uuid-1", organizationUuid: "org-1",
                        colorHex: "#34C759", addedAt: now,
                        lastUsedAt: nil, subscriptionType: nil)
        let data = try JSON.encode(a)
        let decoded = try JSON.decode(Account.self, from: data)
        XCTAssertEqual(decoded.id, "id-1")
        XCTAssertEqual(decoded.label, "alice")
        XCTAssertEqual(decoded.lastUsedAt, nil)
        XCTAssertEqual(decoded.subscriptionType, nil)
        XCTAssertEqual(decoded.colorHex, "#34C759")
    }

    func testUsageSnapshotRoundtripWithNilWeekly() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_500)
        let snap = UsageSnapshot(fiveHourUtilization: 73, fiveHourResetsAt: now,
                                 sevenDayUtilization: nil, sevenDayResetsAt: nil,
                                 fetchedAt: now)
        let data = try JSON.encode(snap)
        let decoded = try JSON.decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded.fiveHourUtilization, 73)
        XCTAssertEqual(decoded.sevenDayUtilization, nil)
        XCTAssertEqual(decoded.sevenDayLevel, .healthy) // nil → 0 → healthy
    }

    func testClaudeOAuthAccountIgnoresUnknownFields() throws {
        let json = Data(#"""
        {
          "accountUuid": "u-1",
          "emailAddress": "x@y.com",
          "organizationUuid": "o-1",
          "billingType": "paid",
          "accountCreatedAt": "2026-01-01",
          "subscriptionCreatedAt": "2026-02-01",
          "futureUnknown": 42,
          "anotherUnknown": {"deep": true}
        }
        """#.utf8)
        let decoded = try JSON.decode(ClaudeOAuthAccount.self, from: json)
        XCTAssertEqual(decoded.accountUuid, "u-1")
        XCTAssertEqual(decoded.emailAddress, "x@y.com")
        XCTAssertEqual(decoded.billingType, "paid")
    }

    func testClaudeCredentialsRootRoundtrip() throws {
        let creds = ClaudeCredentialsRoot(
            claudeAiOauth: ClaudeAiOAuth(
                accessToken: "tok-A",
                refreshToken: "tok-R",
                expiresAt: 1_700_999_999_000,
                scopes: ["user:inference", "user:profile"],
                subscriptionType: "max",
                rateLimitTier: "high"
            )
        )
        let data = try JSON.encode(creds)
        let decoded = try JSON.decode(ClaudeCredentialsRoot.self, from: data)
        XCTAssertEqual(decoded.claudeAiOauth.accessToken, "tok-A")
        XCTAssertEqual(decoded.claudeAiOauth.expiresAt, 1_700_999_999_000)
        XCTAssertEqual(decoded.claudeAiOauth.scopes, ["user:inference", "user:profile"])
        XCTAssertEqual(decoded.claudeAiOauth.subscriptionType, "max")
    }
}

// MARK: - BackupRotator + AtomicFileWriter combined invariant

/// 백업이 atomic 쓰기 + 회전을 합쳐 정확히 N 개만 남기는 동작 검증.
/// 단일 모듈로는 분리 검증되지만, 결합 결과(파일 권한 + 회전 정렬)는 통합.
final class BackupAtomicIntegrationTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccmeter-int-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testBackupsArePerm0600AndSorted() throws {
        let r = BackupRotator(directory: tmp, keep: 3)
        for i in 0..<3 {
            _ = try r.write(label: .claudeCredentials, data: Data("v\(i)".utf8))
            Thread.sleep(forTimeInterval: 0.002)
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
            .filter { $0.hasPrefix("\(BackupRotator.Label.claudeCredentials.rawValue).") }
            .sorted()
        XCTAssertEqual(entries.count, 3)
        for name in entries {
            let path = tmp.appendingPathComponent(name).path
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let perm = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
            XCTAssertEqual(perm & 0o777, 0o600, "backup \(name) has perm \(String(perm, radix: 8))")
        }
    }
}
