import Foundation

/// Rename or move a project folder and the account keeps pointing at the old
/// `gitdir:` path, so the next drop matches nothing and there is no repair in
/// sight.
///
/// The heuristic is deliberately narrow: only a **missing** path that sits in
/// the **same parent directory** as the dropped folder is offered as the stale
/// one — a rename in place, which is the case we can retarget without guessing.
/// A path that still exists is never touched, and no other account is rewritten.
enum StaleGitdirRepair {

    struct Candidate: Equatable, Sendable {
        let account: Account
        /// Storage form of the account's path that no longer exists on disk.
        let stalePath: String
        /// Storage form of the folder the user just dropped.
        let replacementPath: String

        var displayLabel: String {
            account.label.isEmpty ? String(localized: "(unnamed)") : account.label
        }
    }

    /// First missing sibling path across the account list, in account order and
    /// then path order, so the suggestion is deterministic.
    ///
    /// `directoryExists` is injectable so tests do not need real folders.
    static func candidate(
        forDroppedFolder folderPath: String,
        accounts: [Account],
        directoryExists: (String) -> Bool = { path in
            var isDirectory: ObjCBool = false
            let found = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return found && isDirectory.boolValue
        }
    ) -> Candidate? {
        let replacement = CurrentRepoResolver.normalizeGitdir(folderPath)
        guard !replacement.isEmpty else { return nil }
        let droppedParent = parentDirectory(ofGitdirPath: replacement)
        guard !droppedParent.isEmpty else { return nil }

        for account in accounts {
            for raw in account.scope.directories {
                let stored = CurrentRepoResolver.normalizeGitdir(raw)
                guard !stored.isEmpty, stored != replacement else { continue }
                guard parentDirectory(ofGitdirPath: stored) == droppedParent else { continue }
                guard !directoryExists(ConfigStore.expand(stored)) else { continue }
                return Candidate(
                    account: account,
                    stalePath: stored,
                    replacementPath: replacement
                )
            }
        }
        return nil
    }

    /// Replace exactly the stale path, in place, keeping every other gitdir path
    /// and their order. Returns the account unchanged when the stale path is
    /// gone already (a second tap, for instance).
    static func repair(_ candidate: Candidate) -> Account {
        var account = candidate.account
        let paths = account.scope.directories
        guard let index = paths.firstIndex(where: {
            CurrentRepoResolver.normalizeGitdir($0) == candidate.stalePath
        }) else {
            return account
        }
        var updated = paths
        if paths.contains(where: {
            CurrentRepoResolver.normalizeGitdir($0) == candidate.replacementPath
        }) {
            // The new path is already scoped; drop the dead entry instead of
            // creating a duplicate.
            updated.remove(at: index)
        } else {
            updated[index] = candidate.replacementPath
        }
        account.scope = .gitdir(paths: updated)
        return account
    }

    /// Parent of a `gitdir:` prefix: `~/src/old-app/` → `~/src/`.
    static func parentDirectory(ofGitdirPath path: String) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        guard !trimmed.isEmpty, trimmed != "~" else { return "" }
        let parent = (trimmed as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != "/" else { return "" }
        return CurrentRepoResolver.ensureTrailingSlash(parent)
    }
}
