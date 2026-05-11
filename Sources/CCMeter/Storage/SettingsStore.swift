import Foundation

protocol SettingsStoreProtocol: AnyObject {
    func load() -> AppSettings
    func save(_ settings: AppSettings) throws
}

final class SettingsStore: SettingsStoreProtocol {
    func load() -> AppSettings {
        let url = Paths.settingsFile
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSON.decode(AppSettings.self, from: data) else {
            return .defaults
        }
        return parsed
    }

    func save(_ settings: AppSettings) throws {
        let data = try JSON.encode(settings)
        try AtomicFileWriter.write(data, to: Paths.settingsFile, permissions: 0o600)
    }
}
