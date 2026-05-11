import Foundation

protocol AccountRepositoryProtocol: AnyObject {
    func load() throws -> [Account]
    func save(_ accounts: [Account]) throws
}

final class AccountRepository: AccountRepositoryProtocol {
    func load() throws -> [Account] {
        let url = Paths.accountsFile
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [] }
        return try JSON.decode([Account].self, from: data)
    }

    func save(_ accounts: [Account]) throws {
        let data = try JSON.encode(accounts)
        try AtomicFileWriter.write(data, to: Paths.accountsFile, permissions: 0o600)
    }
}
