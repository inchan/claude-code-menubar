import Foundation

protocol SettingsStoreProtocol: AnyObject, Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings) throws
}

final class SettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    private let url: URL
    init(url: URL = Paths.settingsFile) { self.url = url }

    func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSON.decode(AppSettings.self, from: data) else {
            return .defaults
        }
        return parsed
    }

    func save(_ settings: AppSettings) throws {
        let data = try JSON.encode(settings)
        try AtomicFileWriter.write(data, to: url, permissions: 0o600)
    }
}
