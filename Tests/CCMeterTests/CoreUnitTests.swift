import XCTest
@testable import CCMeter

// MARK: - FNV

final class FNVTests: XCTestCase {
    func testDeterministicForSameInput() {
        XCTAssertEqual(FNV.hash32("hello"), FNV.hash32("hello"))
        XCTAssertEqual(FNV.hash32(""), FNV.hash32(""))
    }

    func testDifferentInputsDiffer() {
        XCTAssertNotEqual(FNV.hash32("a"), FNV.hash32("b"))
        XCTAssertNotEqual(FNV.hash32("hello"), FNV.hash32("Hello"))
    }

    func testKnownEmptySeed() {
        // FNV-1a offset basis
        XCTAssertEqual(FNV.hash32(""), 0x811c9dc5)
    }

    func testUtf8MultiByteStable() {
        let a = FNV.hash32("한글")
        let b = FNV.hash32("한글")
        XCTAssertEqual(a, b)
    }
}

// MARK: - ThresholdLevel

final class ThresholdLevelTests: XCTestCase {
    func testBoundaries() {
        XCTAssertEqual(ThresholdLevel.from(percent: 0), .healthy)
        XCTAssertEqual(ThresholdLevel.from(percent: 49), .healthy)
        XCTAssertEqual(ThresholdLevel.from(percent: 50), .caution)
        XCTAssertEqual(ThresholdLevel.from(percent: 79), .caution)
        XCTAssertEqual(ThresholdLevel.from(percent: 80), .warning)
        XCTAssertEqual(ThresholdLevel.from(percent: 94), .warning)
        XCTAssertEqual(ThresholdLevel.from(percent: 95), .critical)
        XCTAssertEqual(ThresholdLevel.from(percent: 100), .critical)
    }

    func testOutOfRangeClampedSemantics() {
        // 음수와 100 초과도 비즈니스 로직상 healthy / critical 로 처리되어야 함
        XCTAssertEqual(ThresholdLevel.from(percent: -1), .healthy)
        XCTAssertEqual(ThresholdLevel.from(percent: 999), .critical)
    }
}

// MARK: - UsageDisplayMode

final class UsageDisplayModeTests: XCTestCase {
    func testUsedReturnsUtilizationClamped() {
        XCTAssertEqual(UsageDisplayMode.used.display(utilization: 0), 0)
        XCTAssertEqual(UsageDisplayMode.used.display(utilization: 50), 50)
        XCTAssertEqual(UsageDisplayMode.used.display(utilization: 100), 100)
        XCTAssertEqual(UsageDisplayMode.used.display(utilization: -5), 0)
        XCTAssertEqual(UsageDisplayMode.used.display(utilization: 250), 100)
    }

    func testRemainingInverts() {
        XCTAssertEqual(UsageDisplayMode.remaining.display(utilization: 0), 100)
        XCTAssertEqual(UsageDisplayMode.remaining.display(utilization: 30), 70)
        XCTAssertEqual(UsageDisplayMode.remaining.display(utilization: 100), 0)
        XCTAssertEqual(UsageDisplayMode.remaining.display(utilization: 120), 0)
        XCTAssertEqual(UsageDisplayMode.remaining.display(utilization: -10), 100)
    }
}

// MARK: - UsageVisibility

final class UsageVisibilityTests: XCTestCase {
    func testShowsSession() {
        XCTAssertTrue(UsageVisibility.sessionOnly.showsSession)
        XCTAssertFalse(UsageVisibility.weeklyOnly.showsSession)
        XCTAssertTrue(UsageVisibility.both.showsSession)
    }

    func testShowsWeekly() {
        XCTAssertFalse(UsageVisibility.sessionOnly.showsWeekly)
        XCTAssertTrue(UsageVisibility.weeklyOnly.showsWeekly)
        XCTAssertTrue(UsageVisibility.both.showsWeekly)
    }
}

// MARK: - Account.initial

