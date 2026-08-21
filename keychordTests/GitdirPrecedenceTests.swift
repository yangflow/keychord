import Testing
import Foundation
@testable import keychord

@Suite("GitdirPrecedence")
struct GitdirPrecedenceTests {

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

    // MARK: - Emission order

    @Test func lessSpecificPathsAreEmittedFirst() {
        let personal = Self.account(label: "personal", paths: ["~/"])
        let work = Self.account(label: "work", paths: ["~/work/"])
        let deep = Self.account(label: "deep", paths: ["~/work/client/api/"])

        // Declaration order is deliberately the opposite of the right order.
        let blocks = GitdirPrecedence.blocks(for: [deep, work, personal])
        #expect(blocks.map(\.storedPath) == ["~/", "~/work/", "~/work/client/api/"])
    }

    @Test func emissionOrderIsStableForEquallySpecificPaths() {
        let a = Self.account(label: "a", paths: ["~/one/"])
        let b = Self.account(label: "b", paths: ["~/two/"])
        let first = GitdirPrecedence.blocks(for: [a, b]).map(\.storedPath)
        let second = GitdirPrecedence.blocks(for: [a, b]).map(\.storedPath)
        #expect(first == second)
        #expect(first == ["~/one/", "~/two/"])
    }

    @Test func blankAndDuplicatePathsAreDropped() {
        let messy = Self.account(label: "messy", paths: ["", "  ", "~/work", "~/work/"])
        let blocks = GitdirPrecedence.blocks(for: [messy])
        #expect(blocks.map(\.storedPath) == ["~/work/"])
    }

    @Test func globalAccountsContributeNoBlocks() {
        let global = Account.new(
            label: "global",
            sshAlias: "gh",
            keyPath: "~/.ssh/id",
            gitUserName: "G",
            gitUserEmail: "g@example.com",
            scope: .global
        )
        #expect(GitdirPrecedence.blocks(for: [global]).isEmpty)
    }

    // MARK: - Specificity

    @Test func specificityCountsPathComponents() {
        #expect(GitdirPrecedence.specificity(ofPattern: "/Users/demo/") == 2)
        #expect(GitdirPrecedence.specificity(ofPattern: "/Users/demo/work/") == 3)
        #expect(GitdirPrecedence.specificity(ofPattern: "/") == 0)
    }

    // MARK: - Winner

    @Test func theLastMatchingBlockWins() {
        let personal = Self.account(label: "personal", paths: ["/Users/demo/"])
        let work = Self.account(label: "work", paths: ["/Users/demo/work/"])

        let matching = GitdirPrecedence.matchingBlocks(
            forRepoRoot: "/Users/demo/work/api",
            accounts: [work, personal]
        )
        #expect(matching.map(\.storedPath) == ["/Users/demo/", "/Users/demo/work/"])

        let winner = GitdirPrecedence.winningBlock(
            forRepoRoot: "/Users/demo/work/api",
            accounts: [work, personal]
        )
        #expect(winner?.accountID == work.id)
    }

    @Test func nonMatchingRepoHasNoWinner() {
        let work = Self.account(label: "work", paths: ["/Users/demo/work/"])
        #expect(
            GitdirPrecedence.winningBlock(
                forRepoRoot: "/Users/demo/elsewhere",
                accounts: [work]
            ) == nil
        )
    }

    @Test func equallySpecificPathsResolveToTheLaterAccount() {
        let first = Self.account(label: "first", paths: ["/Users/demo/work/"])
        let second = Self.account(label: "second", paths: ["/Users/demo/work/"])
        let winner = GitdirPrecedence.winningBlock(
            forRepoRoot: "/Users/demo/work/api",
            accounts: [first, second]
        )
        // Same rule as git: the block written later takes effect.
        #expect(winner?.accountID == second.id)
    }

    // MARK: - Against real git

    /// The rule this whole type exists for: git applies every matching
    /// `includeIf` in file order and the last one wins, regardless of how
    /// specific the earlier ones were. Run against the real binary so a future
    /// git change cannot quietly invalidate the projection order.
    @Test func gitAppliesTheLastMatchingIncludeIfNotTheMostSpecific() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-precedence-\(UUID().uuidString)")
        let repo = home.appendingPathComponent("work/api")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try "[user]\n\temail = work@company.com\n".write(
            to: home.appendingPathComponent("inc-work"),
            atomically: true,
            encoding: .utf8
        )
        try "[user]\n\temail = personal@example.com\n".write(
            to: home.appendingPathComponent("inc-personal"),
            atomically: true,
            encoding: .utf8
        )
        try Self.runGit(at: repo.path, args: ["init", "-q"], home: home.path)

        func email(specificFirst: Bool) throws -> String? {
            let blocks = specificFirst
                ? "[includeIf \"gitdir:~/work/\"]\n\tpath = ~/inc-work\n"
                    + "[includeIf \"gitdir:~/\"]\n\tpath = ~/inc-personal\n"
                : "[includeIf \"gitdir:~/\"]\n\tpath = ~/inc-personal\n"
                    + "[includeIf \"gitdir:~/work/\"]\n\tpath = ~/inc-work\n"
            try blocks.write(
                to: home.appendingPathComponent(".gitconfig"),
                atomically: true,
                encoding: .utf8
            )
            return try Self.gitOutput(
                at: repo.path,
                args: ["config", "user.email"],
                home: home.path
            )
        }

        // Most specific first → the broad scope, being later, wins. This is
        // exactly the trap the emission order avoids.
        #expect(try email(specificFirst: true) == "personal@example.com")
        // Least specific first → the specific scope wins, which is what
        // `GitdirPrecedence.blocks(for:)` guarantees.
        #expect(try email(specificFirst: false) == "work@company.com")
    }

    // MARK: - git helpers

    static func runGit(at dir: String, args: [String], home: String) throws {
        _ = try gitOutput(at: dir, args: args, home: home)
    }

    @discardableResult
    static func gitOutput(at dir: String, args: [String], home: String) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir] + args

        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home
        env["GIT_CONFIG_SYSTEM"] = "/dev/null"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env.removeValue(forKey: "GIT_CONFIG_GLOBAL")
        process.environment = env

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
    }
}
