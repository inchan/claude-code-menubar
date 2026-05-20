import SwiftUI
import AppKit

// MARK: - Claude design tokens (FINAL 시안 단일 정의원: docs/settings-mockups.html)

enum CC {
    // 배경 (slate)
    static let slateDark   = Color(hex: 0x141413)
    static let slateCard   = Color(hex: 0x1E1E1C)
    static let slateElev   = Color(hex: 0x262623).opacity(0.5)

    // 라인
    static let line        = Color.white.opacity(0.06)
    static let lineStrong  = Color.white.opacity(0.10)

    // 텍스트
    static let ivory       = Color(hex: 0xFAF9F5)
    static let text2       = Color(hex: 0xA8A7A1)
    static let text3       = Color(hex: 0x6F6E68)

    // 액센트
    static let clay        = Color(hex: 0xD97757)
    static let claySoft    = Color(hex: 0xD97757).opacity(0.12)
    static let claySoft2   = Color(hex: 0xD97757).opacity(0.06)
    static let accent      = Color(hex: 0xC6613F)

    // 상태
    static let green       = Color(hex: 0x57C28B)
    static let warn        = Color(hex: 0xE0A961)
    static let red         = Color(hex: 0xE5484D)

    // 인터랙션 (mock CSS)
    static let hoverFill   = Color.white.opacity(0.03)  // rgba(255,255,255,0.03)
    static let inputFill   = Color.white.opacity(0.04)  // rgba(255,255,255,0.04)
    static let badgeProBG  = Color.white.opacity(0.06)  // rgba(255,255,255,0.06)
    static let progressTrack = Color.white.opacity(0.05) // pbar bg

    static let cardRadius: CGFloat = 10
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Mono header label (모든 v3-block 헤더, 사이드바 헤더에 공통)

private struct MonoTag: View {
    let text: String
    var color: Color = CC.clay
    var size: CGFloat = 10
    var body: some View {
        Text(text.uppercased())
            .font(AppFonts.mono(size: size, weight: .medium))
            .tracking(1.6) // 0.15em ≈ 1.5pt at 10px
            .foregroundColor(color)
    }
}

// MARK: - Section model

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case accounts, display, system, about

    var id: String { rawValue }
    var label: String {
        switch self {
        case .accounts: return "Accounts"
        case .display:  return "Display"
        case .system:   return "System"
        case .about:    return "About"
        }
    }
    /// SF Symbol — mock 의 dot/square/gear/info 와 가장 가까운 톤.
    var icon: String {
        switch self {
        case .accounts: return "circle.fill"
        case .display:  return "square"
        case .system:   return "gearshape"
        case .about:    return "info.circle"
        }
    }
    var heading: String {
        switch self {
        case .accounts: return "Accounts"
        case .display:  return "Display"
        case .system:   return "System"
        case .about:    return "About"
        }
    }
    var subhead: String {
        switch self {
        case .accounts: return "Live usage across all Claude accounts."
        case .display:  return "메뉴바 표시 방식과 임계치 색상."
        case .system:   return "시작·동기화·데이터 설정."
        case .about:    return "버전·라이선스 정보."
        }
    }
}

// MARK: - Root

struct SettingsView: View {
    @ObservedObject var manager: AccountManager
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var settings: AppSettingsStore
    @State private var selection: SettingsSection = .accounts

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
            Rectangle()
                .fill(CC.line)
                .frame(width: 1)
            ZStack(alignment: .topLeading) {
                CC.slateDark.ignoresSafeArea()
                ScrollView {
                    detailPanel
                        .padding(.horizontal, 32)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .background(CC.slateDark)
        .preferredColorScheme(.dark)
        .frame(minWidth: 720, idealWidth: 920, maxWidth: .infinity,
               minHeight: 480, idealHeight: 680, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // mock v2-side-h: padding 6px 10px 10px, tracking 0.12em (=1.2pt at 10px)
            Text("PREFERENCES")
                .font(AppFonts.mono(size: 10, weight: .medium))
                .tracking(1.2)
                .foregroundColor(CC.text3)
                .padding(.horizontal, 10)
                .padding(.top, 6 + 14)   // v2-side padding 14 + 헤더 자체 6
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(SettingsSection.allCases) { sec in
                    SidebarItem(section: sec, isSelected: selection == sec) {
                        selection = sec
                    }
                }
            }
            .padding(.horizontal, 10)   // mock v2-side padding 14 10
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.015).ignoresSafeArea())
    }

    @ViewBuilder
    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.heading)
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundColor(CC.ivory)
                    Text(selection.subhead)
                        .font(.system(size: 12))
                        .foregroundColor(CC.text2)
                }
                Spacer()
                if selection == .accounts {
                    StreamingPill(monitor: monitor, activeID: manager.activeAccountID)
                }
            }
            Group {
                switch selection {
                case .accounts: AccountsPanel(manager: manager, monitor: monitor, settings: settings)
                case .display:  DisplayPanel(settings: settings)
                case .system:   SystemPanel(settings: settings)
                case .about:    AboutPanel()
                }
            }
            .transaction { $0.animation = nil }
            .animation(nil, value: selection)
        }
    }
}

