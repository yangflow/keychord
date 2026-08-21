import Foundation
import Observation

/// Loads and saves the persistent Account list at
/// ~/.config/keychord/accounts.json. This is the source of truth for
/// keychord-managed accounts. AccountProjector turns the in-memory
/// list into SSH config + gitconfig managed files.
@MainActor
@Observable
final class AccountsStore {

    private(set) var accounts: [Account] = []

    /// Absolute path of the accounts.json file this store owns.
    let storageURL: URL

    /// Snapshots accounts.json before adding a new account so the user can
    /// roll back from the Restore view. Updates / deletes do not create backups.
    let backups: BackupService

    // MARK: - Init / defaults

    init(
        storageURL: URL = AccountsStore.defaultURL,
        backups: BackupService = BackupService(),
        autoLoad: Bool = true
    ) {
        self.storageURL = storageURL
        self.backups = backups
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

    /// Writes `accounts.json`. When `createBackup` is true and a file already
    /// exists, snapshots it first (used only by ``add``).
    func save(createBackup: Bool = false) throws {
        do {
            let parent = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            if createBackup, FileManager.default.fileExists(atPath: storageURL.path) {
                _ = try backups.backup(originalPath: storageURL.path)
            }
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
        try save(createBackup: true)
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

    /// Marks an account as just used so the popover can sort by recency.
    /// Silently ignores an unknown alias — callers touch on every match, and a
    /// blank alias belongs to an account that has not been finished yet.
    func touchLastUsed(sshAlias: String, at date: Date = Date()) {
        let alias = sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty,
              let idx = accounts.firstIndex(where: { $0.sshAlias == alias }) else { return }
        accounts[idx].lastUsedAt = date
        try? save()
    }

    /// Same, keyed by identity — usable before an account has an SSH alias.
    func touchLastUsed(id: UUID, at date: Date = Date()) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].lastUsedAt = date
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
