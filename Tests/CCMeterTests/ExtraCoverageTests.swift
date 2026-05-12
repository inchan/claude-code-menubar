import XCTest
@testable import CCMeter
import Foundation

// MARK: - AtomicFileWriter error paths

final class AtomicFileWriterErrorTests: XCTestCase {
    private var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccm-afw-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() {
        // 권한 복구 후 정리
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)],
                                               ofItemAtPath: tmp.path)
        try? FileManager.default.removeItem(at: tmp)
    }

    func testErrorDescriptionsCoverage() {
        let p = "/test/path"
        let t = "/target/path"
        XCTAssertTrue(AtomicFileWriterError.openFailed(errno: 1, path: p).description.contains(p))
        XCTAssertTrue(AtomicFileWriterError.chmodFailed(errno: 2, path: p).description.contains(p))
        XCTAssertTrue(AtomicFileWriterError.writeFailed(errno: 3, path: p).description.contains(p))
        XCTAssertTrue(AtomicFileWriterError.fsyncFailed(errno: 4, path: p).description.contains(p))
        XCTAssertTrue(AtomicFileWriterError.closeFailed(errno: 5, path: p).description.contains(p))
        XCTAssertTrue(AtomicFileWriterError.renameFailed(errno: 6, path: p, target: t).description.contains(t))
    }
}

// MARK: - FileLock

final class FileLockTests: XCTestCase {
    private var tmp: URL!
    private var path: String { tmp.appendingPathComponent("test.lock").path }

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccm-lock-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testAcquireAndRelease() throws {
        let lock = try FileLock.acquire(at: path)
        XCTAssertEqual(lock.path, path)
        lock.release()
        // 재취득 가능
        let lock2 = try FileLock.acquire(at: path)
        lock2.release()
    }

    func testReleaseIsIdempotent() throws {
        let lock = try FileLock.acquire(at: path)
        lock.release()
        lock.release() // no crash
    }

    func testBusyWhenAlreadyLocked() throws {
        let first = try FileLock.acquire(at: path)
        XCTAssertThrowsError(try FileLock.acquire(at: path)) { err in
            guard case FileLockError.busy = err else { return XCTFail("unexpected: \(err)") }
        }
        first.release()
    }

    func testWithLockExecutesBody() throws {
        var ran = false
        try FileLock.withLock(at: path) { ran = true }
        XCTAssertTrue(ran)
    }

    func testWithLockBodyThrowsPropagates() {
        struct Boom: Error {}
        XCTAssertThrowsError(try FileLock.withLock(at: path) { throw Boom() })
    }

    func testErrorDescriptions() {
        XCTAssertTrue(FileLockError.openFailed(errno: 1, path: "/x").description.contains("/x"))
        XCTAssertTrue(FileLockError.lockFailed(errno: 2, path: "/y").description.contains("/y"))
        XCTAssertTrue(FileLockError.busy(path: "/z").description.contains("/z"))
    }
}

// MARK: - JSONByteSlicePatcher edge

final class JSONByteSlicePatcherEdgeTests: XCTestCase {
    private func d(_ s: String) -> Data { s.data(using: .utf8)! }

    func testEscapedQuoteInStringNotConfused() throws {
        // 키 안에 escape 처리된 따옴표가 있어도 정확히 매칭
        let src = d(#"{"a":"has \"quote\" inside","b":1}"#)
        let out = try JSONByteSlicePatcher.replace(in: src, key: "b", with: d("2"))
        XCTAssertEqual(String(data: out, encoding: .utf8),
                       #"{"a":"has \"quote\" inside","b":2}"#)
    }

    func testReplaceBooleanValue() throws {
        let src = d(#"{"flag":true,"x":1}"#)
        let out = try JSONByteSlicePatcher.replace(in: src, key: "flag", with: d("false"))
        XCTAssertEqual(String(data: out, encoding: .utf8), #"{"flag":false,"x":1}"#)
    }

    func testReplaceNullValue() throws {
        let src = d(#"{"a":null,"b":2}"#)
        let out = try JSONByteSlicePatcher.replace(in: src, key: "a", with: d(#""now""#))
        XCTAssertEqual(String(data: out, encoding: .utf8), #"{"a":"now","b":2}"#)
    }

    func testReplaceValueAtEnd() throws {
        let src = d(#"{"x":1,"k":42}"#)
        let out = try JSONByteSlicePatcher.replace(in: src, key: "k", with: d("99"))
        XCTAssertEqual(String(data: out, encoding: .utf8), #"{"x":1,"k":99}"#)
    }

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try JSONByteSlicePatcher.replace(in: Data(), key: "a", with: d("0")))
    }
}

// MARK: - SwitchError underlying message routes through description

final class SwitchErrorExtraTests: XCTestCase {
    func testUnderlyingContainsInnerError() {
        struct Boom: Error, CustomStringConvertible { var description: String { "boom-text" } }
        let s = SwitchError.underlying(Boom())
        XCTAssertTrue(s.description.contains("boom"))
    }
}

// MARK: - JSONByteSlicePatcher.Error description

final class JSONByteSlicePatcherErrorTests: XCTestCase {
    func testErrorDescriptions() {
        XCTAssertTrue(JSONByteSlicePatcher.Error.keyNotFound("k").description.contains("k"))
        XCTAssertTrue(JSONByteSlicePatcher.Error.malformed("m").description.contains("m"))
    }
}

// MARK: - ProfileSnapshotStore failure paths

final class ProfileSnapshotStoreFailureTests: XCTestCase {
    private var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccm-ps-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)],
                                               ofItemAtPath: tmp.path)
        try? FileManager.default.removeItem(at: tmp)
    }

    func testReadReturnsNilWhenOnlyOneFilePresent() throws {
        let store = ProfileSnapshotStore(root: tmp)
        let dir = tmp.appendingPathComponent("only-config", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("claude-config.json"))
        // creds 파일 부재 → read 는 nil
        XCTAssertNil(try store.read(for: "only-config"))
    }
}