// MARK: - Streaming pill (헤더 우측 green pulse)

private struct StreamingPill: View {
    @ObservedObject var monitor: UsageMonitor
    let activeID: AccountID?
    @State private var pulse = false

    var body: some View {
        let fetched = activeID.flatMap { monitor.snapshots[$0]?.fetchedAt }
        HStack(spacing: 7) {
            Circle()
                .fill(CC.green)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                           value: pulse)
            // 5초마다만 갱신 — sibling 레이아웃 흔들림 최소화
            TimelineView(.periodic(from: .now, by: 5)) { ctx in
                Text(label(fetched: fetched, now: ctx.date))
                    .font(AppFonts.mono(size: 11))
                    .foregroundColor(CC.green)
                    .monospacedDigit()
            }
        }
        .frame(width: 130, alignment: .trailing)
        .onAppear { pulse = true }
    }

    private func label(fetched: Date?, now: Date) -> String {
        guard let f = fetched, f != .distantPast else { return "waiting" }
        let s = Int(now.timeIntervalSince(f))
        if s < 0 { return "streaming · now" }
        if s < 60  { return "streaming · \(s)s" }
        if s < 3600 { return "streaming · \(s / 60)m" }
        return "idle"
    }
}

// MARK: - Sidebar item

private struct SidebarItem: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? CC.clay : CC.text3)
                    .frame(width: 14)
                Text(section.label)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? CC.clay : (hover ? CC.ivory : CC.text2))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? CC.claySoft : (hover ? CC.hoverFill : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - V3 Block (헤더 mono uppercase + 본문 row 구조)

private struct V3Block<Content: View>: View {
    let title: String
    var action: (label: String, run: () -> Void)? = nil
    var wide: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MonoTag(text: title, color: CC.clay)
                Spacer()
                if let a = action {
                    Button(action: a.run) {
                        Text(a.label)
                            .font(.system(size: 11))
                            .foregroundColor(CC.text3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .overlay(alignment: .bottom) {
                Rectangle().fill(CC.line).frame(height: 1)
            }

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: CC.cardRadius, style: .continuous)
                .fill(CC.slateCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CC.cardRadius, style: .continuous)
                .stroke(CC.line, lineWidth: 1)
        )
    }
}

private struct V3Row<Trailing: View>: View {
    let label: String
    var desc: String? = nil
    var isLast: Bool = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundColor(CC.text2)
                    if let d = desc {
                        Text(d)
                            .font(AppFonts.mono(size: 10))
                            .foregroundColor(CC.text3)
                    }
                }
                Spacer()
                trailing()
            }
            .padding(.vertical, 10)
            if !isLast { Rectangle().fill(CC.line).frame(height: 1) }
        }
    }
}

// MARK: - Segmented (clay fill)

private struct CCSegmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { opt in
                let on = opt.value == selection
                Button {
                    selection = opt.value
                } label: {
                    Text(opt.label)
                        .font(AppFonts.mono(size: 11, weight: on ? .medium : .regular))
                        .foregroundColor(on ? .white : CC.text2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(on ? CC.clay : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(CC.line, lineWidth: 1)
        )
    }
}

private struct CCToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? CC.clay : Color(hex: 0x3A3A37))
                    .frame(width: 30, height: 18)
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .padding(2)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

// MARK: - Accounts panel

private struct AccountsPanel: View {
    @ObservedObject var manager: AccountManager
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var settings: AppSettingsStore
    @State private var selection: AccountID?
    @State private var draftLabel: String = ""
    @State private var lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if manager.accounts.isEmpty {
                emptyState
            } else {
                ForEach(manager.accounts) { acc in
                    AccountCardFinal(
                        account: acc,
                        isActive: acc.id == manager.activeAccountID,
                        isSelected: selection == acc.id,
                        usage: monitor.snapshots[acc.id],
                        error: monitor.lastError[acc.id],
                        mode: settings.settings.usageDisplayMode,
                        visibility: settings.settings.usageVisibility,
                        overrides: settings.settings.colorOverrides,
                        thresholds: settings.settings.thresholdConfig,
                        timeFormat: settings.settings.timeFormat,
                        onSelect: {
                            selection = acc.id
                            draftLabel = acc.label
                        },
                        onSwitch: acc.id == manager.activeAccountID
                            ? nil
                            : { handleSwitch(to: acc.id) }
                    )
                }
            }

