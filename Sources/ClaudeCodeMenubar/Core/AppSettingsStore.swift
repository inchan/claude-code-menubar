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

    /// 임계치 % 편집. caution/warning/critical 중 하나만 변경.
    /// 단조 증가 제약은 clamped() 에서 보정.
    func setThreshold(_ level: ThresholdLevel, percent: Int) {
        update {
            switch level {
            case .caution:  $0.thresholdCaution  = percent
            case .warning:  $0.thresholdWarning  = percent
            case .critical: $0.thresholdCritical = percent
            case .healthy:  break // healthy 는 시작점이라 편집 불가
            }
        }
    }

    func resetThresholds() {
        update {
            $0.thresholdCaution  = 50
            $0.thresholdWarning  = 80
            $0.thresholdCritical = 95
        }
    }

    // MARK: - Display extras
    func setMenuBarPrefix(_ s: String) { update { $0.menuBarPrefix = s } }
    func setIconAnimation(_ on: Bool) { update { $0.iconAnimation = on } }
    func setBlinkOnChange(_ on: Bool) { update { $0.blinkOnChange = on } }
    func setHoverDetail(_ on: Bool) { update { $0.hoverDetail = on } }
    func setPollInterval(active: Int? = nil, inactive: Int? = nil) {
        update {
            if let a = active   { $0.pollIntervalActiveSeconds   = max(5, min(3600, a)) }
            if let i = inactive { $0.pollIntervalInactiveSeconds = max(5, min(3600, i)) }
        }
    }

    // MARK: - System extras
    func setStartInBackground(_ on: Bool) { update { $0.startInBackground = on } }
    func setAutoUpdateCheck(_ on: Bool) { update { $0.autoUpdateCheck = on } }
    func setKeychainSync(_ on: Bool) { update { $0.keychainSync = on } }
    func setICloudBackup(_ on: Bool) { update { $0.iCloudBackup = on } }
    func setDebugLogEnabled(_ on: Bool) { update { $0.debugLogEnabled = on } }
    func setUseKeychainLiveTokens(_ on: Bool) { update { $0.useKeychainLiveTokens = on } }
    func setUseAutoRefresh(_ on: Bool) { update { $0.useAutoRefresh = on } }

    /// 외부 파일(import)로부터 받은 AppSettings 로 전체 덮어쓰기.
    func replaceAll(_ next: AppSettings) throws {
        settings = next
        try store.save(next)
    }
}
