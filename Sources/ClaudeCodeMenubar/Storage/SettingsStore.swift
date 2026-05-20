import Foundation

protocol SettingsStoreProtocol: AnyObject, Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings) throws
}

final class SettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var cached: AppSettings?

    init(url: URL = Paths.settingsFile) { self.url = url }

    /// 메모리 캐시 — 첫 호출 시 디스크 read, 이후 save 까지 같은 값 반환.
    /// UsageMonitor 가 매 폴링(60s)마다 호출하므로 file I/O 회피 목적.
    /// 외부 프로세스가 settings.json 직접 수정하는 경우는 미지원 (사용자 시나리오 없음).
    func load() -> AppSettings {
        lock.lock(); defer { lock.unlock() }
        if let c = cached { return c }
        let parsed: AppSettings
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let p = try? JSON.decode(AppSettings.self, from: data) {
            parsed = p
        } else {
            parsed = .defaults
        }
        cached = parsed
        return parsed
    }

    func save(_ settings: AppSettings) throws {
        let data = try JSON.encode(settings)
        try AtomicFileWriter.write(data, to: url, permissions: 0o600)
        lock.lock(); cached = settings; lock.unlock()
    }
}
