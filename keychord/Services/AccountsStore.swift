import Foundation
import Combine

/// Loads and saves the persistent Account list at
/// ~/.config/keychord/accounts.json. This is the source of truth for
/// keychord-managed accounts. AccountProjector (Commit B') turns the
/// in-memory list into SSH config + gitconfig managed files.
///
/// @MainActor so mutations are serialized and SwiftUI views can
/// observe `@Published accounts` directly.
@MainActor
final class AccountsStore: ObservableObject {

    @Published private(set) var accounts: [Account] = []

    /// Absolute path of the accounts.json file this store owns.
    let storageURL: URL

    // MARK: - Init / defaults

    init(storageURL: URL = AccountsStore.defaultURL, autoLoad: Bool = true) {
        self.storageURL = storageURL
        if autoLoad {
            try? load()
        }
    }

    nonisolated static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/keychord/accounts.json")
    }

    // MARK: - Errors

    enum StoreError: Swift.Error, Equatable, CustomStringConvertible {
        case duplicateID(UUID)
        case notFound(UUID)
        case decodeFailed(String)
        case writeFailed(String)

        var description: String {
            switch self {
            case .duplicateID(let id):
                return "Account \(id.uuidString) already exists"
            case .notFound(let id):
                return "Account \(id.uuidString) not found"
            case .decodeFailed(let msg):
                return "Failed to decode accounts.json: \(msg)"
            case .writeFailed(let msg):
                return "Failed to write accounts.json: \(msg)"
            }
        }
    }

    // MARK: - Load / save

    func load() throws {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            accounts = []
            return
        }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(StorageFile.self, from: data)
            accounts = file.accounts
        } catch {
            throw StoreError.decodeFailed(error.localizedDescription)
        }
    }

    func save() throws {
        do {
            let parent = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            let file = StorageFile(version: 1, accounts: accounts)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(file)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - CRUD

    func add(_ account: Account) throws {
        guard accounts.contains(where: { $0.id == account.id }) == false else {
            throw StoreError.duplicateID(account.id)
        }
        accounts.append(account)
        try save()
    }

    func update(_ account: Account) throws {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw StoreError.notFound(account.id)
        }
        var next = account
        next.updatedAt = Date()
        accounts[idx] = next
        try save()
    }

    func delete(id: UUID) throws {
        guard accounts.contains(where: { $0.id == id }) else {
            throw StoreError.notFound(id)
        }
        accounts.removeAll { $0.id == id }
        try save()
    }

    func touchLastUsed(sshAlias: String) {
        guard let idx = accounts.firstIndex(where: { $0.sshAlias == sshAlias }) else { return }
        accounts[idx].lastUsedAt = Date()
        try? save()
    }

    func replaceAll(_ records: [Account]) throws {
        accounts = records
        try save()
    }

    // MARK: - Storage envelope

    private struct StorageFile: Codable {
        var version: Int
        var accounts: [Account]
    }
}
