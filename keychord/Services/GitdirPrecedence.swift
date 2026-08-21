import Foundation

/// Ordering of `includeIf "gitdir:…"` blocks, and which one git ends up using.
///
/// Verified against git rather than assumed: git evaluates **every** matching
/// `includeIf` in the order the blocks appear in the file and the **last** one
/// to set a key wins. Specificity plays no part — with
///
///     [includeIf "gitdir:~/work/"] path = work
///     [includeIf "gitdir:~/"]      path = personal
///
/// a repository in `~/work/api` commits as *personal*, because that block is
/// later in the file.
///
/// So "the most specific scope wins" is only true if we emit the blocks in that
/// order. ``blocks(for:)`` is the single ordering that the projector writes and
/// the resolver reads, which keeps the popover's answer equal to git's.
enum GitdirPrecedence {

    /// One projected `includeIf` line: which account it belongs to and the
    /// directory it matches.
    struct Block: Equatable, Hashable, Sendable, Identifiable {
        let accountID: UUID
        /// Position of the owning account in `accounts.json`, used only as a
        /// deterministic tiebreak between equally specific paths.
        let accountIndex: Int
        /// Storage form as the user typed it (`~/work/`).
        let storedPath: String
        /// Expanded, symlink-resolved, trailing-slash form git compares against.
        let pattern: String

        var id: String { "\(accountID.uuidString)::\(storedPath)" }
    }

    // MARK: - Emission order

    /// Every account's gitdir paths, ordered least specific first so the most
    /// specific `includeIf` is the last one git applies — and therefore wins.
    static func blocks(for accounts: [Account]) -> [Block] {
        var blocks: [Block] = []
        for (index, account) in accounts.enumerated() {
            var seen: Set<String> = []
            for raw in account.scope.directories {
                let stored = CurrentRepoResolver.normalizeGitdir(raw)
                guard !stored.isEmpty, !seen.contains(stored) else { continue }
                seen.insert(stored)
                blocks.append(Block(
                    accountID: account.id,
                    accountIndex: index,
                    storedPath: stored,
                    pattern: CurrentRepoResolver.normalizeGitdirPattern(stored)
                ))
            }
        }
        return blocks.sorted(by: isEmittedBefore)
    }

    /// Least specific first; ties broken by account order, then path, so the
    /// projection stays byte-stable across runs.
    static func isEmittedBefore(_ lhs: Block, _ rhs: Block) -> Bool {
        let left = specificity(ofPattern: lhs.pattern)
        let right = specificity(ofPattern: rhs.pattern)
        if left != right { return left < right }
        if lhs.pattern.count != rhs.pattern.count { return lhs.pattern.count < rhs.pattern.count }
        if lhs.accountIndex != rhs.accountIndex { return lhs.accountIndex < rhs.accountIndex }
        return lhs.storedPath < rhs.storedPath
    }

    /// Depth of a `gitdir:` prefix — `~/work/api/` is more specific than `~/`.
    static func specificity(ofPattern pattern: String) -> Int {
        pattern
            .split(separator: "/", omittingEmptySubsequences: true)
            .count
    }

    // MARK: - Resolution

    /// Blocks that match `repoRoot`, in the order git applies them.
    static func matchingBlocks(forRepoRoot repoRoot: String, accounts: [Account]) -> [Block] {
        blocks(for: accounts).filter {
            CurrentRepoResolver.gitdirMatches(repoRoot: repoRoot, pattern: $0.pattern)
        }
    }

    /// The block git honors: the last matching one in emission order.
    static func winningBlock(forRepoRoot repoRoot: String, accounts: [Account]) -> Block? {
        matchingBlocks(forRepoRoot: repoRoot, accounts: accounts).last
    }
}
