import Foundation
import AppKit

/// `claude auth login` 을 사용자가 볼 수 있는 Terminal.app 에서 실행시킨다.
/// 메뉴바 앱 자체에는 PTY 가 없어 직접 spawn 시 OAuth 브라우저 흐름의 prompt 가 보이지 않는다.
struct ClaudeAuthCLI {
    enum Error: Swift.Error, CustomStringConvertible {
        case scriptFailed(String)
        var description: String {
            switch self {
            case .scriptFailed(let m): return "Terminal launch failed: \(m)"
            }
        }
    }

    /// `claude auth login` 을 새 Terminal 창에서 실행. 사용자는 종료 후 메뉴에서 "Import current" 를 누른다.
    func launchLogin() throws {
        try runInTerminal(command: "claude auth login")
    }

    func launchLogout() throws {
        try runInTerminal(command: "claude auth logout")
    }

    private func runInTerminal(command: String) throws {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(&error)
        if let err = error {
            throw Error.scriptFailed(err.description)
        }
    }
}
