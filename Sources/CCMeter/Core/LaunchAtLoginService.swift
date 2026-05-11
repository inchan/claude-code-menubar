import Foundation
import ServiceManagement

/// macOS 13+ SMAppService.mainApp 으로 로그인 시 자동 실행 토글.
@MainActor
enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) throws {
        let svc = SMAppService.mainApp
        if on {
            if svc.status != .enabled { try svc.register() }
        } else {
            if svc.status == .enabled { try svc.unregister() }
        }
    }
}