            // Add account (dashed border)
            HStack {
                Spacer()
                Button {
                    do { _ = try manager.importCurrent(); lastError = nil }
                    catch { lastError = "가져오기 실패: \(String(describing: error))" }
                } label: {
                    Text("+ 현재 계정 가져오기")
                        .font(.system(size: 12))
                        .foregroundColor(CC.text3)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    do { try manager.openLogin(); lastError = "Terminal 에서 로그인 후 ‘현재 계정 가져오기’ 를 누르세요." }
                    catch { lastError = "Terminal 실행 실패: \(String(describing: error))" }
                } label: {
                    Text("+ 새 계정 로그인")
                        .font(.system(size: 12))
                        .foregroundColor(CC.text3)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(14)
            .overlay(
                RoundedRectangle(cornerRadius: CC.cardRadius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundColor(CC.lineStrong)
            )

            if selection != nil {
                V3Block(title: "Edit") {
                    V3Row(label: "표시 이름") {
                        HStack(spacing: 6) {
                            TextField("회사 / 개인 등", text: $draftLabel)
                                .textFieldStyle(.plain)
                                .font(AppFonts.mono(size: 12))
                                .foregroundColor(CC.ivory)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.white.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(CC.lineStrong, lineWidth: 1)
                                )
                                .frame(width: 200)
                                .onSubmit { rename() }
                            CCButton(label: "변경", style: .primary,
                                     disabled: draftLabel.trimmingCharacters(in: .whitespaces).isEmpty) {
                                rename()
                            }
                        }
                    }
                    V3Row(label: "삭제", isLast: true) {
                        CCButton(label: "Remove",
                                 style: .destructive,
                                 disabled: selection == manager.activeAccountID) {
                            guard let id = selection else { return }
                            if id == manager.activeAccountID {
                                lastError = "활성 계정은 삭제할 수 없습니다."; return
                            }
                            do { try manager.remove(id); selection = nil; draftLabel = ""; lastError = nil }
                            catch { lastError = "삭제 실패: \(String(describing: error))" }
                        }
                    }
                }
            }

            if let err = lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(CC.warn)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(CC.ivory)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CC.warn.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CC.warn.opacity(0.30), lineWidth: 1)
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("등록된 계정이 없습니다")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(CC.text2)
            Text("아래 버튼으로 추가하세요.")
                .font(AppFonts.mono(size: 11))
                .foregroundColor(CC.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: CC.cardRadius, style: .continuous)
                .fill(CC.slateCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CC.cardRadius, style: .continuous)
                .stroke(CC.line, lineWidth: 1)
        )
    }

    private func rename() {
        guard let id = selection else { return }
        let trimmed = draftLabel.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do { try manager.rename(id, to: trimmed); lastError = nil }
        catch { lastError = "이름 변경 실패: \(String(describing: error))" }
    }

    private func handleSwitch(to id: AccountID) {
        do { try manager.switchTo(id); lastError = nil; Task { await monitor.refreshActiveOnce() } }
        catch SwitchError.claudeRunning {
            lastError = "Claude Code 가 실행 중입니다. 모든 세션을 종료한 뒤 다시 시도하세요."
        } catch {
            lastError = "전환 실패: \(String(describing: error))"
        }
    }
}

// MARK: - CC button

private struct CCButton: View {
    enum Style { case primary, ghost, destructive }
    let label: String
    var style: Style = .primary
    var disabled: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)  // mock v2-btn: 7px 14px
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(bg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
    }

    private var bg: Color {
        switch style {
        case .primary:     return hover ? CC.accent : CC.clay  // mock: bg clay, hover accent
        case .ghost:       return .clear
        case .destructive: return .clear
        }
    }
    private var fg: Color {
        switch style {
        case .primary:     return .white
        case .ghost:       return hover ? CC.ivory : CC.text2
        case .destructive: return CC.red
        }
    }
    private var stroke: Color {
        switch style {
        case .primary:     return .clear
        case .ghost:       return hover ? Color.white.opacity(0.2) : CC.lineStrong
        case .destructive: return CC.red.opacity(0.3)
        }
    }
}

// MARK: - Display panel (LAYOUT wide + BEHAVIOR / UPDATE half)

