import Foundation

typealias AccountID = String

struct Account: Codable, Identifiable, Hashable, Sendable {
    let id: AccountID
    var label: String
    var emailAddress: String
    var accountUuid: String
    var organizationUuid: String
    var colorHex: String
    var addedAt: Date
    var lastUsedAt: Date?
    var subscriptionType: String?

    var initial: String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return String(emailAddress.prefix(1)).uppercased()
        }
        let words = trimmed.split(separator: " ")
        if words.count >= 2 {
            return "\(words[0].prefix(1))\(words[1].prefix(1))".uppercased()
        }
        return String(trimmed.prefix(1)).uppercased()
    }
}

struct UsageSnapshot: Codable, Hashable, Sendable {
    let fiveHourUtilization: Int       // 0..100
    let fiveHourResetsAt: Date?
    let sevenDayUtilization: Int?
    let sevenDayResetsAt: Date?
    let fetchedAt: Date

    static let empty = UsageSnapshot(fiveHourUtilization: 0, fiveHourResetsAt: nil,
                                     sevenDayUtilization: nil, sevenDayResetsAt: nil,
                                     fetchedAt: .distantPast)

    var fiveHourLevel: ThresholdLevel { ThresholdLevel.from(percent: fiveHourUtilization) }
    var sevenDayLevel: ThresholdLevel {
        ThresholdLevel.from(percent: sevenDayUtilization ?? 0)
    }
}

enum ThresholdLevel: String, Codable, Sendable {
    case healthy   // < caution  — green
    case caution   // < warning  — yellow
    case warning   // < critical — orange
    case critical  // >= critical — red

    /// 기본 임계치 50/80/95 (legacy/fallback).
    static func from(percent: Int) -> ThresholdLevel {
        from(percent: percent, thresholds: .default)
    }

    /// 사용자 설정 임계치 적용 버전.
    static func from(percent: Int, thresholds: ThresholdConfig) -> ThresholdLevel {
        if percent >= thresholds.critical { return .critical }
        if percent >= thresholds.warning  { return .warning }
        if percent >= thresholds.caution  { return .caution }
        return .healthy
    }
}

/// 사용자가 설정 가능한 임계치 구간. 정렬: caution < warning < critical.
struct ThresholdConfig: Sendable, Equatable {
    var caution: Int
    var warning: Int
    var critical: Int

    static let `default` = ThresholdConfig(caution: 50, warning: 80, critical: 95)

    /// 유효 범위(0..100) + 단조 증가 보장.
    func clamped() -> ThresholdConfig {
        let cn = max(1,  min(98, caution))
        let wn = max(cn + 1, min(99, warning))
        let cr = max(wn + 1, min(100, critical))
        return ThresholdConfig(caution: cn, warning: wn, critical: cr)
    }
}

/// Claude Code 활성 자료 스냅샷. 백업/복원의 **byte-단위** 단위.
/// 알 수 없는 필드 손실 방지를 위해 raw bytes 로 보존.
struct ClaudeProfileSnapshot: Sendable {
    /// `~/.claude.json` 의 `oauthAccount` 서브트리 raw JSON
    let oauthAccountJSON: Data
    /// `~/.claude/.credentials.json` 전체 raw JSON
    let credentialsJSON: Data
}

/// 표시/검증 용도의 부분 디코딩 모델.
struct ClaudeOAuthAccount: Codable, Sendable {
    let accountUuid: String
    let emailAddress: String
    let organizationUuid: String
    let billingType: String?
    let accountCreatedAt: String?
    let subscriptionCreatedAt: String?
}

struct ClaudeCredentialsRoot: Codable, Sendable {
    let claudeAiOauth: ClaudeAiOAuth
}

struct ClaudeAiOAuth: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    /// epoch milliseconds
    let expiresAt: Int64
    let scopes: [String]
    let subscriptionType: String?
    let rateLimitTier: String?
}

