import SwiftUI
import AppKit

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case accounts, display, colors, system, about

    var id: String { rawValue }
    var label: String {
        switch self {
        case .accounts: return "계정"
        case .display:  return "표시"
        case .colors:   return "색상"
        case .system:   return "시스템"
        case .about:    return "정보"
        }
    }
    var icon: String {
        switch self {
        case .accounts: return "person.2"
        case .display:  return "rectangle.3.offgrid"
        case .colors:   return "paintpalette"
        case .system:   return "gearshape"
        case .about:    return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var manager: AccountManager
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var settings: AppSettingsStore
    @State private var selection: SettingsSection = .accounts

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { sec in
                Label(sec.label, systemImage: sec.icon)
                    .tag(sec)
                    .font(AppFonts.swiftUI(size: 13))
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            detailPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
        }
        .navigationSplitViewStyle(.balanced)
        // NSHostingController.sizingOptions = [.preferredContentSize] 가 SwiftUI ideal
        // size 를 host 의 contentSize 로 채택 → 외곽 frame 으로 창 크기 강제.
        .frame(minWidth: 760, idealWidth: 820, maxWidth: .infinity,
               minHeight: 500, idealHeight: 560, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailPanel: some View {
        switch selection {
        case .accounts: AccountsPanel(manager: manager, monitor: monitor, settings: settings)
        case .display:  DisplayPanel(settings: settings)
        case .colors:   ColorsPanel(settings: settings)
        case .system:   SystemPanel(settings: settings)
        case .about:    AboutPanel()
        }
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
        VStack(alignment: .leading, spacing: 12) {
            Text("계정 목록").font(AppFonts.swiftUI(size: 14))

            list
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            displayNameEditor

            actions

            if let err = lastError {
                Text(err)
                    .font(AppFonts.swiftUI(size: 11))
                    .foregroundColor(.red)
            }

            Text("활성 계정은 삭제할 수 없습니다. Claude Code 가 실행 중이면 계정 전환이 차단됩니다.")
                .font(AppFonts.swiftUI(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                if manager.accounts.isEmpty {
                    Text("등록된 계정이 없습니다.\n‘현재 계정 가져오기’ 또는 ‘새 계정 로그인’ 으로 추가하세요.")
                        .foregroundColor(.secondary)
                        .font(AppFonts.swiftUI(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ForEach(manager.accounts) { acc in
                        Button {
                            selection = acc.id
                            draftLabel = acc.label
                        } label: {
                            AccountUsageCard(
                                account: acc,
                                isActive: acc.id == manager.activeAccountID,
                                usage: monitor.snapshots[acc.id],
                                error: monitor.lastError[acc.id],
                                mode: settings.settings.usageDisplayMode,
                                visibility: settings.settings.usageVisibility,
                                overrides: settings.settings.colorOverrides,
                                timeFormat: settings.settings.timeFormat,
                                onSwitch: acc.id == manager.activeAccountID
                                    ? nil
                                    : { handleSwitch(to: acc.id) }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selection == acc.id ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var displayNameEditor: some View {
        HStack(spacing: 6) {
            Text("표시 이름")
                .font(AppFonts.swiftUI(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            TextField("회사 / 개인 등", text: $draftLabel)
                .textFieldStyle(.roundedBorder)
                .disabled(selection == nil)
                .onSubmit { rename() }
            Button("변경") { rename() }
                .disabled(selection == nil || draftLabel.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                do { _ = try manager.importCurrent(); lastError = nil }
                catch { lastError = "가져오기 실패: \(String(describing: error))" }
            } label: { Label("현재 계정 가져오기", systemImage: "square.and.arrow.down") }

            Button {
                do { try manager.openLogin(); lastError = "Terminal 에서 로그인 후 ‘현재 계정 가져오기’ 를 누르세요." }
                catch { lastError = "Terminal 실행 실패: \(String(describing: error))" }
            } label: { Label("새 계정 로그인", systemImage: "person.badge.plus") }

            Spacer()

            Button(role: .destructive) {
                guard let id = selection else { return }
                if id == manager.activeAccountID { lastError = "활성 계정은 삭제할 수 없습니다."; return }
                do { try manager.remove(id); selection = nil; draftLabel = ""; lastError = nil }
                catch { lastError = "삭제 실패: \(String(describing: error))" }
            } label: { Label("삭제", systemImage: "trash") }
                .disabled(selection == nil || selection == manager.activeAccountID)
        }
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

private struct AccountRow: View {
    let account: Account
    let isActive: Bool
    let isSelected: Bool
    let usage: UsageSnapshot?
    let error: String?
    let onSelect: () -> Void
    let onSwitch: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: StatusIconRenderer.render(initial: account.initial,
                                                     hex: account.colorHex, size: 32))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.label).font(AppFonts.swiftUI(size: 13))
                    if isActive {
                        Text("active")
                            .font(AppFonts.swiftUI(size: 10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.green)
                            .clipShape(.rect(cornerRadius: 3))
                    }
                }
                Text(account.emailAddress)
                    .font(AppFonts.swiftUI(size: 11))
                    .foregroundColor(.secondary)
                usageLine
            }
            Spacer()
            if !isActive { Button("전환", action: onSwitch).controlSize(.small) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private var usageLine: some View {
        HStack(spacing: 8) {
            if let u = usage {
                badge("S", u.fiveHourUtilization, u.fiveHourLevel)
                if let v = u.sevenDayUtilization { badge("W", v, u.sevenDayLevel) }
            } else if let err = error {
                Text(err == "unauthorized" ? "재로그인 필요" : "조회 실패")
                    .font(AppFonts.swiftUI(size: 10)).foregroundColor(.orange)
            } else {
                Text("--").font(AppFonts.swiftUI(size: 10)).foregroundColor(.secondary)
            }
        }
    }
    private func badge(_ l: String, _ p: Int, _ lv: ThresholdLevel) -> some View {
        Text("\(l): \(p)%")
            .font(AppFonts.swiftUI(size: 10))
            .foregroundColor(lv.color)
    }
}

// MARK: - Display panel

private struct DisplayPanel: View {
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("표시").font(AppFonts.swiftUI(size: 14))

            row("사용량") {
                Picker("", selection: Binding(
                    get: { settings.settings.usageDisplayMode },
                    set: { settings.setDisplayMode($0) }
                )) {
                    ForEach(UsageDisplayMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }

            row("표시 범위") {
                Picker("", selection: Binding(
                    get: { settings.settings.usageVisibility },
                    set: { settings.setVisibility($0) }
                )) {
                    ForEach(UsageVisibility.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }

            row("시간 형식") {
                Picker("", selection: Binding(
                    get: { settings.settings.timeFormat },
                    set: { settings.setTimeFormat($0) }
                )) {
                    ForEach(TimeFormatStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("메뉴바")
                    .font(AppFonts.swiftUI(size: 11))
                    .foregroundColor(.secondary)
                HStack(spacing: 12) {
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
            Spacer()
        }
    }

    @ViewBuilder
    private func row<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(AppFonts.swiftUI(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            content()
        }
    }
}

// MARK: - Colors panel

private struct ColorsPanel: View {
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("임계치 색상").font(AppFonts.swiftUI(size: 14))
                Spacer()
                Button("기본값으로") { settings.resetColorOverrides() }
                    .controlSize(.small)
                    .disabled(settings.settings.colorOverrides.isEmpty)
            }

            ForEach([ThresholdLevel.healthy, .caution, .warning, .critical], id: \.self) { lv in
                HStack {
                    Text(lv.shortLabel)
                        .font(AppFonts.swiftUI(size: 12))
                        .frame(width: 60, alignment: .leading)
                    ColorPicker("", selection: Binding<Color>(
                        get: { lv.color(overrides: settings.settings.colorOverrides) },
                        set: { settings.setColorOverride(lv, hex: NSColor($0).hexString) }
                    ), supportsOpacity: false).labelsHidden()
                    Text(rangeText(for: lv))
                        .font(AppFonts.swiftUI(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            Text("색상 임계치는 항상 실제 사용률(utilization) 기준입니다.")
                .font(AppFonts.swiftUI(size: 10))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private func rangeText(for lv: ThresholdLevel) -> String {
        switch lv {
        case .healthy:  return "0% – 49%"
        case .caution:  return "50% – 79%"
        case .warning:  return "80% – 94%"
        case .critical: return "95% – 100%"
        }
    }
}

// MARK: - System panel

private struct SystemPanel: View {
    @ObservedObject var settings: AppSettingsStore
    @State private var error: String?
    @State private var statusTick: Int = 0  // BTM 상태 재조회 트리거

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("시스템").font(AppFonts.swiftUI(size: 14))
            Toggle("로그인 시 자동 실행", isOn: Binding(
                get: {
                    // 디스크 의도 + 시스템 실제 등록 상태가 모두 충족되어야 on.
                    // 디스크만 보면 stale 등록 상태에서 사용자가 "on 인데 안 됨" 으로 인지.
                    _ = statusTick
                    return settings.settings.launchAtLogin && LaunchAtLoginService.isEnabled
                },
                set: { newVal in
                    do {
                        try LaunchAtLoginService.setEnabled(newVal)
                        settings.setLaunchAtLogin(newVal)
                        error = nil
                    } catch {
                        self.error = launchAtLoginErrorText(error)
                    }
                    statusTick += 1
                }
            ))
            .font(AppFonts.swiftUI(size: 12))
            if LaunchAtLoginService.requiresUserApproval {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚠️ 시스템 설정에서 로그인 항목 승인이 필요합니다")
                        .font(AppFonts.swiftUI(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                    Button("시스템 설정 → 로그인 항목 열기") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(AppFonts.swiftUI(size: 10))
                }
            }
            if let err = error {
                Text(err).font(AppFonts.swiftUI(size: 10)).foregroundColor(.red)
            }
            Spacer()
        }
        .onAppear { statusTick += 1 }
    }

    private func launchAtLoginErrorText(_ error: Error) -> String {
        if LaunchAtLoginService.requiresUserApproval {
            return "시스템 설정 → 일반 → 로그인 항목 에서 CCMeter 를 허용하세요"
        }
        return "설정 실패: \(String(describing: error))"
    }
}

// MARK: - About panel

private struct AboutPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("정보").font(AppFonts.swiftUI(size: 14))
            HStack {
                Text("이름").font(AppFonts.swiftUI(size: 11)).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
                Text("CCMeter").font(AppFonts.swiftUI(size: 12))
            }
            HStack {
                Text("버전").font(AppFonts.swiftUI(size: 11)).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
                Text(versionString).font(AppFonts.swiftUI(size: 12))
            }
            HStack {
                Text("Bundle ID").font(AppFonts.swiftUI(size: 11)).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
                Text(Bundle.main.bundleIdentifier ?? "?").font(AppFonts.swiftUI(size: 12))
            }
            Spacer()
        }
    }
    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (build \(b))"
    }
}

private struct MenuBarStyleTile: View {
    let style: MenuBarStyle
    let isSelected: Bool
    let mode: UsageDisplayMode
    let visibility: UsageVisibility
    let colorOverrides: [String: String]
    let onTap: () -> Void

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
                    .font(AppFonts.swiftUI(size: 12))
                    .foregroundColor(isSelected ? .accentColor : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