private struct DisplayPanel: View {
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            V3Block(title: "Layout") {
                V3Row(label: "사용량 표시") {
                    CCSegmented(
                        options: UsageDisplayMode.allCases.map { ($0, $0.label) },
                        selection: Binding(
                            get: { settings.settings.usageDisplayMode },
                            set: { settings.setDisplayMode($0) }
                        )
                    )
                }
                V3Row(label: "표시 범위") {
                    CCSegmented(
                        options: UsageVisibility.allCases.map { ($0, $0.label) },
                        selection: Binding(
                            get: { settings.settings.usageVisibility },
                            set: { settings.setVisibility($0) }
                        )
                    )
                }
                V3Row(label: "시간 형식") {
                    CCSegmented(
                        options: TimeFormatStyle.allCases.map { ($0, $0.label) },
                        selection: Binding(
                            get: { settings.settings.timeFormat },
                            set: { settings.setTimeFormat($0) }
                        )
                    )
                }
                V3Row(label: "메뉴바 prefix") {
                    PrefixField(prefix: Binding(
                        get: { settings.settings.menuBarPrefix },
                        set: { settings.setMenuBarPrefix($0) }
                    ))
                }
                V3Row(label: "메뉴바 스타일", isLast: true) {
                    HStack(spacing: 8) {
                        ForEach(MenuBarStyle.allCases, id: \.self) { style in
                            MenuBarStyleTile(
                                style: style,
                                isSelected: settings.settings.menuBarStyle == style,
                                mode: settings.settings.usageDisplayMode,
                                visibility: settings.settings.usageVisibility,
                                colorOverrides: settings.settings.colorOverrides
                            ) {
                                settings.setMenuBarStyle(style)
                            }
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                V3Block(title: "Behavior") {
                    V3Row(label: "아이콘 애니메이션",
                          desc: "메뉴바 아이콘이 1.6s 주기로 호흡") {
                        CCToggle(isOn: Binding(
                            get: { settings.settings.iconAnimation },
                            set: { settings.setIconAnimation($0) }
                        ))
                    }
                    V3Row(label: "사용량 변동 시 깜빡임",
                          desc: "새로고침마다 짧게 페이드") {
                        CCToggle(isOn: Binding(
                            get: { settings.settings.blinkOnChange },
                            set: { settings.setBlinkOnChange($0) }
                        ))
                    }
                    V3Row(label: "호버 시 상세 표시",
                          desc: "툴팁에 사용률·리셋 시각",
                          isLast: true) {
                        CCToggle(isOn: Binding(
                            get: { settings.settings.hoverDetail },
                            set: { settings.setHoverDetail($0) }
                        ))
                    }
                }
                V3Block(title: "Update") {
                    V3Row(label: "새로고침 주기") {
                        IntervalField(seconds: Binding(
                            get: { settings.settings.pollIntervalActiveSeconds },
                            set: { settings.setPollInterval(active: $0) }
                        ))
                    }
                    V3Row(label: "유휴 시 주기") {
                        IntervalField(seconds: Binding(
                            get: { settings.settings.pollIntervalInactiveSeconds },
                            set: { settings.setPollInterval(inactive: $0) }
                        ))
                    }
                    V3Row(label: "백오프", isLast: true) {
                        Text("exp")
                            .font(AppFonts.mono(size: 12))
                            .foregroundColor(CC.ivory)
                    }
                }
            }

            // 사용률(utilization) 기준 임계치 색상 — Display 패널 하단으로 통합
            ThresholdsCard(settings: settings)
        }
    }
}

/// "cc" 같은 prefix 짧은 input. 72px center mono.
private struct PrefixField: View {
    @Binding var prefix: String
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(AppFonts.mono(size: 12))
            .foregroundColor(CC.ivory)
            .frame(width: 72)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(focused ? CC.clay : CC.lineStrong, lineWidth: 1)
            )
            .focused($focused)
            .onAppear { draft = prefix }
            .onChange(of: prefix) { new in
                if !focused { draft = new }
            }
            .onSubmit { prefix = String(draft.prefix(6)) }
            .onChange(of: focused) { f in
                if !f { prefix = String(draft.prefix(6)) }
            }
    }
}

/// 새로고침 주기 표시/편집. "30s" / "5m" 표기.
private struct IntervalField: View {
    @Binding var seconds: Int
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(AppFonts.mono(size: 12))
            .foregroundColor(CC.ivory)
            .frame(width: 64)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(focused ? CC.clay : CC.lineStrong, lineWidth: 1)
            )
            .focused($focused)
            .onAppear { draft = format(seconds) }
            .onChange(of: seconds) { new in
                if !focused { draft = format(new) }
            }
            .onSubmit { commit() }
            .onChange(of: focused) { f in
                if !f { commit() }
            }
    }

    private func format(_ s: Int) -> String {
        if s % 60 == 0, s >= 60 { return "\(s / 60)m" }
        return "\(s)s"
    }

    private func commit() {
        let t = draft.trimmingCharacters(in: .whitespaces).lowercased()
        if let parsed = parse(t) {
            seconds = parsed
            draft = format(parsed)
        } else {
            draft = format(seconds)
        }
    }

    private func parse(_ s: String) -> Int? {
        if s.hasSuffix("m"), let n = Int(s.dropLast()) { return n * 60 }
        if s.hasSuffix("s"), let n = Int(s.dropLast()) { return n }
        if let n = Int(s) { return n }
        return nil
    }
}

// MARK: - Thresholds card (Display 패널 내부로 통합)

