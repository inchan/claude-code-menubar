import Foundation

enum ClaudeCredentialsError: Error, CustomStringConvertible {
    case fileNotFound(URL)
    case decodeFailed(String)

    var description: String {
        switch self {
        case .fileNotFound(let u): return "Claude credentials not found: \(u.path)"
        case .decodeFailed(let m): return "Claude credentials decode failed: \(m)"
        }
    }
}

/// `~/.claude/.credentials.json` 전체 R/W. 항상 0600.
final class ClaudeCredentialsFile {
    private let url: URL
    init(url: URL = Paths.claudeCredentials) { self.url = url }

    func readRaw() throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ClaudeCredentialsError.fileNotFound(url)
        }
        return try Data(contentsOf: url)
    }

    func read() throws -> ClaudeCredentialsRoot {
        let data = try readRaw()
        do {
            return try JSON.decode(ClaudeCredentialsRoot.self, from: data)
        } catch {
            throw ClaudeCredentialsError.decodeFailed(String(describing: error))
        }
    }

    func writeRaw(_ data: Data) throws {
        try AtomicFileWriter.write(data, to: url, permissions: 0o600)
    }
}
