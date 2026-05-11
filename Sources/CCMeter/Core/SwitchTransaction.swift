import Foundation

enum SwitchError: Error, CustomStringConvertible {
    case claudeRunning
    case targetNotFound(AccountID)
    case noActiveProfile
    case verificationFailed(String)
    case underlying(Swift.Error)

    var description: String {
        switch self {
        case .claudeRunning:
            return "Claude Code 가 실행 중입니다. 종료한 뒤 다시 시도하세요."
        case .targetNotFound(let id):
            return "계정 스냅샷을 찾을 수 없습니다 (id=\(id))."
        case .noActiveProfile:
            return "현재 활성 Claude 프로필을 읽지 못했습니다."
        case .verificationFailed(let m):
            return "교체 후 검증 실패: \(m)"
        case .underlying(let e):
            return "스위치 실패: \(String(describing: e))"
        }
    }
}

/// 백업 → 교체 → 검증 → (실패 시) 롤백. flock 으로 단일 진입.
struct SwitchTransaction {
    let configFile: ClaudeConfigFile
    let credFile: ClaudeCredentialsFile
    let snapshotStore: ProfileSnapshotStoreProtocol
    let backups: BackupRotator
    let processGuard: ClaudeProcessGuard
    let accountRepo: AccountRepositoryProtocol

    init(configFile: ClaudeConfigFile = ClaudeConfigFile(),
         snapshotStore: ProfileSnapshotStoreProtocol,
         backups: BackupRotator = BackupRotator(),
         processGuard: ClaudeProcessGuard = ClaudeProcessGuard(),
         accountRepo: AccountRepositoryProtocol) {
        self.configFile = configFile
        self.credFile = ClaudeCredentialsFile()  // 쓰기 전용 (read 는 ClaudeLiveCredentials)
        self.snapshotStore = snapshotStore
        self.backups = backups
        self.processGuard = processGuard
        self.accountRepo = accountRepo
    }

    /// 대상 계정으로 활성 자료 교체.
    func execute(targetID: AccountID, allowWhileClaudeRunning: Bool = false) throws {
        try ensureAppRoot()
        try FileLock.withLock(at: Paths.lockFile.path) {
            try executeLocked(targetID: targetID, allowWhileClaudeRunning: allowWhileClaudeRunning)
        }
    }

    private func executeLocked(targetID: AccountID, allowWhileClaudeRunning: Bool) throws {
        // 2) Claude 실행 확인
        if !allowWhileClaudeRunning, processGuard.isClaudeRunning() {
            throw SwitchError.claudeRunning
        }

        // 3) 대상 스냅샷 확보 (선검증으로 빠른 실패)
        guard let target = try snapshotStore.read(for: targetID) else {
            throw SwitchError.targetNotFound(targetID)
        }
        // 대상 credentials 디코드 검증 (corrupt 데이터 차단)
        _ = try JSON.decode(ClaudeCredentialsRoot.self, from: target.credentialsJSON)

        // 4) 활성 자료 수집 + timestamp 백업.
        //    credentials 는 단일 정의원(ClaudeLiveCredentials) 통과 — Keychain 우선.
        let activeOAuth: Data
        let activeCreds: Data
        do {
            activeOAuth = try configFile.readOAuthAccountJSON()
            activeCreds = try ClaudeLiveCredentials.readRaw()
        } catch {
            throw SwitchError.noActiveProfile
        }
        try backups.write(label: .claudeConfigOAuthAccount, data: activeOAuth)
        try backups.write(label: .claudeCredentials, data: activeCreds)

        // 5) 활성 계정의 스냅샷 갱신 (현재 계정이 등록된 계정과 일치하면 백업)
        if let activeID = try matchActiveAccountID(activeOAuthJSON: activeOAuth) {
            let snap = ClaudeProfileSnapshot(oauthAccountJSON: activeOAuth,
                                             credentialsJSON: activeCreds)
            try? snapshotStore.write(snap, for: activeID)
        }

        // 6) 교체 (활성 자료 → 대상)
        do {
            try configFile.patchOAuthAccount(target.oauthAccountJSON)
            try credFile.writeRaw(target.credentialsJSON)
        } catch {
            // 교체 중 실패: rollback 시도
            rollback(oauth: activeOAuth, creds: activeCreds)
            throw SwitchError.underlying(error)
        }

        // 7) 검증
        do {
            let nowOAuth = try configFile.readOAuthAccount()
            let nowCreds = try credFile.read()
            let expected = try JSON.decode(ClaudeOAuthAccount.self, from: target.oauthAccountJSON)
            let expectedCreds = try JSON.decode(ClaudeCredentialsRoot.self,
                                                from: target.credentialsJSON)
            guard nowOAuth.accountUuid == expected.accountUuid else {
                throw SwitchError.verificationFailed("accountUuid mismatch after write")
            }
            guard nowCreds.claudeAiOauth.expiresAt == expectedCreds.claudeAiOauth.expiresAt else {
                throw SwitchError.verificationFailed("credentials.expiresAt mismatch after write")
            }
        } catch let err as SwitchError {
            rollback(oauth: activeOAuth, creds: activeCreds)
            throw err
        } catch {
            rollback(oauth: activeOAuth, creds: activeCreds)
            throw SwitchError.verificationFailed(String(describing: error))
        }

        // 8) lastUsedAt 업데이트
        do {
            var accounts = try accountRepo.load()
            if let idx = accounts.firstIndex(where: { $0.id == targetID }) {
                accounts[idx].lastUsedAt = Date()
                try accountRepo.save(accounts)
            }
        } catch {
            Log.switching.error("lastUsedAt update failed: \(String(describing: error))")
        }
    }

    private func rollback(oauth: Data, creds: Data) {
        do {
            try configFile.patchOAuthAccount(oauth)
            try credFile.writeRaw(creds)
            Log.switching.warning("rollback applied")
        } catch {
            Log.switching.error("rollback FAILED: \(String(describing: error))")
        }
    }

    private func matchActiveAccountID(activeOAuthJSON: Data) throws -> AccountID? {
        let active = try JSON.decode(ClaudeOAuthAccount.self, from: activeOAuthJSON)
        let accounts = try accountRepo.load()
        return accounts.first { $0.accountUuid == active.accountUuid }?.id
    }

    private func ensureAppRoot() throws {
        try FileManager.default.createDirectory(at: Paths.appRoot,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
    }
}
