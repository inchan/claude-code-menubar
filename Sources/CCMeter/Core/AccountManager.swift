import Foundation
import Combine

/// 도메인 진입점. UI 와 Storage/ClaudeIntegration 사이의 facade.
@MainActor
final class AccountManager: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var activeAccountID: AccountID?
    @Published private(set) var lastError: String?

    private let repo: AccountRepositoryProtocol
    private let snapshots: ProfileSnapshotStoreProtocol
    private let configFile: ClaudeConfigFileProtocol
    private let processGuard: ClaudeProcessGuardProtocol
    private let backups: BackupRotator
    private let switcher: SwitchTransaction
    private let authCLI = ClaudeAuthCLI()
    private let liveCredsReadRaw: @Sendable () throws -> Data

    init(repo: AccountRepositoryProtocol = AccountRepository(),
         snapshots: ProfileSnapshotStoreProtocol = ProfileSnapshotStore(),
         configFile: ClaudeConfigFileProtocol = ClaudeConfigFile(),
         processGuard: ClaudeProcessGuardProtocol = ClaudeProcessGuard(),
         backups: BackupRotator = BackupRotator(),
         liveCredsReadRaw: @Sendable @escaping () throws -> Data = ClaudeLiveCredentials.readRaw,
         switcher: SwitchTransaction? = nil) {
        self.repo = repo
        self.snapshots = snapshots
        self.configFile = configFile
        self.processGuard = processGuard
        self.backups = backups
        self.liveCredsReadRaw = liveCredsReadRaw
        self.switcher = switcher ?? SwitchTransaction(
            configFile: configFile,
            snapshotStore: snapshots,
            backups: backups,
            processGuard: processGuard,
            accountRepo: repo,
            liveCredsReadRaw: liveCredsReadRaw
        )
    }

    func reload() {
        do {
            let next = try repo.load()
                .sorted { ($0.lastUsedAt ?? $0.addedAt) > ($1.lastUsedAt ?? $1.addedAt) }
            if next != accounts { accounts = next }
            let nextActive = try detectActiveAccountID(in: next)
            if nextActive != activeAccountID { activeAccountID = nextActive }
            if lastError != nil { lastError = nil }
        } catch {
            let msg = String(describing: error)
            if lastError != msg { lastError = msg }
            Log.app.error("reload failed: \(msg)")
        }
    }

    /// 현재 Claude Code 활성 계정을 import. 같은 accountUuid 가 이미 있으면 갱신.
    /// credentials 는 Keychain 우선 → 파일 fallback (macOS 가 새 로그인/refresh 시
    /// Keychain 만 갱신하고 파일은 부재/stale 인 동작 회피).
    @discardableResult
    func importCurrent(label: String? = nil, colorHex: String? = nil) throws -> Account {
        let oauthData = try configFile.readOAuthAccountJSON()
        let credsData = try liveCredsReadRaw()
        let oauth = try JSON.decode(ClaudeOAuthAccount.self, from: oauthData)

        var accounts = try repo.load()
        if let idx = accounts.firstIndex(where: { $0.accountUuid == oauth.accountUuid }) {
            // 갱신
            var existing = accounts[idx]
            existing.lastUsedAt = Date()
            existing.label = label ?? existing.label
            if let c = colorHex { existing.colorHex = c }
            accounts[idx] = existing
            try repo.save(accounts)
            try snapshots.write(.init(oauthAccountJSON: oauthData, credentialsJSON: credsData),
                                for: existing.id)
            reload()
            notifyAccountChanged(id: existing.id, kind: .imported)
            return existing
        }

        let id = UUID().uuidString
        let acc = Account(
            id: id,
            label: label ?? defaultLabel(for: oauth.emailAddress),
            emailAddress: oauth.emailAddress,
            accountUuid: oauth.accountUuid,
            organizationUuid: oauth.organizationUuid,
            colorHex: colorHex ?? Account.deterministicColor(for: oauth.emailAddress.lowercased()),
            addedAt: Date(),
            lastUsedAt: Date(),
            subscriptionType: nil
        )
        accounts.append(acc)
        try repo.save(accounts)
        try snapshots.write(.init(oauthAccountJSON: oauthData, credentialsJSON: credsData), for: id)
        reload()
        notifyAccountChanged(id: id, kind: .imported)
        return acc
    }

    func remove(_ id: AccountID) throws {
        var accounts = try repo.load()
        accounts.removeAll { $0.id == id }
        try repo.save(accounts)
        try snapshots.remove(for: id)
        reload()
    }

    func rename(_ id: AccountID, to label: String) throws {
        var accounts = try repo.load()
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].label = label
        try repo.save(accounts)
        reload()
    }

    func switchTo(_ id: AccountID, allowWhileClaudeRunning: Bool = false) throws {
        try switcher.execute(targetID: id, allowWhileClaudeRunning: allowWhileClaudeRunning)
        reload()
        notifyAccountChanged(id: id, kind: .switched)
    }

    private func notifyAccountChanged(id: AccountID, kind: CCAccountChangedKind) {
        NotificationCenter.default.post(
            name: .ccAccountChanged,
            object: nil,
            userInfo: ["accountID": id, "kind": kind.rawValue]
        )
    }

    func openLogin() throws {
        try authCLI.launchLogin()
    }

    // MARK: - helpers

    private func defaultLabel(for email: String) -> String {
        if let local = email.split(separator: "@").first {
            return String(local)
        }
        return email
    }

    private func detectActiveAccountID(in list: [Account]) throws -> AccountID? {
        let oauth = try configFile.readOAuthAccount()
        return list.first { $0.accountUuid == oauth.accountUuid }?.id
    }
}

extension Account {
    /// 이메일(또는 임의 식별자) 기반 결정적 컬러. 같은 입력 → 항상 같은 색.
    static func deterministicColor(for seed: String) -> String {
        let palette = [
            "#3478F6", "#34C759", "#FF9500", "#FF3B30",
            "#AF52DE", "#5AC8FA", "#FF2D55", "#A2845E",
            "#30B0C7", "#BF5AF2"
        ]
        return palette[Int(FNV.hash32(seed) % UInt32(palette.count))]
    }
}
