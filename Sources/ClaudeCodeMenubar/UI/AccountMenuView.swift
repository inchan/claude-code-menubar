import SwiftUI
import AppKit

/// 메뉴바 popover — 모든 계정의 사용량 카드 list.
struct AccountMenuView: View {
    @ObservedObject var manager: AccountManager
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var settings: AppSettingsStore
    @State private var lastOpenedAt: Date = .distantPast
    @State private var lastError: String?
    @State private var isRefreshing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if manager.accounts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(orderedAccounts) { acc in
                            AccountUsageCard(
                                account: acc,
                                isActive: acc.id == manager.activeAccountID,
                                usage: monitor.snapshots[acc.id],
                                error: monitor.lastError[acc.id],
                                mode: settings.settings.usageDisplayMode,
                                visibility: settings.settings.usageVisibility,
                                overrides: settings.settings.colorOverrides,
                                timeFormat: settings.settings.timeFormat,
                                thresholds: settings.settings.thresholdConfig,
                                onSwitch: acc.id == manager.activeAccountID
                                    ? nil
                                    : { handleSwitch(to: acc.id) },
                                progressLayout: .verticalOnly
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 420)
            }
            if let err = lastError {
                Text(err).font(AppFonts.swiftUI(size: 10)).foregroundColor(.orange)
            }
            Divider()
            actionRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 240, idealWidth: 240, maxWidth: 240, alignment: .leading)
        .onAppear {
            let now = Date()
            if now.timeIntervalSince(lastOpenedAt) > 5 {
                manager.reload()
                Task { await monitor.refreshAllOnce() }
                lastOpenedAt = now
            }
        }
    }

    /// 활성 계정 먼저, 그 다음 lastUsedAt 순.
    private var orderedAccounts: [Account] {
        let active = manager.activeAccountID
        return manager.accounts.sorted {
            if $0.id == active { return true }
            if $1.id == active { return false }
            return ($0.lastUsedAt ?? $0.addedAt) > ($1.lastUsedAt ?? $1.addedAt)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("등록된 계정이 없습니다").font(AppFonts.swiftUI(size: 12))
            Text("설정 → 계정에서 ‘현재 계정 가져오기’ 를 눌러 추가하세요.")
                .font(AppFonts.swiftUI(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 16)
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task {
                    isRefreshing = true
                    await monitor.refreshAllForcing()
                    isRefreshing = false
                }
            } label: {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRefreshing ? "새로고침 중…" : "새로고침")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r")
            .disabled(isRefreshing)

            Button {
                SettingsWindowController.shared.show(manager: manager,
                                                     monitor: monitor,
                                                     settings: settings)
            } label: {
                Label("설정", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",")

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("종료", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
    }

    private func handleSwitch(to id: AccountID) {
        do {
            try performSwitch(to: id)
        } catch SwitchError.claudeRunning {
            // Claude CLI 가 stale 토큰을 캐시하면 401 또는 사용량 카운팅 오류 가능.
            // 사용자 확인 후에만 우회 — UI 가 우회 경로의 유일한 게이트.
            guard confirmForceSwitch() else {
                lastError = "Claude Code 가 실행 중입니다. 모든 세션 종료 후 재시도."
                return
            }
            do {
                try performSwitch(to: id, allowWhileClaudeRunning: true)
            } catch {
                lastError = "강제 전환 실패: \(String(describing: error))"
            }
        } catch {
            lastError = "전환 실패: \(String(describing: error))"
        }
    }

    private func performSwitch(to id: AccountID, allowWhileClaudeRunning: Bool = false) throws {
        try manager.switchTo(id, allowWhileClaudeRunning: allowWhileClaudeRunning)
        lastError = nil
        Task { await monitor.refreshActiveOnce() }
    }

    private func confirmForceSwitch() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Claude Code 실행 중 — 강제 전환"
        alert.informativeText = """
        실행 중인 Claude Code 세션이 감지되었습니다.

        강제 전환하면 진행 중인 세션이 이전 토큰을 캐시한 상태로 남아 401 \
        또는 사용량 카운팅 오류가 발생할 수 있습니다. 가능하면 진행 중인 \
        응답을 마친 뒤 전환하시길 권장합니다.

        그래도 지금 전환하시겠습니까?
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "강제 전환")
        alert.addButton(withTitle: "취소")
        // macOS 14+ 의 무인자 activate() 가 권장. 메뉴바 앱이 background 일 때
        // alert 가 뒤에 숨지 않도록 명시 활성화.
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        alert.window.level = .floating
        return alert.runModal() == .alertFirstButtonReturn
    }
}
