import Foundation

/// flock(2) 기반 advisory lock.
/// RAII: deinit 에서 자동 해제. `withLock {}` 헬퍼로 호출자의 `defer release()` 반복 제거.
final class FileLock {
    private var fd: Int32
    private var released: Bool = false
    let path: String

    private init(fd: Int32, path: String) {
        self.fd = fd
        self.path = path
    }

    deinit {
        // idempotent — release() 가 이미 호출됐어도 안전
        if !released, fd >= 0 {
            flock(fd, LOCK_UN)
            close(fd)
        }
    }

    static func acquire(at path: String, blocking: Bool = false) throws -> FileLock {
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            throw FileLockError.openFailed(errno: errno, path: path)
        }
        // 락 자체가 잡혀 있더라도 lock 파일 권한은 0600 강제
        _ = fchmod(fd, 0o600)
        let op = LOCK_EX | (blocking ? 0 : LOCK_NB)
        if flock(fd, op) != 0 {
            let savedErrno = errno
            close(fd)
            if savedErrno == EWOULDBLOCK {
                throw FileLockError.busy(path: path)
            }
            throw FileLockError.lockFailed(errno: savedErrno, path: path)
        }
        return FileLock(fd: fd, path: path)
    }

    /// 락을 잡고 body 실행, 종료 시 자동 해제.
    static func withLock<T>(at path: String, blocking: Bool = false,
                            _ body: () throws -> T) throws -> T {
        let lock = try acquire(at: path, blocking: blocking)
        defer { lock.release() }
        return try body()
    }

    /// 명시적 해제. 이미 해제됐으면 no-op.
    func release() {
        guard !released else { return }
        released = true
        if fd >= 0 {
            flock(fd, LOCK_UN)
            close(fd)
            fd = -1
        }
    }
}

enum FileLockError: Error, CustomStringConvertible {
    case openFailed(errno: Int32, path: String)
    case lockFailed(errno: Int32, path: String)
    case busy(path: String)

    var description: String {
        switch self {
        case .openFailed(let e, let p): return "FileLock.open failed (errno=\(e)) at \(p)"
        case .lockFailed(let e, let p): return "FileLock.flock failed (errno=\(e)) at \(p)"
        case .busy(let p): return "FileLock busy at \(p) — another instance is running"
        }
    }
}
