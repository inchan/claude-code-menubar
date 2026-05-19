import SwiftUI

/// 한 계정의 표시 카드: 헤더 + 세션/주간 진행률 바 + 리셋 시간.
/// 메뉴바 드롭다운과 설정창에서 공통 사용.
enum ProgressLayout { case auto, verticalOnly }

private enum CardTokens {
    static let claudeAccent = Color(red: 0.80, green: 0.47, blue: 0.36)
    static let claudeAccentSoft = Color(red: 0.80, green: 0.47, blue: 0.36).opacity(0.14)
    static let activeBadgeBG = Color(red: 0.80, green: 0.47, blue: 0.36).opacity(0.16)
    static let cardFill = Color(nsColor: .textBackgroundColor)
    static let cardStroke = Color.primary.opacity(0.08)
    static let trackColor = Color.primary.opacity(0.08)
}

struct AccountUsageCard: View {
    let account: Account
    let isActive: Bool
    let usage: UsageSnapshot?
    let error: String?
    let mode: UsageDisplayMode
    let visibility: UsageVisibility
    let overrides: [String: String]
    let timeFormat: TimeFormatStyle
    var thresholds: ThresholdConfig = .default
    let onSwitch: (() -> Void)?
    var progressLayout: ProgressLayout = .auto

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            progressRows
            if let err = error, !errorText(err).isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(errorText(err))
                        .font(AppFonts.swiftUI(size: 10, weight: .medium))
                }
                .foregroundColor(.orange)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CardTokens.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? CardTokens.claudeAccent.opacity(0.45) : CardTokens.cardStroke,
                        lineWidth: isActive ? 1.5 : 1)
        )
        .shadow(color: Color.black.opacity(isActive ? 0.06 : 0.03),
                radius: isActive ? 4 : 2, x: 0, y: 1)
    }

    @ViewBuilder
    private var progressRows: some View {
        let session = visibility.showsSession ? sessionRow : nil
        let weekly  = visibility.showsWeekly ? weeklyRow : nil
        if let s = session, let w = weekly {
            switch progressLayout {
            case .verticalOnly:
                VStack(alignment: .leading, spacing: 10) { s; w }
            case .auto:
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        s.frame(maxWidth: .infinity, alignment: .leading)
                        w.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 10) { s; w }
                }
            }
        } else if let s = session {
            s
        } else if let w = weekly {
            w
        }
    }

    private var sessionRow: UsageProgressRow {
        let pct = usage?.fiveHourUtilization
        return UsageProgressRow(
            title: "세션 사용량",
            utilization: pct,
            resetsAt: usage?.fiveHourResetsAt,
            level: pct.map { ThresholdLevel.from(percent: $0, thresholds: thresholds) },
            mode: mode,
            overrides: overrides,
            timeFormat: timeFormat
        )
    }

    private var weeklyRow: UsageProgressRow {
        let pct = usage?.sevenDayUtilization
        return UsageProgressRow(
            title: "주간 사용량",
            utilization: pct,
            resetsAt: usage?.sevenDayResetsAt,
            level: pct.map { ThresholdLevel.from(percent: $0, thresholds: thresholds) },
            mode: mode,
            overrides: overrides,
            timeFormat: timeFormat
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.label)
                        .font(AppFonts.heading(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if isActive {
                        Text("ACTIVE")
                            .font(AppFonts.mono(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(CardTokens.claudeAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(CardTokens.activeBadgeBG)
                            )
                    }
                    Spacer(minLength: 4)
                    if !isActive, let onSwitch {
                        Button(action: onSwitch) {
                            Text("전환")
                                .font(AppFonts.swiftUI(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(CardTokens.claudeAccent)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(account.emailAddress)
                    .font(AppFonts.swiftUI(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var avatar: some View {
        Image(nsImage: StatusIconRenderer.render(initial: account.initial,
                                                 hex: account.colorHex, size: 28,
                                                 warning: error == "keychain_denied"))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    /// keychain_denied 는 usage 가 있어도 stale 이므로 항상 안내.
    /// unauthorized / generic 은 usage 없을 때만 노출 (기존 동작 유지).
    private func errorText(_ err: String) -> String {
        switch err {
        case "keychain_denied":
            return "🔐 Keychain 접근 권한 필요 — '새로고침' 으로 다시 요청"
        case "unauthorized":
            return usage == nil ? "재로그인 필요" : ""
        case "invalid_grant":
            return "🔑 refresh 만료 — Claude Code 로 재로그인 필요"
        case "rate_limited":
            return usage == nil ? "잠시 후 재시도" : ""
        default:
            return usage == nil ? "조회 실패: \(err)" : ""
        }
    }
}

struct UsageProgressRow: View {
    let title: String
    let utilization: Int?
    let resetsAt: Date?
    let level: ThresholdLevel?
    let mode: UsageDisplayMode
    let overrides: [String: String]
    let timeFormat: TimeFormatStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AppFonts.swiftUI(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(percentText)
                    .font(AppFonts.mono(size: 12, weight: .semibold))
                    .foregroundColor(level?.color(overrides: overrides) ?? .secondary)
            }
            ProgressBarShape(percent: utilization ?? 0,
                             color: (level ?? .healthy).color(overrides: overrides))
                .frame(height: 4)
            if let reset = resetsAt {
                Text(formatResetTime(reset))
                    .font(AppFonts.swiftUI(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var percentText: String {
        guard let u = utilization else { return "--%" }
        return "\(mode.display(utilization: u))%"
    }

    private func formatResetTime(_ date: Date) -> String {
        let cal = Calendar.current
        let timeStr = TimeFormat.format(date, style: timeFormat)
        if cal.isDateInToday(date) { return "Today \(timeStr) 리셋" }
        let mo = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return "\(mo)월 \(d), \(timeStr) 리셋"
    }
}

/// 시간 포맷 단일 정의원.
enum TimeFormat {
    static func format(_ date: Date, style: TimeFormatStyle,
                       locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        switch style {
        case .twentyFourHour:
            f.dateFormat = "HH:mm"
        case .twelveHour:
            let isKo = (locale.language.languageCode?.identifier ?? "en") == "ko"
            f.dateFormat = isKo ? "a h:mm" : "h:mm a"
        }
        return f.string(from: date)
    }
}

struct ProgressBarShape: View {
    let percent: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CardTokens.trackColor)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.82)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
            }
        }
    }
}
