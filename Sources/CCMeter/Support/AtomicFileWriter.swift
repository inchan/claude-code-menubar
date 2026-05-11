import Foundation

/// tmp 파일에 쓰고 fsync 후 rename 으로 원자 교체.
/// 권한은 umask 영향을 받지 않도록 `fchmod` 로 명시 강제.
/// 기존 디렉토리는 `chmod` 로 0700 재강제.
enum AtomicFileWriter {
    static func write(_ data: Data, to url: URL, permissions: mode_t = 0o600,
                      directoryPermissions: mode_t = 0o700) throws {
        let dir = url.deletingLastPathComponent()
        try ensureDirectory(dir, permissions: directoryPermissions)

        let tmpURL = dir.appendingPathComponent(".\(url.lastPathComponent).tmp.\(UUID().uuidString)")
        let path = tmpURL.path
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, permissions)
        guard fd >= 0 else {
            throw AtomicFileWriterError.openFailed(errno: errno, path: path)
        }
        // umask 영향 차단: 권한 명시 강제
        if fchmod(fd, permissions) != 0 {
            let e = errno
            Darwin.close(fd)
            unlink(path)
            throw AtomicFileWriterError.chmodFailed(errno: e, path: path)
        }

        do {
            try writeAll(fd: fd, data: data, path: path)
            if fsync(fd) != 0 {
                throw AtomicFileWriterError.fsyncFailed(errno: errno, path: path)
            }
            // close 실패도 쓰기 오류의 일부 — fsync 이후 close 가 디스크 메타 commit 에 영향 줄 수 있음
            if Darwin.close(fd) != 0 {
                let e = errno
                unlink(path)
                throw AtomicFileWriterError.closeFailed(errno: e, path: path)
            }
        } catch {
            // 부분 실패: tmp 정리
            Darwin.close(fd)
            unlink(path)
            throw error
        }

        if rename(path, url.path) != 0 {
            let e = errno
            unlink(path)
            throw AtomicFileWriterError.renameFailed(errno: e, path: path, target: url.path)
        }
        // 디렉토리 fsync 로 메타 영속화 (best-effort)
        if let dirFd = openDir(dir.path) {
            fsync(dirFd)
            Darwin.close(dirFd)
        }
    }

    private static func ensureDirectory(_ dir: URL, permissions: mode_t) throws {
        let path = dir.path
        var stat = Darwin.stat()
        let exists = (lstat(path, &stat) == 0)
        if !exists {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: permissions)]
            )
        }
        // 기존 dir 도 권한 재강제 (createDirectory attributes 미적용 케이스 보정)
        if chmod(path, permissions) != 0 {
            // chmod 실패는 로깅만 — 본 동작은 진행
            Log.store.warning("chmod(\(path), \(String(permissions, radix: 8))) failed errno=\(errno)")
        }
    }

    private static func writeAll(fd: Int32, data: Data, path: String) throws {
        var written = 0
        try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Void in
            guard let base = buf.baseAddress else { return }
            while written < data.count {
                let n = Darwin.write(fd, base.advanced(by: written), data.count - written)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw AtomicFileWriterError.writeFailed(errno: errno, path: path)
                }
                written += n
            }
        }
    }

    private static func openDir(_ path: String) -> Int32? {
        let fd = open(path, O_RDONLY)
        return fd >= 0 ? fd : nil
    }
}

enum AtomicFileWriterError: Error, CustomStringConvertible {
    case openFailed(errno: Int32, path: String)
    case chmodFailed(errno: Int32, path: String)
    case writeFailed(errno: Int32, path: String)
    case fsyncFailed(errno: Int32, path: String)
    case closeFailed(errno: Int32, path: String)
    case renameFailed(errno: Int32, path: String, target: String)

    var description: String {
        switch self {
        case .openFailed(let e, let p): return "open failed (errno=\(e)) at \(p)"
        case .chmodFailed(let e, let p): return "fchmod failed (errno=\(e)) at \(p)"
        case .writeFailed(let e, let p): return "write failed (errno=\(e)) at \(p)"
        case .fsyncFailed(let e, let p): return "fsync failed (errno=\(e)) at \(p)"
        case .closeFailed(let e, let p): return "close failed (errno=\(e)) at \(p)"
        case .renameFailed(let e, let p, let t): return "rename failed (errno=\(e)) \(p) -> \(t)"
        }
    }
}
