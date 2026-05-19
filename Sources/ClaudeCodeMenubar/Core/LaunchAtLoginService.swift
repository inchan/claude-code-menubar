import Foundation
import ServiceManagement

/// macOS 13+ SMAppService.mainApp 으로 로그인 시 자동 실행 토글.
@MainActor
enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 실제 시스템 등록 상태. UI 가 디스크 저장값 대신 이 값을 표시해야 stale 토글 회피.
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// 사용자가 System Settings → Login Items 에서 disable 한 상태 (재등록만으론 못 푼다).
    static var requiresUserApproval: Bool { status == .requiresApproval }

    /// register/unregister 는 idempotent 가 아님 — 같은 path/identity 라도
    /// re-install 후엔 BTM 등록을 다시 박아야 stale 등록을 새 bundle 로 갱신.
    /// 따라서 on 인 경우 status 와 무관하게 항상 register() 호출.
    static func setEnabled(_ on: Bool) throws {
        let svc = SMAppService.mainApp
        if on {
            // requiresApproval 이면 register() 가 throw 함 — UI 에서 시스템 설정 안내 필요.
            try svc.register()
        } else {
            if svc.status == .enabled { try svc.unregister() }
        }
    }

    /// 앱 시작 시 — 디스크 의도(`desiredOn`) 와 BTM 실제 상태를 화해.
    /// 의도 on + 실제 미등록 → register 시도 (재설치 후 path/identity 갱신 케이스).
    /// 실패해도 throw 하지 않음 — 시작 흐름을 막지 않고 로깅만.
    @discardableResult
    static func reconcileAtLaunch(desiredOn: Bool) -> SMAppService.Status {
        let svc = SMAppService.mainApp
        if desiredOn && svc.status != .enabled {
            do {
                try svc.register()
                Log.app.info("[LAUNCH-AT-LOGIN] re-registered (was status=\(svc.status.rawValue))")
            } catch {
                Log.app.error("[LAUNCH-AT-LOGIN] register failed status=\(svc.status.rawValue) err=\(String(describing: error), privacy: .public)")
            }
        }
        return svc.status
    }
}