private struct ThresholdsCard: View {
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        let isPristine = settings.settings.colorOverrides.isEmpty
            && settings.settings.thresholdConfig == .default
        return V3Block(
            title: "Thresholds",
            action: isPristine
                ? nil
                : (label: "reset", run: {
                    settings.resetColorOverrides()
                    settings.resetThresholds()
                })
        ) {
            // Safe at 은 시작점이라 % 편집 없음 (항상 0)
            ThresholdEditRow(
                label: "Safe at",
                level: .healthy,
                percent: 0,
                isEditable: false,
                isLast: false,
                settings: settings
            )
            ThresholdEditRow(
                label: "Warn at",
                level: .caution,
                percent: settings.settings.thresholdCaution,
                isEditable: true,
                isLast: false,
                settings: settings
            )
            ThresholdEditRow(
                label: "Danger at",
                level: .warning,
                percent: settings.settings.thresholdWarning,
                isEditable: true,
                isLast: false,
                settings: settings
            )
            ThresholdEditRow(
                label: "Critical at",
                level: .critical,
                percent: settings.settings.thresholdCritical,
                isEditable: true,
                isLast: true,
                settings: settings
            )
        }
    }
}

/// Mock 의 cl-row: 라벨 좌측, 우측에 swatch + % input + 컬러된 % 기호.
private struct ThresholdEditRow: View {
    let label: String
    let level: ThresholdLevel
    let percent: Int
    let isEditable: Bool
    let isLast: Bool
    @ObservedObject var settings: AppSettingsStore
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        V3Row(label: label, isLast: isLast) {
            HStack(spacing: 8) {
                ColorSwatch(
                    color: level.color(overrides: settings.settings.colorOverrides),
                    onPick: { hex in
                        settings.setColorOverride(level, hex: hex)
                    }
                )
                if isEditable {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(AppFonts.mono(size: 13))
                        .foregroundColor(CC.ivory)
                        .frame(width: 44)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(focused ? CC.clay : CC.lineStrong, lineWidth: 1)
                        )
                        .focused($focused)
                        .onAppear { draft = String(percent) }
                        .onChange(of: percent) { new in
                            if !focused { draft = String(new) }
                        }
                        .onSubmit { commit() }
                        .onChange(of: focused) { isFocused in
                            if !isFocused { commit() }
                        }
                } else {
                    Text("\(percent)")
                        .font(AppFonts.mono(size: 13))
                        .foregroundColor(CC.text2)
                        .frame(width: 44)
                        .padding(.vertical, 4)
                }
                Text("%")
                    .font(AppFonts.mono(size: 13))
                    .foregroundColor(level.color(overrides: settings.settings.colorOverrides))
            }
        }
    }

    private func commit() {
        guard isEditable else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if let n = Int(trimmed), n >= 1, n <= 99 {
            settings.setThreshold(level, percent: n)
        }
        // clamped 결과 반영
        draft = String({
            switch level {
            case .caution:  return settings.settings.thresholdCaution
            case .warning:  return settings.settings.thresholdWarning
            case .critical: return settings.settings.thresholdCritical
            default: return 0
            }
        }())
    }
}

/// mock cl-swatch: 18x18 border-radius 5 + slate-line-strong stroke.
private struct ColorSwatch: View {
    let color: Color
    let onPick: (String) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(CC.lineStrong, lineWidth: 1)
                )
            ColorPicker("", selection: Binding<Color>(
                get: { color },
                set: { onPick(NSColor($0).hexString) }
            ), supportsOpacity: false)
                .labelsHidden()
                .opacity(0.02)
                .frame(width: 18, height: 18)
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: - System panel

