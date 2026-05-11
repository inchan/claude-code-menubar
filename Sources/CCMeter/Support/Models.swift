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
    case healthy   // 0..<50  — green
    case caution   // 50..<80 — yellow
    case warning   // 80..<95 — orange
    case critical  // >=95    — red

    static func from(percent: Int) -> ThresholdLevel {
        if percent >= 95 { return .critical }
        if percent >= 80 { return .warning }
        if percent >= 50 { return .caution }
        return .healthy
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
    var thresholdWarning: Int = 80
    var thresholdCritical: Int = 95
    var usageDisplayMode: UsageDisplayMode = .used
    var usageVisibility: UsageVisibility = .both
    var menuBarStyle: MenuBarStyle = .percent
    var timeFormat: TimeFormatStyle = .twelveHour
    /// ThresholdLevel.rawValue → hex (#RRGGBB). nil 또는 누락 시 system default 사용.
    var colorOverrides: [String: String] = [:]

    static let defaults = AppSettings()

    enum CodingKeys: String, CodingKey {
        case pollIntervalActiveSeconds, pollIntervalInactiveSeconds, launchAtLogin
        case thresholdWarning, thresholdCritical, usageDisplayMode
        case usageVisibility, menuBarStyle, timeFormat, colorOverrides
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pollIntervalActiveSeconds = try c.decodeIfPresent(Int.self, forKey: .pollIntervalActiveSeconds) ?? 60
        pollIntervalInactiveSeconds = try c.decodeIfPresent(Int.self, forKey: .pollIntervalInactiveSeconds) ?? 300
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        thresholdWarning = try c.decodeIfPresent(Int.self, forKey: .thresholdWarning) ?? 80
        thresholdCritical = try c.decodeIfPresent(Int.self, forKey: .thresholdCritical) ?? 95
        usageDisplayMode = try c.decodeIfPresent(UsageDisplayMode.self, forKey: .usageDisplayMode) ?? .used
        usageVisibility = try c.decodeIfPresent(UsageVisibility.self, forKey: .usageVisibility) ?? .both
        menuBarStyle = try c.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle) ?? .percent
        timeFormat = try c.decodeIfPresent(TimeFormatStyle.self, forKey: .timeFormat) ?? .twelveHour
        colorOverrides = try c.decodeIfPresent([String: String].self, forKey: .colorOverrides) ?? [:]
    }
}
