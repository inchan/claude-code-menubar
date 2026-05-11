import Foundation
import Combine

/// 활성/비활성 계정의 사용량을 주기적으로 폴링하고 캐시한다.
@MainActor
final class UsageMonitor: ObservableObject {
    @Published private(set) var snapshots: [AccountID: UsageSnapshot] = [:]
    @Published private(set) var lastError: [AccountID: String] = [:]
    private var nextEligibleAt: [AccountID: Date] = [:]

    private weak var accountManager: AccountManager?
    private let client: UsageClientProtocol
    private let snapshotStore: ProfileSnapshotStoreProtocol
    private let settingsStore: SettingsStoreProtocol
    private let clock: ClockProtocol

    private var activeTimer: Timer?
    private var inactiveTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var notificationToken: NSObjectProtocol?

    init(accountManager: AccountManager,
         client: UsageClientProtocol = UsageClient(),
         snapshotStore: ProfileSnapshotStoreProtocol = ProfileSnapshotStore(),
         settingsStore: SettingsStoreProtocol = SettingsStore(),
         clock: ClockProtocol = SystemClock()) {
        self.accountManager = accountManager
        self.client = client
        self.snapshotStore = snapshotStore
        self.settingsStore = settingsStore
        self.clock = clock
        // init 시점에 accounts 가 비어 있어도 OK — 아래 observer 가 reload 시 자동 채움.
        loadCachedSnapshots()
        observeAccountChanges()
        observeAccountListChanges()
    }

