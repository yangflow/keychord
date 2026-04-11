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
}
