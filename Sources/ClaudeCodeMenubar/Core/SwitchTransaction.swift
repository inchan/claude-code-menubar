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
/// 모든 외부 의존성(파일/Keychain/프로세스 검사) 은 protocol 또는 closure 로 주입 가능 —
/// 단위 테스트에서 mock 으로 전체 transactional 흐름을 검증하기 위해.
struct SwitchTransaction {
    let configFile: ClaudeConfigFileProtocol
    let credFile: ClaudeCredentialsFileProtocol
    let snapshotStore: ProfileSnapshotStoreProtocol
    let backups: BackupRotator
    let processGuard: ClaudeProcessGuardProtocol
    let accountRepo: AccountRepositoryProtocol
    let keychainWrite: @Sendable (Data) throws -> Void
    let keychainReadRaw: @Sendable () -> Data?
    let liveCredsReadRaw: @Sendable () throws -> Data
    let lockFilePath: String

    init(configFile: ClaudeConfigFileProtocol = ClaudeConfigFile(),
         credFile: ClaudeCredentialsFileProtocol = ClaudeCredentialsFile(),
         snapshotStore: ProfileSnapshotStoreProtocol,
         backups: BackupRotator = BackupRotator(),
         processGuard: ClaudeProcessGuardProtocol = ClaudeProcessGuard(),
         accountRepo: AccountRepositoryProtocol,
         keychainWrite: @Sendable @escaping (Data) throws -> Void = ClaudeKeychainCredentials.writeRaw,
         keychainReadRaw: @Sendable @escaping () -> Data? = ClaudeKeychainCredentials.readRaw,
         liveCredsReadRaw: @Sendable @escaping () throws -> Data = ClaudeLiveCredentials.readRaw,
         lockFilePath: String = Paths.lockFile.path) {
        self.configFile = configFile
        self.credFile = credFile
        self.snapshotStore = snapshotStore
        self.backups = backups
        self.processGuard = processGuard
        self.accountRepo = accountRepo
        self.keychainWrite = keychainWrite
        self.keychainReadRaw = keychainReadRaw
        self.liveCredsReadRaw = liveCredsReadRaw
        self.lockFilePath = lockFilePath
    }

    /// 대상 계정으로 활성 자료 교체.
    func execute(targetID: AccountID, allowWhileClaudeRunning: Bool = false) throws {
        try ensureAppRoot()
        try FileLock.withLock(at: lockFilePath) {
            try executeLocked(targetID: targetID, allowWhileClaudeRunning: allowWhileClaudeRunning)
        }
    }

    private func executeLocked(targetID: AccountID, allowWhileClaudeRunning: Bool) throws {
        // 2) Claude 실행 확인
        if !allowWhileClaudeRunning, processGuard.isClaudeRunning() {
            throw SwitchError.claudeRunning
        }

        // 3) 대상 스냅샷 확보 + 디코드 (선검증으로 빠른 실패, 결과는 step 7 검증에서 재사용)
        guard let target = try snapshotStore.read(for: targetID) else {
            throw SwitchError.targetNotFound(targetID)
        }
        let targetCreds = try JSON.decode(ClaudeCredentialsRoot.self, from: target.credentialsJSON)
        let targetOAuth = try JSON.decode(ClaudeOAuthAccount.self, from: target.oauthAccountJSON)

        // 4) 활성 자료 수집 + timestamp 백업.
        //    credentials 는 단일 정의원(ClaudeLiveCredentials) 통과 — Keychain 우선.
        let activeOAuth: Data
        let activeCreds: Data
        do {
            activeOAuth = try configFile.readOAuthAccountJSON()
            activeCreds = try liveCredsReadRaw()
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

        // 6) 교체 (활성 자료 → 대상). 파일 + Keychain 동시 — 한 쪽만 갱신되면
        //    ClaudeLiveCredentials (Keychain 우선) 가 stale 토큰을 읽어 폴링이
        //    이전 계정의 사용량을 반환하는 회귀가 발생함.
        do {
            try configFile.patchOAuthAccount(target.oauthAccountJSON)
            try credFile.writeRaw(target.credentialsJSON)
            try keychainWrite(target.credentialsJSON)
        } catch {
            // 교체 중 실패: rollback 시도
            rollback(oauth: activeOAuth, creds: activeCreds)
            throw SwitchError.underlying(error)
        }

        // 7) 검증 — 파일 + Keychain 둘 다 대상 토큰과 일치하는지 확인.
        do {
            let nowOAuth = try configFile.readOAuthAccount()
            let nowCreds = try credFile.read()
            guard nowOAuth.accountUuid == targetOAuth.accountUuid else {
                throw SwitchError.verificationFailed("accountUuid mismatch after write")
            }
            guard nowCreds.claudeAiOauth.expiresAt == targetCreds.claudeAiOauth.expiresAt else {
                throw SwitchError.verificationFailed("credentials.expiresAt mismatch after write")
            }
            guard let kcData = keychainReadRaw(),
                  let kc = try? JSON.decode(ClaudeCredentialsRoot.self, from: kcData) else {
                throw SwitchError.verificationFailed("keychain read-back missing")
            }
            guard kc.claudeAiOauth.expiresAt == targetCreds.claudeAiOauth.expiresAt else {
                throw SwitchError.verificationFailed("keychain.expiresAt mismatch after write")
            }
        } catch {
            rollback(oauth: activeOAuth, creds: activeCreds)
            if let se = error as? SwitchError { throw se }
            // 비-SwitchError 는 step 7 의 readback I/O 실패 (configFile.readOAuthAccount,
            // credFile.read, JSON.decode). 값 불일치(SwitchError) 와 prefix 로 구분.
            throw SwitchError.verificationFailed("readback-io: \(String(describing: error))")
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
        // 어느 단계에서 실패했는지 진단할 수 있도록 단계별로 try? + 개별 로깅.
        // 실패해도 다음 단계를 시도 — 한 곳이라도 복구되면 부분이라도 안전.
        var failures: [String] = []
        do { try configFile.patchOAuthAccount(oauth) }
        catch { failures.append("config: \(String(describing: error))") }
        do { try credFile.writeRaw(creds) }
        catch { failures.append("file: \(String(describing: error))") }
        do { try keychainWrite(creds) }
        catch { failures.append("keychain: \(String(describing: error))") }
        if failures.isEmpty {
            Log.switching.warning("rollback applied")
        } else {
            Log.switching.error("rollback PARTIAL/FAILED: \(failures.joined(separator: " | "))")
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