final class AccountInitialTests: XCTestCase {
    private func make(label: String, email: String = "user@example.com") -> Account {
        Account(id: "x", label: label, emailAddress: email, accountUuid: "u",
                organizationUuid: "o", colorHex: "#000000", addedAt: Date(),
                lastUsedAt: nil, subscriptionType: nil)
    }

    func testSingleWordLabel() {
        XCTAssertEqual(make(label: "alice").initial, "A")
        XCTAssertEqual(make(label: "Bob").initial, "B")
    }

    func testTwoWordLabel() {
        XCTAssertEqual(make(label: "John Doe").initial, "JD")
        XCTAssertEqual(make(label: "alice smith").initial, "AS")
    }

    func testThreeOrMoreWordsUsesFirstTwo() {
        XCTAssertEqual(make(label: "Mary Jane Doe").initial, "MJ")
    }

    func testEmptyLabelFallsBackToEmail() {
        XCTAssertEqual(make(label: "", email: "zoe@example.com").initial, "Z")
        XCTAssertEqual(make(label: "   ", email: "yoda@x.com").initial, "Y")
    }
}

// MARK: - Account.deterministicColor

final class AccountColorTests: XCTestCase {
    func testSameSeedYieldsSameColor() {
        XCTAssertEqual(Account.deterministicColor(for: "alice@example.com"),
                       Account.deterministicColor(for: "alice@example.com"))
    }

    func testKnownPaletteColor() {
        let c = Account.deterministicColor(for: "alice@example.com")
        XCTAssertTrue(c.hasPrefix("#"))
        XCTAssertEqual(c.count, 7) // #RRGGBB
    }
}

// MARK: - JSONByteSlicePatcher

final class JSONByteSlicePatcherTests: XCTestCase {
    private func data(_ s: String) -> Data { s.data(using: .utf8)! }

