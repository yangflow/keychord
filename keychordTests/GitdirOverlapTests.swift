import Testing
import Foundation
@testable import keychord

@Suite("GitdirOverlap")
struct GitdirOverlapTests {

    static func account(label: String, paths: [String]) -> Account {
        Account.new(
            label: label,
            sshAlias: "github-\(label)",
            keyPath: "~/.ssh/id_\(label)",
            gitUserName: label,
            gitUserEmail: "\(label)@example.com",
            scope: .gitdir(paths: paths)
        )
    }

    static let personal = account(label: "personal", paths: ["/Users/demo/"])
    static let workAccount = account(label: "work", paths: ["/Users/demo/work/"])

    // MARK: - Detection

    @Test func twoAccountsCoveringOneRepoAreAnOverlap() throws {
        let overlap = try #require(
            GitdirOverlap.detect(
                repoRoot: "/Users/demo/work/api",
                accounts: [Self.workAccount, Self.personal]
            )
        )
        // Ordered the way git reads them: broad first, specific last.
        #expect(overlap.contenders.map(\.displayLabel) == ["personal", "work"])
        #expect(overlap.winner?.displayLabel == "work")
        #expect(overlap.losers.map(\.displayLabel) == ["personal"])
        #expect(overlap.winner?.path == "/Users/demo/work/")
        #expect(overlap.winnerIsMostSpecific)
    }

    @Test func winnerFlagMatchesTheLastContender() throws {
        let overlap = try #require(
            GitdirOverlap.detect(
                repoRoot: "/Users/demo/work/api",
                accounts: [Self.personal, Self.workAccount]
            )
        )
        #expect(overlap.contenders.last?.isWinner == true)
        #expect(overlap.contenders.dropLast().allSatisfy { !$0.isWinner })
    }

    @Test func oneMatchingAccountIsNotAnOverlap() {
        #expect(
            GitdirOverlap.detect(
                repoRoot: "/Users/demo/work/api",
                accounts: [Self.workAccount]
            ) == nil
        )
    }

    @Test func noMatchIsNotAnOverlap() {
        #expect(
            GitdirOverlap.detect(
                repoRoot: "/Users/demo/elsewhere",
                accounts: [Self.workAccount, Self.personal]
            ) == nil
        )
    }

    @Test func oneAccountOwningBothPathsIsNotAConflict() {
        let both = Self.account(
            label: "work",
            paths: ["/Users/demo/", "/Users/demo/work/"]
        )
        // Same identity either way — nothing for the user to decide.
        #expect(
            GitdirOverlap.detect(repoRoot: "/Users/demo/work/api", accounts: [both]) == nil
        )
    }

    @Test func threeWayOverlapKeepsEveryContender() throws {
        let deep = Self.account(label: "deep", paths: ["/Users/demo/work/client/"])
        let overlap = try #require(
            GitdirOverlap.detect(
                repoRoot: "/Users/demo/work/client/api",
                accounts: [Self.personal, Self.workAccount, deep]
            )
        )
        #expect(overlap.contenders.map(\.displayLabel) == ["personal", "work", "deep"])
        #expect(overlap.winner?.displayLabel == "deep")
        #expect(overlap.losers.map(\.displayLabel) == ["personal", "work"])
    }

    @Test func unnamedAccountsGetAPlaceholderLabel() throws {
        let unnamed = Self.account(label: "", paths: ["/Users/demo/"])
        let overlap = try #require(
            GitdirOverlap.detect(
                repoRoot: "/Users/demo/work/api",
                accounts: [unnamed, Self.workAccount]
            )
        )
        #expect(overlap.contenders.first?.displayLabel.isEmpty == false)
    }

    // MARK: - Agreement with the resolver

    @Test func overlapWinnerIsTheAccountTheResolverReports() {
        let accounts = [Self.workAccount, Self.personal]
        let result = CurrentRepoResolver.matchAccounts(
            forRepoRoot: "/Users/demo/work/api",
            accounts: accounts
        )
        guard case .matched(let account, _, _) = result else {
            Issue.record("Expected a match, got \(result)")
            return
        }
        let overlap = GitdirOverlap.detect(
            repoRoot: "/Users/demo/work/api",
            accounts: accounts
        )
        #expect(overlap?.winner?.account.id == account.id)
    }
}
