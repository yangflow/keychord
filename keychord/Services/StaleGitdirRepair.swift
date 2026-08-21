import Foundation

/// Rename or move a project folder and the account keeps pointing at the old
/// `gitdir:` path, so the next drop matches nothing and there is no repair in
/// sight.
///
/// The heuristic stays narrow on purpose. A path only qualifies when it is
/// **missing on disk** *and* looks like the dropped folder's previous name:
///
///   * same parent directory — `~/src/old-app/` vs a dropped `~/src/renamed-app/`
///     (a rename in place, the strongest signal);
///   * same last path component — `~/src/api/` vs a dropped `~/work/api/`
///     (the project moved).
///
/// The account label breaks ties between equally plausible candidates. A path
/// that still exists is never touched, only that one path is ever rewritten,
/// and no other account is looked at again.
enum StaleGitdirRepair {

    struct Candidate: Equatable, Sendable {
        let account: Account
        /// Storage form of the account's path that no longer exists on disk.
        let stalePath: String
        /// Storage form of the folder the user just dropped.
        let replacementPath: String
        /// Why this path looks like the folder's previous name.
        let reason: Reason

        var displayLabel: String {
            account.label.isEmpty ? String.loc("(unnamed)") : account.label
        }
    }

    /// Ordered by how much it tells us: a sibling rename beats a move.
    enum Reason: Int, Equatable, Sendable, Comparable {
        case sameParent = 0
        case sameLastComponent = 1

        static func < (lhs: Reason, rhs: Reason) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Best missing-path candidate across the account list, or `nil` when no
    /// path looks related. Deterministic: ranked by reason, then a label that
    /// matches the folder name, then account and path order.
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
        let droppedLeaf = lastPathComponent(ofGitdirPath: replacement)
        guard !droppedParent.isEmpty, !droppedLeaf.isEmpty else { return nil }

        var best: (candidate: Candidate, rank: (Reason, Bool, Int, String))?

        for (index, account) in accounts.enumerated() {
            let labelMatchesFolder = account.label
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(droppedLeaf) == .orderedSame

            for raw in account.scope.directories {
                let stored = CurrentRepoResolver.normalizeGitdir(raw)
                guard !stored.isEmpty, stored != replacement else { continue }

                let reason: Reason
                if parentDirectory(ofGitdirPath: stored) == droppedParent {
                    reason = .sameParent
                } else if lastPathComponent(ofGitdirPath: stored)
                    .caseInsensitiveCompare(droppedLeaf) == .orderedSame {
                    reason = .sameLastComponent
                } else {
                    continue
                }
                guard !directoryExists(ConfigStore.expand(stored)) else { continue }

                // Sort key: better reason first, then a label naming this
                // folder, then declaration order.
                let rank = (reason, !labelMatchesFolder, index, stored)
                let candidate = Candidate(
                    account: account,
                    stalePath: stored,
                    replacementPath: replacement,
                    reason: reason
                )
                if best == nil || isRank(rank, betterThan: best!.rank) {
                    best = (candidate, rank)
                }
            }
        }
        return best?.candidate
    }

    private static func isRank(
        _ lhs: (Reason, Bool, Int, String),
        betterThan rhs: (Reason, Bool, Int, String)
    ) -> Bool {
        if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
        if lhs.1 != rhs.1 { return !lhs.1 }
        if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
        return lhs.3 < rhs.3
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

    /// Leaf of a `gitdir:` prefix: `~/src/old-app/` → `old-app`.
    static func lastPathComponent(ofGitdirPath path: String) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        guard !trimmed.isEmpty, trimmed != "~" else { return "" }
        return (trimmed as NSString).lastPathComponent
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
