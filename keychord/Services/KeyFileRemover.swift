import Foundation

/// Deleting an account removes a keychord record; the private key and the
/// directories it was scoped to live on. This service describes those leftovers
/// for the delete confirmation and, only when the user opts in, removes the one
/// key file that clearly belongs to the account.
enum KeyFileRemover {

    /// What survives a delete, and whether the key is safe to remove with it.
    struct Leftovers: Equatable, Sendable {
        /// Storage form (`~/…`) of the account's private key; empty when unset.
        let privateKeyPath: String
        /// Storage form of every `gitdir:` path the account owned.
        let gitdirPaths: [String]
        /// `nil` when the key can be deleted; otherwise why it cannot.
        let keyRemovalBlocker: Blocker?

        var canRemoveKey: Bool { !privateKeyPath.isEmpty && keyRemovalBlocker == nil }
    }

    enum Blocker: Equatable, Sendable {
        case noKeyPath
        case missing(String)
        case symlink(String)
        case notARegularFile(String)
        /// Another account points at the same key file.
        case sharedWith([String])

        var localizedMessage: String {
            switch self {
            case .noKeyPath:
                return String.loc("This account has no private key yet.")
            case .missing(let path):
                return String.loc("No private key at \(path.abbreviatedHomePath())")
            case .symlink(let path):
                return String.loc("\(path.abbreviatedHomePath()) is a symlink, so keychord will not delete it.")
            case .notARegularFile(let path):
                return String.loc("\(path.abbreviatedHomePath()) is not a regular file.")
            case .sharedWith(let labels):
                let joined = labels.joined(separator: ", ")
                return String.loc("\(joined) also uses this key, so it is kept.")
            }
        }
    }

    enum RemoveError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case blocked(Blocker)
        case removeFailed(String)

        var description: String {
            switch self {
            case .blocked(let blocker):
                return blocker.localizedMessage
            case .removeFailed(let message):
                return String.loc("Could not delete the private key: \(message)")
            }
        }
    }

    // MARK: - Describe

    static func leftovers(for account: Account, in accounts: [Account]) -> Leftovers {
        let stored = account.keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = account.scope.directories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Leftovers(
            privateKeyPath: stored,
            gitdirPaths: paths,
            keyRemovalBlocker: keyRemovalBlocker(for: account, in: accounts)
        )
    }

    /// “Clearly the account key” means: a path is set, a regular file is there,
    /// it is not a symlink, and no other account depends on it.
    static func keyRemovalBlocker(for account: Account, in accounts: [Account]) -> Blocker? {
        let stored = account.keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stored.isEmpty else { return .noKeyPath }

        let sharing = accounts
            .filter { $0.id != account.id }
            .filter {
                ConfigStore.expand($0.keyPath.trimmingCharacters(in: .whitespacesAndNewlines))
                    == ConfigStore.expand(stored)
            }
            .map { $0.label.isEmpty ? String.loc("(unnamed)") : $0.label }
        if !sharing.isEmpty { return .sharedWith(sharing) }

        let expanded = ConfigStore.expand(stored)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: expanded)) != nil {
            return .symlink(stored)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
            return .missing(stored)
        }
        if isDirectory.boolValue { return .notARegularFile(stored) }
        return nil
    }

    // MARK: - Remove

    /// Delete the account's private key file. The public half is left alone —
    /// it holds no secret and users often keep it around.
    static func removePrivateKey(of account: Account, in accounts: [Account]) throws {
        if let blocker = keyRemovalBlocker(for: account, in: accounts) {
            throw RemoveError.blocked(blocker)
        }
        let expanded = ConfigStore.expand(
            account.keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try FileManager.default.removeItem(atPath: expanded)
        } catch {
            throw RemoveError.removeFailed(error.localizedDescription)
        }
    }
}