extension Notification.Name {
    static let ccAccountChanged = Notification.Name("CCAccountChanged")
}

enum CCAccountChangedKind: String {
    case imported, switched, removed, renamed
}

/// UsageMonitor 가 계정별 마지막 에러 상태를 UI 에 노출하기 위한 enum.
/// 알려진 4종 + 그 외 자유 텍스트.
enum AccountError: Equatable, Sendable {
    case keychainDenied
    case unauthorized
    case invalidGrant
    case rateLimited
    case other(String)
}

enum UsageDisplayMode: String, Codable, CaseIterable, Sendable {
    case used       // "사용한" 비율 (utilization 그대로)
    case remaining  // "남은" 비율 (100 - utilization)

    var label: String {
        switch self {
        case .used: return "사용 퍼센트"
        case .remaining: return "남은 퍼센트"
        }
    }

    func display(utilization: Int) -> Int {
        switch self {
        case .used: return max(0, min(100, utilization))
        case .remaining: return max(0, min(100, 100 - utilization))
        }
    }
}

/// 메뉴바 라벨 + 드롭다운에서 어떤 사용량을 보일지.
enum UsageVisibility: String, Codable, CaseIterable, Sendable {
    case sessionOnly  // 5h 만
    case weeklyOnly   // 7d 만
    case both         // 둘 다 (기본)

    var label: String {
        switch self {
        case .sessionOnly: return "세션만"
        case .weeklyOnly: return "주간만"
        case .both: return "세션 + 주간"
        }
    }

    var showsSession: Bool { self != .weeklyOnly }
    var showsWeekly: Bool { self != .sessionOnly }
}

/// 메뉴바 라벨 표시 스타일.
enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    case percent   // "S: 50%  W: 12%"
    case progress  // 그래픽 progress bar

    var label: String {
        switch self {
        case .percent: return "숫자(%)"
        case .progress: return "진행률 바"
        }
    }
}

/// 시간 표시 형식.
enum TimeFormatStyle: String, Codable, CaseIterable, Sendable {
    case twelveHour    // 12시간제 (locale 적용: KO=오후 10:00, EN=10:00 PM)
    case twentyFourHour // 24시간제 (HH:mm)

    var label: String {
        switch self {
        case .twelveHour: return "12시간 (AM/PM)"
        case .twentyFourHour: return "24시간"
        }
    }
}

struct AppSettings: Codable, Sendable {
    var pollIntervalActiveSeconds: Int = 60
    var pollIntervalInactiveSeconds: Int = 300
    var launchAtLogin: Bool = false
    var thresholdCaution: Int = 50
    var thresholdWarning: Int = 80
    var thresholdCritical: Int = 95
    var usageDisplayMode: UsageDisplayMode = .used
    var usageVisibility: UsageVisibility = .both
    var menuBarStyle: MenuBarStyle = .percent
    var timeFormat: TimeFormatStyle = .twelveHour
    /// ThresholdLevel.rawValue → hex (#RRGGBB). nil 또는 누락 시 system default 사용.
    var colorOverrides: [String: String] = [:]

    // MARK: - Display extras
    /// 메뉴바 텍스트 앞 prefix. 비어있으면 표시 안 함. (mock: "cc")
    var menuBarPrefix: String = ""
    /// Behavior 카드 토글들
    var iconAnimation: Bool = false
    var blinkOnChange: Bool = true
    var hoverDetail: Bool = true

