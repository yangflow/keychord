import Testing
import Foundation
@testable import keychord

@Suite("CurrentRepoResolver")
struct CurrentRepoResolverTests {

    /// Isolate every git call from the developer's real ~/.gitconfig and
    /// /etc/gitconfig so tests are deterministic regardless of the machine
    /// they run on. `/dev/null` is a valid "empty config file" for git.
    static let isolatedEnv: [String: String] = [
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_SYSTEM": "/dev/null"
    ]

    // MARK: - extractSSHAlias

    @Test func extractsAliasFromGitAtUrl() {
        #expect(CurrentRepoResolver.extractSSHAlias(from: "git@github.com:foo/bar.git") == "github.com")
        #expect(CurrentRepoResolver.extractSSHAlias(from: "git@github-work:Org/repo.git") == "github-work")
        #expect(CurrentRepoResolver.extractSSHAlias(from: "deploy@example.com:private/app.git") == "example.com")
    }

    @Test func returnsNilForHttpsUrl() {
        #expect(CurrentRepoResolver.extractSSHAlias(from: "https://github.com/foo/bar.git") == nil)
        #expect(CurrentRepoResolver.extractSSHAlias(from: "http://example.com/repo.git") == nil)
    }

    @Test func returnsNilForNonsense() {
        #expect(CurrentRepoResolver.extractSSHAlias(from: "") == nil)
        #expect(CurrentRepoResolver.extractSSHAlias(from: "just-a-path") == nil)
        #expect(CurrentRepoResolver.extractSSHAlias(from: "/absolute/path") == nil)
    }

    // MARK: - resolveSync against a temp git repo

    static func makeRepo(
        userName: String = "alice",
        userEmail: String = "alice@example.com",
        originURL: String? = "git@github-work:TestOrg/TestRepo.git"
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // git init
        try runGit(at: tmp.path, args: ["init", "-q"])
        try runGit(at: tmp.path, args: ["config", "user.name", userName])
        try runGit(at: tmp.path, args: ["config", "user.email", userEmail])
        if let origin = originURL {
            try runGit(at: tmp.path, args: ["remote", "add", "origin", origin])
        }
        return tmp
    }

    static func runGit(at dir: String, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir] + args

