import Foundation

/// Pure rules for pointing an account's `gitdir:` scope at a folder the user
/// dropped on the menu-bar icon. Binding **adds** a path — an account can own
/// `~/work/` and `~/src/new-app/` at once — so a one-tap bind can never drop
/// a directory the user configured earlier.
///
/// Persistence (AccountsStore save + AccountProjector regenerate) stays with
/// the caller so a failed write can be reported on the match card.
enum GitdirBinder {

    enum Outcome: Equatable, Sendable {
        /// `path` was appended to the account's scope (storage form).
        case added(path: String)
        /// An existing `gitdir:` path already covers the folder, so the scope
        /// is unchanged and git already resolves this repo to the account.
        case alreadyCovered(by: String)
        /// `path` was removed from the account's scope.
        case removed(path: String)
        /// The account has no `gitdir:` entry for exactly this folder, so there
        /// is nothing to remove — a parent scope is deliberately left alone.
        case notBoundExactly
        /// The dropped path was blank.
        case invalidPath
    }

    struct Result: Equatable, Sendable {
        let account: Account
        let outcome: Outcome

        /// Whether the caller has to persist + reproject.
        var changedScope: Bool {
            switch outcome {
            case .added, .removed:
                return true
            case .alreadyCovered, .notBoundExactly, .invalidPath:
                return false
            }
        }
    }

    /// Add `folderPath` to `account`'s gitdir scope. A global account becomes
    /// scoped; a scoped account keeps every path it had.
    static func bind(folderPath: String, to account: Account) -> Result {
        let normalized = CurrentRepoResolver.normalizeGitdir(folderPath)
        guard !normalized.isEmpty else {
            return Result(account: account, outcome: .invalidPath)
        }
        if let covering = coveringPath(forFolderPath: folderPath, in: account.scope) {
            return Result(account: account, outcome: .alreadyCovered(by: covering))
        }
        var next = account
        next.scope = .gitdir(paths: account.scope.directories + [normalized])
        return Result(account: next, outcome: .added(path: normalized))
    }

    /// Drop `folderPath` from `account`'s gitdir scope. Only an entry for
    /// exactly this folder is removed: unbinding one repository must not pull
    /// a parent scope like `~/work/` out from under its siblings.
    ///
    /// Removing the last path leaves an empty gitdir scope rather than turning
    /// the account global, which would silently claim every other repository.
    static func unbind(folderPath: String, from account: Account) -> Result {
        guard let stored = exactPath(forFolderPath: folderPath, in: account.scope) else {
            return Result(account: account, outcome: .notBoundExactly)
        }
        var next = account
        next.scope = .gitdir(paths: account.scope.directories.filter { $0 != stored })
        return Result(account: next, outcome: .removed(path: stored))
    }

    /// Remove one stored `gitdir:` entry by value — used to unbind the broader
    /// scope that loses an overlap (`personal`'s `~/`), which is not the folder
    /// the user dropped.
    static func removePath(_ storedPath: String, from account: Account) -> Result {
        let target = CurrentRepoResolver.normalizeGitdir(storedPath)
        guard !target.isEmpty else {
            return Result(account: account, outcome: .invalidPath)
        }
        let remaining = account.scope.directories.filter {
            CurrentRepoResolver.normalizeGitdir($0) != target
        }
        guard remaining.count != account.scope.directories.count else {
            return Result(account: account, outcome: .notBoundExactly)
        }
        var next = account
        next.scope = .gitdir(paths: remaining)
        return Result(account: next, outcome: .removed(path: target))
    }

    /// The stored `gitdir:` entry that points at exactly `folderPath` (after
    /// normalization), if the scope has one. Parent scopes do not count.
    static func exactPath(forFolderPath folderPath: String, in scope: Account.Scope) -> String? {
        let target = CurrentRepoResolver.normalizeGitdirPattern(folderPath)
        guard !target.isEmpty else { return nil }
        return scope.directories.first { raw in
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return CurrentRepoResolver.normalizeGitdirPattern(raw) == target
        }
    }

    /// The existing `gitdir:` path of `scope` that git would already match for
    /// a repository at `folderPath`, if any. Prefers the most specific hit so
    /// the caption can name the closest parent.
    static func coveringPath(forFolderPath folderPath: String, in scope: Account.Scope) -> String? {
        let repoRoot = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoRoot.isEmpty else { return nil }
        return scope.directories
            .filter { raw in
                let pattern = CurrentRepoResolver.normalizeGitdirPattern(raw)
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return false
                }
                return CurrentRepoResolver.gitdirMatches(repoRoot: repoRoot, pattern: pattern)
            }
            .max(by: { $0.count < $1.count })
    }
}
