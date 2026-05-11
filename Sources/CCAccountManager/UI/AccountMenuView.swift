import SwiftUI
import AppKit

/// 메뉴바 popover — 모든 계정의 사용량 카드 list.
struct AccountMenuView: View {
    @ObservedObject var manager: AccountManager
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var settings: AppSettingsStore
    @State private var lastOpenedAt: Date = .distantPast
    @State private var lastError: String?

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
            try manager.switchTo(id)
            lastError = nil
            Task { await monitor.refreshActiveOnce() }
        } catch SwitchError.claudeRunning {
            lastError = "Claude Code 가 실행 중입니다. 모든 세션 종료 후 재시도."
        } catch {
            lastError = "전환 실패: \(String(describing: error))"
        }
    }
}