private struct SystemPanel: View {
    @ObservedObject var settings: AppSettingsStore
    @State private var error: String?
    @State private var info: String?
    @State private var statusTick: Int = 0  // BTM 상태 재조회 트리거

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                V3Block(title: "Startup") {
                    V3Row(label: "로그인 시 자동 실행") {
                        CCToggle(isOn: Binding(
                            get: {
                                // 디스크 의도 + 시스템 실제 등록 둘 다 충족해야 on.
                                // 재설치/재서명 후 stale 등록 상태 노출 회피.
                                _ = statusTick
                                return settings.settings.launchAtLogin
                                    && LaunchAtLoginService.isEnabled
                            },
                            set: { newVal in
                                do {
                                    try LaunchAtLoginService.setEnabled(newVal)
                                    settings.setLaunchAtLogin(newVal)
                                    error = nil
                                } catch {
                                    self.error = LaunchAtLoginService.requiresUserApproval
                                        ? "시스템 설정 → 일반 → 로그인 항목 에서 Claude Code Menubar 허용 필요"
                                        : "설정 실패: \(String(describing: error))"
                                }
                                statusTick += 1
                            }
                        ))
                    }
                    V3Row(label: "백그라운드 시작") {
                        CCToggle(isOn: Binding(
                            get: { settings.settings.startInBackground },
                            set: { settings.setStartInBackground($0) }
                        ))
                    }
                    V3Row(label: "업데이트 자동 확인", isLast: true) {
                        CCToggle(isOn: Binding(
                            get: { settings.settings.autoUpdateCheck },
                            set: { settings.setAutoUpdateCheck($0) }
                        ))
                    }
                }
                V3Block(title: "Sync") {
                    V3Row(label: "Keychain 동기화") {
                        CCToggle(isOn: Binding(
                            get: { settings.settings.keychainSync },
                            set: { settings.setKeychainSync($0) }
                        ))
                    }
                    V3Row(label: "폴링 시 Keychain 사용") {
                        CCToggle(isOn: Binding(
                            get: { settings.settings.useKeychainLiveTokens },
                            set: { settings.setUseKeychainLiveTokens($0) }
                        ))
                    }
                    V3Row(label: "토큰 자동 refresh") {
                        CCToggle(isOn: Binding(
                            get: { settings.settings.useAutoRefresh },
                            set: { settings.setUseAutoRefresh($0) }
                        ))
                    }
                    V3Row(label: "iCloud 설정 백업") {
                        CCToggle(isOn: Binding(
                            get: { settings.settings.iCloudBackup },
                            set: { settings.setICloudBackup($0) }
                        ))
                    }
                    V3Row(label: "디버그 로그", isLast: true) {
                        CCToggle(isOn: Binding(
                            get: { settings.settings.debugLogEnabled },
                            set: { settings.setDebugLogEnabled($0) }
                        ))
                    }
                }
            }

            V3Block(
                title: "Data",
                action: (label: "reveal in Finder", run: { revealInFinder() })
            ) {
                V3Row(label: "설정 폴더") {
                    Text(prettyPath(Paths.appRoot.path))
                        .font(AppFonts.mono(size: 11))
                        .foregroundColor(CC.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                V3Row(label: "설정 파일") {
                    Text(fileSize(Paths.settingsFile))
                        .font(AppFonts.mono(size: 12))
                        .foregroundColor(CC.ivory)
                }
                V3Row(label: "계정 파일", isLast: true) {
                    Text(fileSize(Paths.accountsFile))
                        .font(AppFonts.mono(size: 12))
                        .foregroundColor(CC.ivory)
                }
            }

            V3Block(title: "Actions") {
                HStack(spacing: 8) {
                    CCButton(label: "Export settings…", style: .ghost) { exportSettings() }
                    CCButton(label: "Import settings…", style: .ghost) { importSettings() }
                    Spacer()
                    CCButton(label: "Reset usage data", style: .destructive) { resetUsageData() }
                }
                .padding(.vertical, 6)
            }

            if LaunchAtLoginService.requiresUserApproval {
                Banner(text: "⚠️ 시스템 설정 → 일반 → 로그인 항목 에서 Claude Code Menubar 활성화가 필요합니다", kind: .error)
                CCButton(label: "시스템 설정 → 로그인 항목 열기", style: .ghost) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            if let info = info {
                Banner(text: info, kind: .info)
            }
            if let err = error {
                Banner(text: err, kind: .error)
            }
        }
        .onAppear { statusTick += 1 }
    }

    private func resetUsageData() {
        let alert = NSAlert()
        alert.messageText = "사용량 데이터를 초기화하시겠습니까?"
        alert.informativeText = "로컬 스냅샷 캐시가 삭제됩니다. Claude 계정 자체에는 영향이 없습니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "초기화")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if FileManager.default.fileExists(atPath: Paths.snapshotsDir.path) {
                try FileManager.default.removeItem(at: Paths.snapshotsDir)
            }
            info = "사용량 캐시 초기화 완료"
            error = nil
        } catch {
            self.error = "초기화 실패: \(String(describing: error))"
            info = nil
        }
    }

    private func prettyPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    private func fileSize(_ url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else { return "—" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.2f MB", Double(size) / 1024 / 1024)
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Paths.appRoot])
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.title = "Export Claude Code Menubar settings"
        panel.nameFieldStringValue = "ccmeter-settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try FileManager.default.copyItem(at: Paths.settingsFile, to: dest)
            info = "내보내기 완료: \(dest.lastPathComponent)"
            error = nil
        } catch {
            self.error = "내보내기 실패: \(String(describing: error))"
            info = nil
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.title = "Import Claude Code Menubar settings"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let src = panel.url else { return }
        do {
            let data = try Data(contentsOf: src)
            let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
            try settings.replaceAll(decoded)
            info = "가져오기 완료: \(src.lastPathComponent)"
            error = nil
        } catch {
            self.error = "가져오기 실패: \(String(describing: error))"
            info = nil
        }
    }
}