    /// 앱 종료 시 AppDelegate 가 명시 호출. deinit 는 Swift 6 isolation 충돌로 미사용.
    func teardown() {
        stop()
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
            notificationToken = nil
        }
        cancellables.removeAll()
    }

    func start() {
        let s = settingsStore.load()
        scheduleActive(every: TimeInterval(s.pollIntervalActiveSeconds))
        scheduleInactive(every: TimeInterval(s.pollIntervalInactiveSeconds))
        Task { await refreshActiveOnce() }
    }

    func stop() {
        activeTimer?.invalidate(); activeTimer = nil
        inactiveTimer?.invalidate(); inactiveTimer = nil
    }

    func refreshActiveOnce() async {
        guard let am = accountManager, let activeID = am.activeAccountID else { return }
        await refresh(accountID: activeID)
    }

    func refreshAllOnce() async {
        guard let am = accountManager else { return }
        let ids = am.accounts.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { [id] in await self.refresh(accountID: id) }
            }
        }
    }

    /// 새 토큰 import / 스위치 직후 호출되어 backoff 를 풀고 즉시 재폴링.
    func invalidateBackoff(for accountID: AccountID) {
        nextEligibleAt[accountID] = nil
        if lastError[accountID] != nil { lastError[accountID] = nil }
        Task { await refresh(accountID: accountID) }
    }

    // MARK: - private

    private func observeAccountChanges() {
        notificationToken = NotificationCenter.default.addObserver(
            forName: .ccAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let id = note.userInfo?["accountID"] as? AccountID
            Task { @MainActor in
                if let id { self.invalidateBackoff(for: id) }
            }
        }
    }

    /// AccountManager.accounts 변경 시 cached snapshots 재로드 + 삭제된 id prune.
    /// init 순서에 의존하지 않도록 — 원천 차단.
    private func observeAccountListChanges() {
        accountManager?.$accounts
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.loadCachedSnapshots() }
            .store(in: &cancellables)
    }

    /// 디스크 캐시 로드 + 삭제된 계정의 dict 항목 prune.
    private func loadCachedSnapshots() {
        guard let am = accountManager else { return }
        let validIDs = Set(am.accounts.map(\.id))
        // prune
        snapshots = snapshots.filter { validIDs.contains($0.key) }
        lastError = lastError.filter { validIDs.contains($0.key) }
        nextEligibleAt = nextEligibleAt.filter { validIDs.contains($0.key) }
        // load 누락된 것
        for acc in am.accounts where snapshots[acc.id] == nil {
            if let s = try? snapshotStore.readUsage(for: acc.id) {
                snapshots[acc.id] = s
            }
        }
    }

    private func scheduleActive(every seconds: TimeInterval) {
        activeTimer?.invalidate()
        activeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshActiveOnce() }
        }
        if let t = activeTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func scheduleInactive(every seconds: TimeInterval) {
        inactiveTimer?.invalidate()
        inactiveTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshInactive() }
        }
        if let t = inactiveTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func refreshInactive() async {
        guard let am = accountManager else { return }
        let ids = am.accounts.map(\.id).filter { $0 != am.activeAccountID }
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { [id] in await self.refresh(accountID: id) }
            }
        }
    }

    private func refresh(accountID: AccountID) async {
        Log.usage.info("[REFRESH enter] id=\(accountID, privacy: .public) backoff=\(self.nextEligibleAt[accountID]?.timeIntervalSinceNow ?? -1)")
        if let next = nextEligibleAt[accountID], next > clock.now() {
            Log.usage.info("[REFRESH backoff-skip] id=\(accountID, privacy: .public)")
            return
        }
        // 활성 계정은 ~/.claude/.credentials.json 의 최신 토큰 사용 (Claude Code 가
        // 주기적으로 refresh 하므로 snapshot 의 stale 토큰 사용 시 영구 401 위험).
        let token: String
        let isActive = accountManager?.activeAccountID == accountID
        if isActive,
           let liveData = liveActiveCredentials(),
           let live = try? JSON.decode(ClaudeCredentialsRoot.self, from: liveData) {
            token = live.claudeAiOauth.accessToken
            Log.usage.info("[REFRESH live-token] id=\(accountID, privacy: .public)")
            // 활성 계정 snapshot 도 latest 로 sync (다음 스위치 시 활용)
            if let cur = try? snapshotStore.read(for: accountID) {
                let newSnap = ClaudeProfileSnapshot(oauthAccountJSON: cur.oauthAccountJSON,
                                                    credentialsJSON: liveData)
                try? snapshotStore.write(newSnap, for: accountID)
            }
        } else {
            guard let snap = try? snapshotStore.read(for: accountID),
                  let creds = try? JSON.decode(ClaudeCredentialsRoot.self, from: snap.credentialsJSON)
            else { return }
            token = creds.claudeAiOauth.accessToken
        }
        do {
            let usage = try await client.fetch(accessToken: token)
            Log.usage.info("[REFRESH ok] id=\(accountID, privacy: .public) 5h=\(usage.fiveHourUtilization) 7d=\(usage.sevenDayUtilization ?? -1)")
            if !isSameVisible(usage, snapshots[accountID]) {
                snapshots[accountID] = usage
                try? snapshotStore.writeUsage(usage, for: accountID)
            }
            if lastError[accountID] != nil { lastError[accountID] = nil }
        } catch UsageClientError.unauthorized {
            Log.usage.error("[REFRESH 401] id=\(accountID, privacy: .public)")
            setError(accountID, "unauthorized")
            // 1분 backoff. Claude Code 명령 한 번이면 자동 refresh → 다음 폴링에서 회복.
            nextEligibleAt[accountID] = clock.now().addingTimeInterval(60)
        } catch UsageClientError.rateLimited(let retry) {
            let wait = retry.flatMap { max($0, 30) } ?? 60
            Log.usage.error("[REFRESH 429] id=\(accountID, privacy: .public) wait=\(wait)")
            nextEligibleAt[accountID] = clock.now().addingTimeInterval(wait)
            setError(accountID, "rate_limited")
        } catch {
            Log.usage.error("[REFRESH err] id=\(accountID, privacy: .public) err=\(String(describing: error), privacy: .public)")
            setError(accountID, String(describing: error))
            nextEligibleAt[accountID] = clock.now().addingTimeInterval(120)
        }
    }

    private func liveActiveCredentials() -> Data? {
        try? ClaudeLiveCredentials.readRaw()
    }

    private func setError(_ id: AccountID, _ msg: String) {
        if lastError[id] != msg { lastError[id] = msg }
    }

    /// fetchedAt 외 표시용 필드가 같으면 동일로 간주.
    private func isSameVisible(_ a: UsageSnapshot, _ b: UsageSnapshot?) -> Bool {
        guard let b else { return false }
        return a.fiveHourUtilization == b.fiveHourUtilization
            && a.fiveHourResetsAt == b.fiveHourResetsAt
            && a.sevenDayUtilization == b.sevenDayUtilization
            && a.sevenDayResetsAt == b.sevenDayResetsAt
    }
}
