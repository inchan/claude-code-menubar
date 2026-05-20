import Foundation
import Combine

/// 활성/비활성 계정의 사용량을 주기적으로 폴링하고 캐시한다.
@MainActor
final class UsageMonitor: ObservableObject {
    @Published private(set) var snapshots: [AccountID: UsageSnapshot] = [:]
    @Published private(set) var lastError: [AccountID: AccountError] = [:]
    private var nextEligibleAt: [AccountID: Date] = [:]

    private weak var accountManager: AccountManager?
    private let client: UsageClientProtocol
    private let snapshotStore: ProfileSnapshotStoreProtocol
    private let settingsStore: SettingsStoreProtocol
    private let clock: ClockProtocol
    private let liveCredsReadRaw: @Sendable () -> Data?
    private let keychainProbe: @Sendable () -> ClaudeKeychainCredentials.AccessState
    private let oauthRefresh: ClaudeOAuthRefreshProtocol

    /// per-account refresh 직렬화. 동일 계정 동시 refresh 방지.
    private var refreshInFlight: Set<AccountID> = []

    private var activeTimer: Timer?
    private var inactiveTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var notificationToken: NSObjectProtocol?

    init(accountManager: AccountManager,
         client: UsageClientProtocol = UsageClient(),
         snapshotStore: ProfileSnapshotStoreProtocol = ProfileSnapshotStore(),
         settingsStore: SettingsStoreProtocol = SettingsStore(),
         clock: ClockProtocol = SystemClock(),
         liveCredsReadRaw: @Sendable @escaping () -> Data? = { try? ClaudeLiveCredentials.readRaw() },
         keychainProbe: @Sendable @escaping () -> ClaudeKeychainCredentials.AccessState = ClaudeKeychainCredentials.readDetailed,
         oauthRefresh: ClaudeOAuthRefreshProtocol = ClaudeOAuthRefresh()) {
        self.accountManager = accountManager
        self.client = client
        self.snapshotStore = snapshotStore
        self.settingsStore = settingsStore
        self.clock = clock
        self.liveCredsReadRaw = liveCredsReadRaw
        self.keychainProbe = keychainProbe
        self.oauthRefresh = oauthRefresh
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

    /// 사용자가 메뉴바에서 명시적으로 "새로고침" 클릭한 경우 — 모든 계정의 backoff 클리어 후 즉시 폴링.
    /// 자동 폴링과 달리 rate_limit/invalid_grant backoff 도 무시 (사용자 의도 우선).
    /// await 으로 완료 대기 가능 — UI 가 spinner / disable 인디케이터에 사용.
    func refreshAllForcing() async {
        guard let am = accountManager else { return }
        for id in am.accounts.map(\.id) {
            nextEligibleAt[id] = nil
            if lastError[id] != nil { lastError[id] = nil }
        }
        await refreshAllOnce()
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
        let isActive = accountManager?.activeAccountID == accountID
        let settings = settingsStore.load()
        let useKeychain = settings.useKeychainLiveTokens
        let autoRefresh = settings.useAutoRefresh

        if isActive && useKeychain {
            if case .accessDenied(let status) = keychainProbe() {
                Log.usage.error("[REFRESH keychain-denied] id=\(accountID, privacy: .public) status=\(status)")
                setError(accountID, .keychainDenied)
                nextEligibleAt[accountID] = clock.now().addingTimeInterval(15)
                return
            }
        }
        if let next = nextEligibleAt[accountID], next > clock.now() {
            Log.usage.info("[REFRESH backoff-skip] id=\(accountID, privacy: .public)")
            return
        }

        guard var creds = loadCredentials(accountID: accountID, isActive: isActive, useKeychain: useKeychain) else {
            return
        }

        // 사전 refresh — expiresAt 까지 5분 이내면 호출 전 갱신.
        if autoRefresh && shouldPreRefresh(creds: creds) {
            if let refreshed = await tryRefresh(accountID: accountID, current: creds, isActive: isActive) {
                creds = refreshed
            }
        }

        do {
            let usage = try await client.fetch(accessToken: creds.accessToken)
            Log.usage.info("[REFRESH ok] id=\(accountID, privacy: .public) 5h=\(usage.fiveHourUtilization) 7d=\(usage.sevenDayUtilization ?? -1)")
            if !isSameVisible(usage, snapshots[accountID]) {
                snapshots[accountID] = usage
                try? snapshotStore.writeUsage(usage, for: accountID)
            }
            if lastError[accountID] != nil { lastError[accountID] = nil }
        } catch UsageClientError.unauthorized {
            Log.usage.error("[REFRESH 401] id=\(accountID, privacy: .public) autoRefresh=\(autoRefresh)")
            // 401 → autoRefresh 켜져있으면 1회 refresh 후 재시도.
            if autoRefresh, let refreshed = await tryRefresh(accountID: accountID, current: creds, isActive: isActive) {
                do {
                    let usage = try await client.fetch(accessToken: refreshed.accessToken)
                    Log.usage.info("[REFRESH ok-after-refresh] id=\(accountID, privacy: .public)")
                    snapshots[accountID] = usage
                    try? snapshotStore.writeUsage(usage, for: accountID)
                    if lastError[accountID] != nil { lastError[accountID] = nil }
                    return
                } catch {
                    Log.usage.error("[REFRESH retry-fail] id=\(accountID, privacy: .public) err=\(String(describing: error), privacy: .public)")
                }
            }
            setError(accountID, .unauthorized)
            nextEligibleAt[accountID] = clock.now().addingTimeInterval(60)
        } catch UsageClientError.rateLimited(let retry) {
            let wait = retry.flatMap { max($0, 30) } ?? 60
            Log.usage.error("[REFRESH 429] id=\(accountID, privacy: .public) wait=\(wait)")
            nextEligibleAt[accountID] = clock.now().addingTimeInterval(wait)
            setError(accountID, .rateLimited)
        } catch {
            Log.usage.error("[REFRESH err] id=\(accountID, privacy: .public) err=\(String(describing: error), privacy: .public)")
            setError(accountID, .other(String(describing: error)))
            nextEligibleAt[accountID] = clock.now().addingTimeInterval(120)
        }
    }

    /// 토큰 소스 결정 — 활성/비활성 + Keychain 사용 여부에 따라.
    private func loadCredentials(accountID: AccountID, isActive: Bool, useKeychain: Bool) -> ClaudeAiOAuth? {
        if isActive, useKeychain,
           let liveData = liveActiveCredentials(),
           let live = try? JSON.decode(ClaudeCredentialsRoot.self, from: liveData) {
            Log.usage.info("[CREDS keychain] id=\(accountID, privacy: .public)")
            if let cur = try? snapshotStore.read(for: accountID) {
                let newSnap = ClaudeProfileSnapshot(oauthAccountJSON: cur.oauthAccountJSON, credentialsJSON: liveData)
                try? snapshotStore.write(newSnap, for: accountID)
            }
            return live.claudeAiOauth
        }
        if isActive && !useKeychain {
            if let fileData = try? ClaudeCredentialsFile().readRaw(),
               let live = try? JSON.decode(ClaudeCredentialsRoot.self, from: fileData) {
                Log.usage.info("[CREDS file] id=\(accountID, privacy: .public)")
                return live.claudeAiOauth
            }
            if let snap = try? snapshotStore.read(for: accountID),
               let cred = try? JSON.decode(ClaudeCredentialsRoot.self, from: snap.credentialsJSON) {
                Log.usage.info("[CREDS snapshot-fallback] id=\(accountID, privacy: .public)")
                return cred.claudeAiOauth
            }
            return nil
        }
        // 비활성 — snapshot 만 사용
        if let snap = try? snapshotStore.read(for: accountID),
           let cred = try? JSON.decode(ClaudeCredentialsRoot.self, from: snap.credentialsJSON) {
            return cred.claudeAiOauth
        }
        return nil
    }

    /// expiresAt 까지 5분 미만이면 true.
    private func shouldPreRefresh(creds: ClaudeAiOAuth) -> Bool {
        let nowMs = Int64(clock.now().timeIntervalSince1970 * 1000)
        let marginMs: Int64 = 5 * 60 * 1000
        return creds.expiresAt - nowMs < marginMs
    }

    /// refresh_token 으로 새 access_token 발급 + snapshot 갱신. 실패 시 nil.
    /// 활성 계정의 .credentials.json 동시 갱신은 Claude Code 와 race 가능성이 있어 의도적으로 안 함.
    private func tryRefresh(accountID: AccountID, current: ClaudeAiOAuth, isActive: Bool) async -> ClaudeAiOAuth? {
        if refreshInFlight.contains(accountID) {
            Log.usage.info("[REFRESH-TOKEN skip-inflight] id=\(accountID, privacy: .public)")
            return nil
        }
        refreshInFlight.insert(accountID)
        defer { refreshInFlight.remove(accountID) }

        do {
            let new = try await oauthRefresh.refresh(refreshToken: current.refreshToken, existing: current)
            try saveRefreshedCredentials(accountID: accountID, current: current, new: new)
            Log.usage.info("[REFRESH-TOKEN ok] id=\(accountID, privacy: .public)")
            return new
        } catch OAuthRefreshError.invalidGrant(let msg) {
            Log.usage.error("[REFRESH-TOKEN invalid_grant] id=\(accountID, privacy: .public) msg=\(msg, privacy: .public)")
            setError(accountID, .invalidGrant)
            nextEligibleAt[accountID] = clock.now().addingTimeInterval(300)  // 5분 backoff — 재로그인 필요
            return nil
        } catch OAuthRefreshError.rateLimited(let retry) {
            let wait = retry.flatMap { max($0, 60) } ?? 120
            nextEligibleAt[accountID] = clock.now().addingTimeInterval(wait)
            return nil
        } catch {
            Log.usage.error("[REFRESH-TOKEN fail] id=\(accountID, privacy: .public) err=\(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// 새 credentials 를 snapshot 에 원자적 write. 기존 oauthAccount JSON 은 유지.
    /// access/refresh 둘 다 동일하면 skip (서버가 rotation 안 한 + access 도 같은 케이스 — 드물지만 가능).
    private func saveRefreshedCredentials(accountID: AccountID, current: ClaudeAiOAuth, new: ClaudeAiOAuth) throws {
        if new.accessToken == current.accessToken && new.refreshToken == current.refreshToken {
            return
        }
        let root = ClaudeCredentialsRoot(claudeAiOauth: new)
        let credData = try JSON.encode(root)
        let configData: Data = (try? snapshotStore.read(for: accountID)?.oauthAccountJSON) ?? Data("{}".utf8)
        let snap = ClaudeProfileSnapshot(oauthAccountJSON: configData, credentialsJSON: credData)
        try snapshotStore.write(snap, for: accountID)
    }

    private func liveActiveCredentials() -> Data? {
        liveCredsReadRaw()
    }

    private func setError(_ id: AccountID, _ err: AccountError) {
        if lastError[id] != err { lastError[id] = err }
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
