import Foundation

/// Remembers the `org/` a clone command last used, per account, so the next
/// clone field starts where the last one left off instead of empty.
///
/// Per account rather than global: `work` clones from one org, `personal` from
/// another, and mixing them up produces a wrong URL that looks right.
@MainActor
final class ClonePrefixMemory {
    static let shared = ClonePrefixMemory()

    static let defaultsKeyPrefix = "keychord.clonePrefix."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func prefix(for accountID: UUID) -> String? {
        let stored = defaults.string(forKey: Self.key(for: accountID))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return nil }
        return stored
    }

    /// Store the owner part of `input` (`acme/api` → `acme/`). Input without a
    /// usable owner leaves the memory untouched — a bad paste should not erase
    /// a good prefix.
    func remember(input: String, for accountID: UUID) {
        guard let prefix = Self.ownerPrefix(from: input) else { return }
        defaults.set(prefix, forKey: Self.key(for: accountID))
    }

    func forget(accountID: UUID) {
        defaults.removeObject(forKey: Self.key(for: accountID))
    }

    static func key(for accountID: UUID) -> String {
        defaultsKeyPrefix + accountID.uuidString
    }

    /// `acme/api` → `acme/`, `acme/group/repo` → `acme/`. Nil for a bare repo
    /// name, a URL, or anything with no owner component.
    static func ownerPrefix(from input: String) -> String? {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Accept a pasted remote too: peel it down to owner/repo first.
        if let ownerRepo = CloneURLRewriter.ownerRepoPath(fromRemoteURL: trimmed) {
            trimmed = ownerRepo
        }
        guard !trimmed.contains("://"), !trimmed.contains("@") else { return nil }
        while trimmed.hasPrefix("/") { trimmed = String(trimmed.dropFirst()) }

        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let owner = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return nil }
        return owner + "/"
    }
}