        var env = ProcessInfo.processInfo.environment
        for (k, v) in Self.isolatedEnv { env[k] = v }
        process.environment = env

        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "test", code: Int(process.terminationStatus))
        }
    }

    @Test func resolvesRepoWithOrigin() throws {
        let repo = try Self.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        var model = ConfigModel()
        model.sshHosts = [
            SSHHost(alias: "github-work", hostName: "ssh.github.com", port: 443, identityFile: "~/.ssh/id_rsa")
        ]

        let result = CurrentRepoResolver.resolveSync(
            path: repo.path,
            model: model,
            env: Self.isolatedEnv
        )
        guard case .success(let resolved) = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(resolved.userName == "alice")
        #expect(resolved.userEmail == "alice@example.com")
        #expect(resolved.originURL == "git@github-work:TestOrg/TestRepo.git")
        #expect(resolved.sshAlias == "github-work")
        #expect(resolved.matchedHost?.alias == "github-work")
        #expect(resolved.identityFile == "~/.ssh/id_rsa")
    }

    @Test func resolvesRepoWithoutMatchingHost() throws {
        let repo = try Self.makeRepo(originURL: "git@unknown-host:X/Y.git")
        defer { try? FileManager.default.removeItem(at: repo) }

        let result = CurrentRepoResolver.resolveSync(
            path: repo.path,
            model: ConfigModel(),
            env: Self.isolatedEnv
        )
        guard case .success(let resolved) = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(resolved.sshAlias == "unknown-host")
        #expect(resolved.matchedHost == nil)
        #expect(resolved.identityFile == nil)
    }

    @Test func resolvesHttpsRepoWithNoAlias() throws {
        let repo = try Self.makeRepo(originURL: "https://github.com/foo/bar.git")
        defer { try? FileManager.default.removeItem(at: repo) }

        let result = CurrentRepoResolver.resolveSync(
            path: repo.path,
            model: ConfigModel(),
            env: Self.isolatedEnv
        )
        guard case .success(let resolved) = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(resolved.sshAlias == nil)
        #expect(resolved.matchedHost == nil)
    }

    @Test func failsOnRepoWithNoOrigin() throws {
        let repo = try Self.makeRepo(originURL: nil)
        defer { try? FileManager.default.removeItem(at: repo) }

        let result = CurrentRepoResolver.resolveSync(
            path: repo.path,
            model: ConfigModel(),
            env: Self.isolatedEnv
        )
        if case .failure(.noOrigin) = result {
            // expected
        } else {
            Issue.record("Expected .noOrigin, got \(result)")
        }
    }

    @Test func failsOnNonRepoPath() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-not-a-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = CurrentRepoResolver.resolveSync(
            path: tmp.path,
            model: ConfigModel(),
            env: Self.isolatedEnv
        )
        if case .failure(.notARepo) = result {
            // expected
        } else {
            Issue.record("Expected .notARepo, got \(result)")
        }
    }

    // MARK: - matchAccount (scoped dir + empty states)

    @Test func matchAccountResolvesScopedGitdir() throws {
        let scopeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-scope-\(UUID().uuidString)")
        let repo = try Self.makeRepo(
            under: scopeRoot.appendingPathComponent("project")
        )
        defer { try? FileManager.default.removeItem(at: scopeRoot) }

        let work = Account.new(
            label: "Work",
            sshAlias: "github-work",
            keyPath: "~/.ssh/id_work",
            gitUserName: "Work User",
            gitUserEmail: "work@example.com",
            scope: .gitdir(scopeRoot.path + "/"),
            color: .orange
        )
        let personal = Account.new(
            label: "Personal",
            sshAlias: "github.com",
            keyPath: "~/.ssh/id_personal",
            gitUserName: "Personal",
            gitUserEmail: "me@example.com",
            scope: .global,
            color: .blue
        )

        let result = CurrentRepoResolver.matchAccountSync(
            path: repo.path,
            accounts: [personal, work],
            env: Self.isolatedEnv
        )
        guard case .matched(let account, let root, let originURL) = result else {
            Issue.record("Expected scoped match, got \(result)")
            return
        }
        #expect(account.id == work.id)
        #expect(account.label == "Work")
        #expect(account.sshAlias == "github-work")
        #expect(account.gitUserEmail == "work@example.com")
        #expect(account.scope.isScoped)
        let expectedRoot = repo.resolvingSymlinksInPath().path
        #expect(root == expectedRoot || root == repo.path)
        #expect(originURL == "git@github-work:TestOrg/TestRepo.git")
    }

    @Test func matchAccountReportsNotARepoForEmptyDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = CurrentRepoResolver.matchAccountSync(
            path: tmp.path,
            accounts: [],
            env: Self.isolatedEnv
        )
        guard case .notARepo(let path) = result else {
            Issue.record("Expected .notARepo, got \(result)")
            return
        }
        #expect(path == tmp.path)
        #expect(result.unresolvedReason?.contains("is not a git repository") == true)
    }

    @Test func matchAccountsPicksMostSpecificGitdir() {
        let root = "/Users/demo/work/client/repo"
        let broad = Account.new(
            label: "Work",
            sshAlias: "work",
            keyPath: "~/.ssh/id_work",
            gitUserName: "W",
            gitUserEmail: "w@example.com",
            scope: .gitdir("/Users/demo/work/"),
            color: .orange
        )
        let specific = Account.new(
            label: "Client",
            sshAlias: "client",
            keyPath: "~/.ssh/id_client",
            gitUserName: "C",
            gitUserEmail: "c@example.com",
            scope: .gitdir("/Users/demo/work/client/"),
            color: .green
        )

        let result = CurrentRepoResolver.matchAccounts(
            forRepoRoot: root,
            accounts: [broad, specific]
        )
        guard case .matched(let account, _, _) = result else {
            Issue.record("Expected match, got \(result)")
            return
        }
        #expect(account.label == "Client")
    }

    @Test func matchAccountsReportsNoMatchingGitdir() {
        let scoped = Account.new(
            label: "Work",
            sshAlias: "work",
            keyPath: "~/.ssh/id_work",
            gitUserName: "W",
            gitUserEmail: "w@example.com",
            scope: .gitdir("/only/work/"),
            color: .orange
        )
        let result = CurrentRepoResolver.matchAccounts(
            forRepoRoot: "/elsewhere/repo",
            accounts: [scoped]
        )
        guard case .noMatchingGitdir(let root) = result else {
            Issue.record("Expected .noMatchingGitdir, got \(result)")
            return
        }
        #expect(root == "/elsewhere/repo")
        #expect(result.unresolvedReason?.contains("No matching gitdir") == true)
    }

    @Test func matchAccountsReportsConflictingGlobals() {
        let a = Account.new(
            label: "A",
            sshAlias: "a",
            keyPath: "~/.ssh/id_a",
            gitUserName: "A",
            gitUserEmail: "a@example.com",
            scope: .global,
            color: .blue
        )
        let b = Account.new(
            label: "B",
            sshAlias: "b",
            keyPath: "~/.ssh/id_b",
            gitUserName: "B",
            gitUserEmail: "b@example.com",
            scope: .global,
            color: .green
        )
        let result = CurrentRepoResolver.matchAccounts(
            forRepoRoot: "/tmp/repo",
            accounts: [a, b]
        )
        guard case .conflictingGlobals(_, let accounts) = result else {
            Issue.record("Expected .conflictingGlobals, got \(result)")
            return
        }
        #expect(accounts.count == 2)
        #expect(result.unresolvedReason?.contains("Conflicting global") == true)
    }

    @Test func matchAccountsFallsBackToSingleGlobal() {
        let global = Account.new(
            label: "Personal",
            sshAlias: "github.com",
            keyPath: "~/.ssh/id",
            gitUserName: "Me",
            gitUserEmail: "me@example.com",
            scope: .global,
            color: .blue
        )
        let result = CurrentRepoResolver.matchAccounts(
            forRepoRoot: "/tmp/any-repo",
            accounts: [global]
        )
        guard case .matched(let account, _, _) = result else {
            Issue.record("Expected global match, got \(result)")
            return
        }
        #expect(account.id == global.id)
    }

    // MARK: - normalizeGitdir (storage form from folder picker)

    @Test func normalizeGitdirAddsTrailingSlashToAbsoluteHomePath() {
        let abs = NSHomeDirectory() + "/work"
        #expect(CurrentRepoResolver.normalizeGitdir(abs) == "~/work/")
    }

    @Test func normalizeGitdirAddsTrailingSlashToTildePath() {
        #expect(CurrentRepoResolver.normalizeGitdir("~/work") == "~/work/")
        #expect(CurrentRepoResolver.normalizeGitdir("~/work/") == "~/work/")
    }

    @Test func normalizeGitdirTrimsWhitespace() {
        #expect(CurrentRepoResolver.normalizeGitdir("  ~/projects  ") == "~/projects/")
    }

    @Test func normalizeGitdirLeavesEmptyUnchanged() {
        #expect(CurrentRepoResolver.normalizeGitdir("") == "")
        #expect(CurrentRepoResolver.normalizeGitdir("   ") == "")
    }

    @Test func normalizeGitdirKeepsNonHomeAbsolutePath() {
        #expect(CurrentRepoResolver.normalizeGitdir("/opt/repos") == "/opt/repos/")
    }

    @Test func ensureTrailingSlashIsIdempotent() {
        #expect(CurrentRepoResolver.ensureTrailingSlash("/a/b") == "/a/b/")
        #expect(CurrentRepoResolver.ensureTrailingSlash("/a/b/") == "/a/b/")
        #expect(CurrentRepoResolver.ensureTrailingSlash("") == "")
    }

    // MARK: - Helpers

    static func makeRepo(
        under parent: URL,
        userName: String = "alice",
        userEmail: String = "alice@example.com",
        originURL: String? = "git@github-work:TestOrg/TestRepo.git"
    ) throws -> URL {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try runGit(at: parent.path, args: ["init", "-q"])
        try runGit(at: parent.path, args: ["config", "user.name", userName])
        try runGit(at: parent.path, args: ["config", "user.email", userEmail])
        if let origin = originURL {
            try runGit(at: parent.path, args: ["remote", "add", "origin", origin])
        }
        return parent
    }
}