    // MARK: - System extras
    /// Startup 카드
    var startInBackground: Bool = true
    var autoUpdateCheck: Bool = false
    /// Sync 카드
    var keychainSync: Bool = true
    var iCloudBackup: Bool = false
    var debugLogEnabled: Bool = false
    /// 활성 계정 폴링 시 Keychain 에서 live 토큰을 읽을지 여부.
    /// false: 파일(`~/.claude/.credentials.json`) 만 사용 — Keychain 프롬프트 없음, 단 토큰 refresh 후
    /// Claude Code 가 파일을 갱신하지 않으면 stale → 401 가능 (자동 backoff 후 복구 시도).
    /// true: 기존 동작 — Keychain 우선 read (live 토큰 보장, 단 ACL prompt 발생 가능).
    var useKeychainLiveTokens: Bool = false
    /// 토큰 만료 임박 / 401 시 refresh_token 으로 자동 갱신. 비활성 계정도 항상 fresh 유지.
    /// false 시 비활성 계정은 expiresAt 도달 후 영구 401 (스위치 전까지).
    var useAutoRefresh: Bool = true

    static let defaults = AppSettings()

    /// 임계치 3구간 구조체. UI/계산 모두 이 값만 보면 됨.
    var thresholdConfig: ThresholdConfig {
        ThresholdConfig(caution: thresholdCaution,
                        warning: thresholdWarning,
                        critical: thresholdCritical).clamped()
    }

    enum CodingKeys: String, CodingKey {
        case pollIntervalActiveSeconds, pollIntervalInactiveSeconds, launchAtLogin
        case thresholdCaution, thresholdWarning, thresholdCritical, usageDisplayMode
        case usageVisibility, menuBarStyle, timeFormat, colorOverrides
        case menuBarPrefix, iconAnimation, blinkOnChange, hoverDetail
        case startInBackground, autoUpdateCheck
        case keychainSync, iCloudBackup, debugLogEnabled
        case useKeychainLiveTokens, useAutoRefresh
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pollIntervalActiveSeconds = try c.decodeIfPresent(Int.self, forKey: .pollIntervalActiveSeconds) ?? 60
        pollIntervalInactiveSeconds = try c.decodeIfPresent(Int.self, forKey: .pollIntervalInactiveSeconds) ?? 300
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        thresholdCaution = try c.decodeIfPresent(Int.self, forKey: .thresholdCaution) ?? 50
        thresholdWarning = try c.decodeIfPresent(Int.self, forKey: .thresholdWarning) ?? 80
        thresholdCritical = try c.decodeIfPresent(Int.self, forKey: .thresholdCritical) ?? 95
        usageDisplayMode = try c.decodeIfPresent(UsageDisplayMode.self, forKey: .usageDisplayMode) ?? .used
        usageVisibility = try c.decodeIfPresent(UsageVisibility.self, forKey: .usageVisibility) ?? .both
        menuBarStyle = try c.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle) ?? .percent
        timeFormat = try c.decodeIfPresent(TimeFormatStyle.self, forKey: .timeFormat) ?? .twelveHour
        colorOverrides = try c.decodeIfPresent([String: String].self, forKey: .colorOverrides) ?? [:]
        menuBarPrefix = try c.decodeIfPresent(String.self, forKey: .menuBarPrefix) ?? ""
        iconAnimation = try c.decodeIfPresent(Bool.self, forKey: .iconAnimation) ?? false
        blinkOnChange = try c.decodeIfPresent(Bool.self, forKey: .blinkOnChange) ?? true
        hoverDetail = try c.decodeIfPresent(Bool.self, forKey: .hoverDetail) ?? true
        startInBackground = try c.decodeIfPresent(Bool.self, forKey: .startInBackground) ?? true
        autoUpdateCheck = try c.decodeIfPresent(Bool.self, forKey: .autoUpdateCheck) ?? false
        keychainSync = try c.decodeIfPresent(Bool.self, forKey: .keychainSync) ?? true
        iCloudBackup = try c.decodeIfPresent(Bool.self, forKey: .iCloudBackup) ?? false
        debugLogEnabled = try c.decodeIfPresent(Bool.self, forKey: .debugLogEnabled) ?? false
        useKeychainLiveTokens = try c.decodeIfPresent(Bool.self, forKey: .useKeychainLiveTokens) ?? false
        useAutoRefresh = try c.decodeIfPresent(Bool.self, forKey: .useAutoRefresh) ?? true
    }
}
