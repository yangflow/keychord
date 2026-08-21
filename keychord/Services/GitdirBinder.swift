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
        /// The dropped path was blank.
        case invalidPath
    }

    struct Result: Equatable, Sendable {
        let account: Account
        let outcome: Outcome

        /// Whether the caller has to persist + reproject.
        var changedScope: Bool {
            if case .added = outcome { return true }
            return false
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