private struct Banner: View {
    enum Kind { case info, error }
    let text: String
    let kind: Kind
    var body: some View {
        let (icon, color): (String, Color) = {
            switch kind {
            case .info:  return ("info.circle.fill", CC.clay)
            case .error: return ("exclamationmark.triangle.fill", CC.red)
            }
        }()
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(CC.ivory)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - About panel

private struct AboutPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            V3Block(
                title: "App",
                action: (label: "check for updates", run: { checkForUpdates() })
            ) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [CC.clay, CC.accent],
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .frame(width: 48, height: 48)
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Code Menubar")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(CC.ivory)
                        Text("Claude usage meter for macOS menubar")
                            .font(AppFonts.mono(size: 11))
                            .foregroundColor(CC.text2)
                    }
                    Spacer()
                    badge("v \(versionShort)", style: .max)
                    badge(buildNumber, style: .pro)
                }
                .padding(.vertical, 8)
            }

            HStack(alignment: .top, spacing: 12) {
                V3Block(title: "Meta") {
                    V3Row(label: "Bundle ID") {
                        Text(Bundle.main.bundleIdentifier ?? "?")
                            .font(AppFonts.mono(size: 11))
                            .foregroundColor(CC.ivory)
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    V3Row(label: "License") {
                        Text("MIT")
                            .font(AppFonts.mono(size: 12))
                            .foregroundColor(CC.ivory)
                    }
                    V3Row(label: "Author", isLast: true) {
                        Text("inchan")
                            .font(AppFonts.mono(size: 12))
                            .foregroundColor(CC.ivory)
                    }
                }
                V3Block(title: "Links") {
                    linkRow(label: "Repository",
                            url: "https://github.com/inchan/cc-meter",
                            cta: "github")
                    linkRow(label: "Release notes",
                            url: "https://github.com/inchan/cc-meter/releases",
                            cta: "view")
                    linkRow(label: "Report issue",
                            url: "https://github.com/inchan/cc-meter/issues/new",
                            cta: "new",
                            isLast: true)
                }
            }

            V3Block(title: "Credits") {
                V3Row(label: "Design inspiration") {
                    Text("Claude Code · Anthropic")
                        .font(AppFonts.mono(size: 12))
                        .foregroundColor(CC.text3)
                }
                V3Row(label: "Built with", isLast: true) {
                    Text("Swift · SwiftUI · AppKit")
                        .font(AppFonts.mono(size: 12))
                        .foregroundColor(CC.text3)
                }
            }
        }
    }

    private func checkForUpdates() {
        if let u = URL(string: "https://github.com/inchan/cc-meter/releases/latest") {
            NSWorkspace.shared.open(u)
        }
    }

    private func linkRow(label: String, url: String, cta: String, isLast: Bool = false) -> some View {
        V3Row(label: label, isLast: isLast) {
            Button {
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            } label: {
                HStack(spacing: 4) {
                    Text(cta)
                        .font(AppFonts.mono(size: 11))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(CC.clay)
            }
            .buttonStyle(.plain)
        }
    }

    private enum BadgeStyle { case max, pro }
    private func badge(_ text: String, style: BadgeStyle) -> some View {
        let (bg, fg): (Color, Color) = {
            switch style {
            case .max: return (CC.claySoft, CC.clay)
            case .pro: return (Color.white.opacity(0.06), CC.text2)
            }
        }()
        return Text(text)
            .font(AppFonts.mono(size: 10, weight: .medium))
            .tracking(0.4)
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(bg)
            )
    }

    private var versionShort: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }
    private var buildHash: String { "build \(buildNumber)" }
}

// MARK: - Account card (FINAL: column layout)

private struct AccountCardFinal: View {
    let account: Account
    let isActive: Bool
    let isSelected: Bool
    let usage: UsageSnapshot?
    let error: AccountError?
    let mode: UsageDisplayMode
    let visibility: UsageVisibility
    let overrides: [String: String]
    let thresholds: ThresholdConfig
    let timeFormat: TimeFormatStyle
    let onSelect: () -> Void
    let onSwitch: (() -> Void)?

