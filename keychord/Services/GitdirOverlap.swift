import Foundation

/// Two or more managed `gitdir:` scopes matching the same repository —
/// `gitdir:~/` and `gitdir:~/work/` both cover `~/work/api`.
///
/// git applies every matching `includeIf` in file order and the last one wins
/// (see ``GitdirPrecedence``), so which identity actually signs a commit is not
/// obvious from the account list. This describes the pile-up in the order git
/// reads it, names the winner, and is what the match card explains.
struct GitdirOverlap: Equatable, Sendable {
    struct Contender: Equatable, Sendable, Identifiable {
        let account: Account
        /// The account's `gitdir:` path that matches this repository.
        let path: String
        /// Directory depth of `path`; higher is more specific.
        let specificity: Int
        /// True for the block git applies last.
        let isWinner: Bool

        var id: String { "\(account.id.uuidString)::\(path)" }

        var displayLabel: String {
            account.label.isEmpty ? String.loc("(unnamed)") : account.label
        }
    }

    let repoRoot: String
    /// In the order git applies them: the winner is last.
    let contenders: [Contender]

    var winner: Contender? { contenders.last }
    var losers: [Contender] { contenders.dropLast().map { $0 } }

    /// True when the winner also happens to be the most specific scope, which
    /// is what the projector's ordering guarantees. False would mean the file
    /// on disk is stale — worth saying plainly instead of claiming precedence
    /// we did not verify.
    var winnerIsMostSpecific: Bool {
        guard let winner else { return false }
        return contenders.allSatisfy { $0.specificity <= winner.specificity }
    }

    // MARK: - Detect

    /// `nil` unless at least two distinct accounts scope this repository. One
    /// account owning both `~/` and `~/work/` is not a conflict — the identity
    /// is the same either way.
    static func detect(repoRoot: String, accounts: [Account]) -> GitdirOverlap? {
        let blocks = GitdirPrecedence.matchingBlocks(forRepoRoot: repoRoot, accounts: accounts)
        guard Set(blocks.map(\.accountID)).count > 1 else { return nil }

        let lastIndex = blocks.count - 1
        let contenders = blocks.enumerated().compactMap { index, block -> Contender? in
            guard let account = accounts.first(where: { $0.id == block.accountID }) else {
                return nil
            }
            return Contender(
                account: account,
                path: block.storedPath,
                specificity: GitdirPrecedence.specificity(ofPattern: block.pattern),
                isWinner: index == lastIndex
            )
        }
        guard contenders.count > 1 else { return nil }
        return GitdirOverlap(repoRoot: repoRoot, contenders: contenders)
    }
}
