import Foundation

/// Claude Code CLI 실행 중인지 검사. 실행 중이면 스위치 차단.
struct ClaudeProcessGuard {
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

    private func matchesClaudeProcess(_ cmd: String) -> Bool {
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
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        return s.split(separator: "\n").map(String.init)
    }
}
