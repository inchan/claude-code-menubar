import Foundation
import Combine

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var settings: AppSettings
    private let store: SettingsStoreProtocol

    init(store: SettingsStoreProtocol = SettingsStore()) {
        self.store = store
        self.settings = store.load()
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        do {
            try store.save(settings)
        } catch {
            Log.app.error("settings save failed: \(String(describing: error))")
        }
    }

    func setDisplayMode(_ mode: UsageDisplayMode) { update { $0.usageDisplayMode = mode } }
    func setVisibility(_ v: UsageVisibility) { update { $0.usageVisibility = v } }
    func setMenuBarStyle(_ s: MenuBarStyle) { update { $0.menuBarStyle = s } }
    func setTimeFormat(_ f: TimeFormatStyle) { update { $0.timeFormat = f } }
    func setLaunchAtLogin(_ on: Bool) { update { $0.launchAtLogin = on } }
    func setColorOverride(_ level: ThresholdLevel, hex: String?) {
        update {
            if let hex { $0.colorOverrides[level.rawValue] = hex }
            else { $0.colorOverrides.removeValue(forKey: level.rawValue) }
        }
    }
    func resetColorOverrides() { update { $0.colorOverrides.removeAll() } }
}
