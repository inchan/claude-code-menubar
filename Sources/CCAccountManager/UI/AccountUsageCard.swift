import SwiftUI

/// 한 계정의 표시 카드: 헤더 + 세션/주간 진행률 바 + 리셋 시간.
/// 메뉴바 드롭다운과 설정창에서 공통 사용.
enum ProgressLayout { case auto, verticalOnly }

struct AccountUsageCard: View {
    let account: Account
    let isActive: Bool
    let usage: UsageSnapshot?
    let error: String?
    let mode: UsageDisplayMode
    let visibility: UsageVisibility
    let overrides: [String: String]
    let timeFormat: TimeFormatStyle
    let onSwitch: (() -> Void)?
    var progressLayout: ProgressLayout = .auto

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            progressRows
            if let err = error, usage == nil {
                Text(err == "unauthorized" ? "재로그인 필요" : "조회 실패: \(err)")
                    .font(AppFonts.swiftUI(size: 10, weight: .medium))
                    .tracking(0.4)
                    .foregroundColor(.orange)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.08)))
    }

    @ViewBuilder
    private var progressRows: some View {
        let session = visibility.showsSession ? sessionRow : nil
        let weekly  = visibility.showsWeekly ? weeklyRow : nil
        // 둘 다일 때만 가로 우선, 폭 부족 시 세로. 한 쪽만이면 그대로 단일.
        if let s = session, let w = weekly {
            switch progressLayout {
            case .verticalOnly:
                VStack(alignment: .leading, spacing: 8) { s; w }
            case .auto:
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        s.frame(maxWidth: .infinity, alignment: .leading)
                        w.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 8) { s; w }
                }
            }
        } else if let s = session {
            s
        } else if let w = weekly {
            w
        }
    }

    private var sessionRow: UsageProgressRow {
        UsageProgressRow(title: "세션 사용량",
                         utilization: usage?.fiveHourUtilization,
                         resetsAt: usage?.fiveHourResetsAt,
                         level: usage?.fiveHourLevel,
                         mode: mode,
                         overrides: overrides,
                         timeFormat: timeFormat)
    }

    private var weeklyRow: UsageProgressRow {
        UsageProgressRow(title: "주간 사용량",
                         utilization: usage?.sevenDayUtilization,
                         resetsAt: usage?.sevenDayResetsAt,
                         level: usage?.sevenDayLevel,
                         mode: mode,
                         overrides: overrides,
                         timeFormat: timeFormat)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(nsImage: StatusIconRenderer.render(initial: account.initial,
                                                     hex: account.colorHex, size: 16.8))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(account.label)
                        .font(AppFonts.swiftUI(size: 13, weight: .semibold))
                        .tracking(0.4)
                    if isActive {
                        Text("활성화")
                            .font(AppFonts.swiftUI(size: 10, weight: .medium))
                            .tracking(0.4)
                            .foregroundColor(.green)
                    }
                    Spacer(minLength: 4)
                    if !isActive, let onSwitch {
                        Button("전환", action: onSwitch)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .font(AppFonts.swiftUI(size: 10, weight: .medium))
                    }
                }
                Text(account.emailAddress)
                    .font(AppFonts.swiftUI(size: 10, weight: .medium))
                    .tracking(0.4)
                    .foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
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
            HStack {
                Text(title)
                    .font(AppFonts.swiftUI(size: 12, weight: .medium))
                    .tracking(0.4)
                Spacer()
                Text(percentText)
                    .font(AppFonts.swiftUI(size: 12, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(level?.color(overrides: overrides) ?? .secondary)
            }
            ProgressBarShape(percent: utilization ?? 0,
                             color: (level ?? .healthy).color(overrides: overrides))
                .frame(height: 3)
            if let reset = resetsAt {
                Text(formatResetTime(reset))
                    .font(AppFonts.swiftUI(size: 10, weight: .medium))
                    .tracking(0.4)
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
/// - 24h: "HH:mm" (locale 무관)
/// - 12h + KO: "오후 10:00"
/// - 12h + 그 외: "10:00 PM"
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
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.18))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
            }
        }
    }
}