    func testReplaceObjectValue() throws {
        let src = data(#"{"a":1,"b":{"x":1},"c":3}"#)
        let newV = data(#"{"y":2}"#)
        let out = try JSONByteSlicePatcher.replace(in: src, key: "b", with: newV)
        XCTAssertEqual(String(data: out, encoding: .utf8), #"{"a":1,"b":{"y":2},"c":3}"#)
    }

    func testReplaceStringValuePreservesOtherKeys() throws {
        let src = data(#"{"a":"old","b":2}"#)
        let newV = data(#""new""#)
        let out = try JSONByteSlicePatcher.replace(in: src, key: "a", with: newV)
        XCTAssertEqual(String(data: out, encoding: .utf8), #"{"a":"new","b":2}"#)
    }

    func testReplaceArrayValue() throws {
        let src = data(#"{"k":[1,2,3]}"#)
        let newV = data("[]")
        let out = try JSONByteSlicePatcher.replace(in: src, key: "k", with: newV)
        XCTAssertEqual(String(data: out, encoding: .utf8), #"{"k":[]}"#)
    }

    func testReplaceNumberValue() throws {
        let src = data(#"{"n":42,"m":7}"#)
        let newV = data("100")
        let out = try JSONByteSlicePatcher.replace(in: src, key: "n", with: newV)
        XCTAssertEqual(String(data: out, encoding: .utf8), #"{"n":100,"m":7}"#)
    }

    func testKeyNotFoundThrows() {
        let src = data(#"{"a":1}"#)
        XCTAssertThrowsError(
            try JSONByteSlicePatcher.replace(in: src, key: "missing", with: data("0"))
        ) { err in
            guard case JSONByteSlicePatcher.Error.keyNotFound(let k) = err else {
                return XCTFail("unexpected error: \(err)")
            }
            XCTAssertEqual(k, "missing")
        }
    }

    func testMalformedNoTopLevelObjectThrows() {
        let src = data("not json")
        XCTAssertThrowsError(
            try JSONByteSlicePatcher.replace(in: src, key: "a", with: data("0"))
        )
    }

    func testNestedKeyOfSameNameInChildNotMatched() throws {
        // top-level "b" 만 매칭. child 의 "b" 는 무시되어야 함.
        let src = data(#"{"a":{"b":99},"b":2}"#)
        let newV = data("777")
        let out = try JSONByteSlicePatcher.replace(in: src, key: "b", with: newV)
        XCTAssertEqual(String(data: out, encoding: .utf8), #"{"a":{"b":99},"b":777}"#)
    }

    func testPreservesWhitespaceAndOrder() throws {
        let src = data("{\n  \"a\": 1,\n  \"b\": {\"x\": 1}\n}")
        let newV = data(#"{"y":2}"#)
        let out = try JSONByteSlicePatcher.replace(in: src, key: "b", with: newV)
        XCTAssertEqual(String(data: out, encoding: .utf8),
                       "{\n  \"a\": 1,\n  \"b\": {\"y\":2}\n}")
    }
}

// MARK: - AtomicFileWriter

final class AtomicFileWriterTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccmeter-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testWriteCreatesFileWithContents() throws {
        let url = tmp.appendingPathComponent("hello.txt")
        let bytes = Data("hello world".utf8)
        try AtomicFileWriter.write(bytes, to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testWriteOverwritesAtomically() throws {
        let url = tmp.appendingPathComponent("a.bin")
        try AtomicFileWriter.write(Data("v1".utf8), to: url)
        try AtomicFileWriter.write(Data("v2-longer".utf8), to: url)
        XCTAssertEqual(try Data(contentsOf: url), Data("v2-longer".utf8))
    }

    func testWriteSetsExactPermissions() throws {
        let url = tmp.appendingPathComponent("perm.bin")
        try AtomicFileWriter.write(Data("x".utf8), to: url, permissions: 0o600)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perm = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        XCTAssertEqual(perm & 0o777, 0o600)
    }

    func testWriteCreatesIntermediateDirectory() throws {
        let nested = tmp.appendingPathComponent("a/b/c", isDirectory: true)
        let url = nested.appendingPathComponent("file.bin")
        try AtomicFileWriter.write(Data("x".utf8), to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testTempFileCleanedUpAfterSuccess() throws {
        let url = tmp.appendingPathComponent("clean.bin")
        try AtomicFileWriter.write(Data("ok".utf8), to: url)
        let leftover = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
            .filter { $0.hasPrefix(".clean.bin.tmp.") }
        XCTAssertTrue(leftover.isEmpty, "tmp file leaked: \(leftover)")
    }
}

// MARK: - BackupRotator

final class BackupRotatorTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccmeter-backup-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func count(prefix: String) throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: tmp.path)
            .filter { $0.hasPrefix("\(prefix).") }
            .count
    }

    func testWriteCreatesBackupFile() throws {
        let r = BackupRotator(directory: tmp, keep: 3)
        let url = try r.write(label: .claudeCredentials, data: Data("v".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url), Data("v".utf8))
    }

    func testRotationKeepsLatestN() throws {
        let r = BackupRotator(directory: tmp, keep: 3)
        for i in 0..<5 {
            _ = try r.write(label: .claudeCredentials, data: Data("v\(i)".utf8))
            // 같은 ms 충돌을 피하기 위해 짧은 sleep
            Thread.sleep(forTimeInterval: 0.002)
        }
        XCTAssertEqual(try count(prefix: BackupRotator.Label.claudeCredentials.rawValue), 3)
    }

    func testLabelsAreIsolated() throws {
        let r = BackupRotator(directory: tmp, keep: 2)
        for _ in 0..<3 {
            _ = try r.write(label: .claudeCredentials, data: Data("c".utf8))
            Thread.sleep(forTimeInterval: 0.002)
            _ = try r.write(label: .claudeConfigOAuthAccount, data: Data("o".utf8))
            Thread.sleep(forTimeInterval: 0.002)
        }
        XCTAssertEqual(try count(prefix: BackupRotator.Label.claudeCredentials.rawValue), 2)
        XCTAssertEqual(try count(prefix: BackupRotator.Label.claudeConfigOAuthAccount.rawValue), 2)
    }
}

// MARK: - AppSettings (defaults + decoding tolerance)

final class AppSettingsTests: XCTestCase {
    func testDefaults() {
        let s = AppSettings()
        XCTAssertEqual(s.pollIntervalActiveSeconds, 60)
        XCTAssertEqual(s.pollIntervalInactiveSeconds, 300)
        XCTAssertFalse(s.launchAtLogin)
        XCTAssertEqual(s.thresholdWarning, 80)
        XCTAssertEqual(s.thresholdCritical, 95)
        XCTAssertEqual(s.usageDisplayMode, .used)
        XCTAssertEqual(s.usageVisibility, .both)
        XCTAssertEqual(s.menuBarStyle, .percent)
        XCTAssertEqual(s.timeFormat, .twelveHour)
        XCTAssertTrue(s.colorOverrides.isEmpty)
    }

    func testDecodeEmptyJsonUsesDefaults() throws {
        let s = try JSON.decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(s.pollIntervalActiveSeconds, 60)
        XCTAssertEqual(s.usageDisplayMode, .used)
    }

    func testDecodePartialKeysPreservesRestAsDefault() throws {
        let s = try JSON.decode(AppSettings.self, from: Data(#"{"thresholdWarning":70}"#.utf8))
        XCTAssertEqual(s.thresholdWarning, 70)
        XCTAssertEqual(s.thresholdCritical, 95)
    }

    func testRoundtripJSON() throws {
        var s = AppSettings()
        s.thresholdWarning = 75
        s.usageVisibility = .sessionOnly
        s.colorOverrides = ["healthy": "#112233"]
        let encoded = try JSON.encode(s)
        let decoded = try JSON.decode(AppSettings.self, from: encoded)
        XCTAssertEqual(decoded.thresholdWarning, 75)
        XCTAssertEqual(decoded.usageVisibility, .sessionOnly)
        XCTAssertEqual(decoded.colorOverrides["healthy"], "#112233")
    }
}

// MARK: - TimeFormat (UI-adjacent pure helper)

final class TimeFormatTests: XCTestCase {
    private func at(hour: Int, minute: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 12
        c.hour = hour; c.minute = minute
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testTwentyFourHourFormatIsLocaleInvariant() {
        let d = at(hour: 22, minute: 5)
        let ko = TimeFormat.format(d, style: .twentyFourHour, locale: Locale(identifier: "ko_KR"))
        let en = TimeFormat.format(d, style: .twentyFourHour, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(ko, "22:05")
        XCTAssertEqual(en, "22:05")
    }

    func testTwelveHourKoreanUsesAmPmPrefix() {
        let d = at(hour: 22, minute: 0)
        let ko = TimeFormat.format(d, style: .twelveHour, locale: Locale(identifier: "ko_KR"))
        XCTAssertTrue(ko.contains("10:00"))
        // "오후" 가 어딘가에 있어야 함 (locale 별로 위치가 다를 수 있음)
        XCTAssertTrue(ko.contains("오후"))
    }

    func testTwelveHourEnglishUsesAmPmSuffix() {
        let d = at(hour: 22, minute: 0)
        let en = TimeFormat.format(d, style: .twelveHour, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(en.contains("10:00"))
        XCTAssertTrue(en.uppercased().contains("PM"))
    }
}

// MARK: - ClaudeKeychainCredentials.Error description

final class ClaudeKeychainCredentialsErrorTests: XCTestCase {
    func testWriteFailedDescriptionContainsStatus() {
        let err = ClaudeKeychainCredentials.Error.writeFailed(-25293)
        XCTAssertTrue(err.description.contains("-25293"))
        XCTAssertTrue(err.description.contains("Keychain"))
    }
}
