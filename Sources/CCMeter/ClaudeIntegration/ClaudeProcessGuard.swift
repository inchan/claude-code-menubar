import Foundation

protocol ClaudeProcessGuardProtocol: Sendable {
    func isClaudeRunning() -> Bool
}

/// Claude Code CLI 실행 중인지 검사. 실행 중이면 스위치 차단.
struct ClaudeProcessGuard: ClaudeProcessGuardProtocol {
    /// `pgrep -fx '^node .*claude'` 류로는 false-positive 가 많아 ps + 정밀 매칭 사용.
    func isClaudeRunning() -> Bool {
        guard let lines = runPS() else { return false }
        for line in lines {
            // 형태: "PID command-line"
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let spaceIdx = trimmed.firstIndex(of: " ") else { continue }
            let cmd = String(trimmed[trimmed.index(after: spaceIdx)...])
            if matchesClaudeProcess(cmd) {
                return true
            }
        }
        return false
    }

    /// 명령행 한 줄이 Claude CLI 시그니처에 매칭되는지. 단위 테스트 용도로 internal.
    func matchesClaudeProcess(_ cmd: String) -> Bool {
        // node /path/to/claude/cli.js ...  또는  /usr/local/bin/claude ...
        let lowered = cmd.lowercased()
        // 우리 자신(CCMeter) 또는 기타 'claude' 문자열 포함 프로세스 제외
        if lowered.contains("ccmeter") { return false }
        if lowered.contains("claude code") { return false } // Claude.app
        // claude CLI 시그니처: 끝이 /claude 또는 .../cli.js (node 실행)
        if cmd.hasSuffix("/claude") { return true }
        if lowered.contains("/claude/") && lowered.contains("cli.js") { return true }
        if cmd.range(of: #"(^|/)claude($|\s)"#, options: .regularExpression) != nil {
            // 두 번째 안전망
            return true
        }
        return false
    }

    private func runPS() -> [String]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Ao", "pid,command"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
        } catch {
            return nil
        }
        // 파이프 버퍼 고갈 데드락 방지 — read 후 waitUntilExit 순서 유지.
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        return s.split(separator: "\n").map(String.init)
    }
}