    private func settingsErrorText(_ err: AccountError) -> String {
        switch err {
        case .keychainDenied: return "Keychain 접근 거부"
        case .unauthorized:   return "재로그인 필요"
        case .invalidGrant:   return "refresh 만료 — 재로그인 필요"
        case .rateLimited:    return "잠시 후 재시도"
        case .other(let m):   return "조회 실패: \(m)"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                header
                progressRows
                if let err = error, usage == nil {
                    Text(settingsErrorText(err))
                        .font(AppFonts.mono(size: 10))
                        .foregroundColor(CC.warn)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CC.cardRadius, style: .continuous)
                    .fill(isActive ? CC.claySoft2 : CC.slateCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CC.cardRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected || isActive ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var borderColor: Color {
        if isSelected { return CC.clay }
        if isActive   { return CC.clay.opacity(0.35) }
        return CC.line
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: StatusIconRenderer.render(initial: account.initial,
                                                     hex: account.colorHex, size: 36))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isActive ? CC.ivory : CC.text2)
                        .lineLimit(1)
                }
                Text(account.emailAddress)
                    .font(AppFonts.mono(size: 11))
                    .foregroundColor(CC.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isActive {
                HStack(spacing: 5) {
                    Circle().fill(CC.green).frame(width: 5, height: 5)
                    Text("Active")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(CC.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(CC.green.opacity(0.12))
                )
                .overlay(Capsule().stroke(CC.green.opacity(0.3), lineWidth: 1))
            } else if let onSwitch {
                CCButton(label: "Switch", style: .primary, action: onSwitch)
            }
        }
    }

    @ViewBuilder
    private var progressRows: some View {
        VStack(spacing: 14) {
            if visibility.showsSession {
                progressBlock(tag: "session",
                              utilization: usage?.fiveHourUtilization,
                              reset: usage?.fiveHourResetsAt,
                              isPrimary: true)
            }
            if visibility.showsWeekly {
                progressBlock(tag: "weekly",
                              utilization: usage?.sevenDayUtilization,
                              reset: usage?.sevenDayResetsAt,
                              isPrimary: !visibility.showsSession)
            }
        }
    }

    /// mock: [progress bar 1fr] [큰 % (15px clay)] / [resets in ...] [● live]
    private func progressBlock(tag: String,
                               utilization: Int?,
                               reset: Date?,
                               isPrimary: Bool) -> some View {
        let level = utilization.map { ThresholdLevel.from(percent: $0, thresholds: thresholds) }
        let color = (level ?? .healthy).color(overrides: overrides)
        let pct = utilization ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.05))
                        Capsule()
                            .fill(color)
                            .frame(width: max(0, geo.size.width * CGFloat(min(max(pct, 0), 100)) / 100))
                    }
                }
                .frame(height: 6)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(mode.display(utilization: pct))")
                        .font(AppFonts.mono(size: isPrimary ? 16 : 13, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundColor(utilization == nil ? CC.text3 : color)
                    Text("%")
                        .font(AppFonts.mono(size: 11))
                        .foregroundColor(utilization == nil ? CC.text3 : color.opacity(0.85))
                }
                .frame(width: 60, alignment: .trailing)
            }
            HStack {
                HStack(spacing: 6) {
                    MonoTag(text: tag, color: CC.text3, size: 9)
                    if let reset = reset {
                        Text("resets \(formatReset(reset))")
                            .font(AppFonts.mono(size: 10))
                            .foregroundColor(CC.text3)
                    }
                }
                Spacer()
                if isActive && isPrimary {
                    HStack(spacing: 6) {
                        // mock: dot.live = bg clay + box-shadow 0 0 0 3px clay-soft
                        Circle()
                            .fill(CC.clay)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle()
                                    .stroke(CC.claySoft, lineWidth: 3)
                            )
                        Text("live")
                            .font(AppFonts.mono(size: 10))
                    }
                    .foregroundColor(CC.clay)
                }
            }
        }
    }

    private func formatReset(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        if diff > 0, diff < 86400 {
            let h = Int(diff) / 3600
            let m = (Int(diff) % 3600) / 60
            if h > 0 { return "in \(h)h \(m)m" }
            return "in \(m)m"
        }
        let cal = Calendar.current
        let timeStr = TimeFormat.format(date, style: timeFormat)
        if cal.isDateInToday(date) { return "today \(timeStr)" }
        let mo = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return "\(mo)/\(d) \(timeStr)"
    }
}

// MARK: - Menu bar style tile

private struct MenuBarStyleTile: View {
    let style: MenuBarStyle
    let isSelected: Bool
    let mode: UsageDisplayMode
    let visibility: UsageVisibility
    let colorOverrides: [String: String]
    let onTap: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                Image(nsImage: StatusIconRenderer.renderStatusBar(
                    initial: "I", hex: "#5AC8FA",
                    fiveHour: visibility.showsSession ? mode.display(utilization: 50) : nil,
                    fiveLevel: visibility.showsSession ? .caution : nil,
                    sevenDay: visibility.showsWeekly ? mode.display(utilization: 16) : nil,
                    sevenLevel: visibility.showsWeekly ? .healthy : nil,
                    style: style,
                    colorOverrides: colorOverrides
                ))
                .renderingMode(.original)
                Text(style.label)
                    .font(AppFonts.mono(size: 10, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? CC.clay : CC.text2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? CC.claySoft : Color.white.opacity(hover ? 0.04 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? CC.clay.opacity(0.4) : CC.line,
                            lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
