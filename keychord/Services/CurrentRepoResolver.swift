import Foundation

struct ResolvedRepo: Equatable, Sendable {
    var workingDirectory: String
    var repoRoot: String
    var userName: String?
    var userEmail: String?
    var originURL: String?         // raw from git config
    var effectiveURL: String?      // after insteadOf rewrite, from `git ls-remote --get-url`
    var sshAlias: String?          // parsed out of effectiveURL
    var matchedHost: SSHHost?      // Host block in model matching the alias
    var identityFile: String?      // from matchedHost
}

enum CurrentRepoResolver {

    enum ResolveError: Swift.Error, Equatable, CustomStringConvertible {
        case notARepo(path: String)
        case gitFailed(stderr: String)
        case noOrigin

        var description: String {
            switch self {
            case .notARepo(let p): return "\(p) is not a git repository"
            case .gitFailed(let e): return "git failed: \(e)"
            case .noOrigin:        return "repo has no `origin` remote"
            }
        }
    }

    // MARK: - Entry points

    static func resolve(
        path: String,
        model: ConfigModel,
        env: [String: String]? = nil,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) async -> Result<ResolvedRepo, ResolveError> {
        await Task.detached(priority: .userInitiated) {
            resolveSync(path: path, model: model, env: env, runner: runner)
        }.value
    }

    static func resolveSync(
        path: String,
        model: ConfigModel,
        env: [String: String]? = nil,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> Result<ResolvedRepo, ResolveError> {
        // 1. Is it a git repo?
        let rootResult = runGit(at: path, args: ["rev-parse", "--show-toplevel"], env: env, runner: runner)
        guard case .success(let rootOut) = rootResult else {
            return .failure(.notARepo(path: path))
        }
        let repoRoot = rootOut.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Identity (respects includeIf)
        let name = stringOrNil(runGit(at: path, args: ["config", "user.name"], env: env, runner: runner))
        let email = stringOrNil(runGit(at: path, args: ["config", "user.email"], env: env, runner: runner))

        // 3. Raw origin URL (as declared in config). This is the source of truth
        //    for "does the repo have an origin remote?" — `git config --get` fails
        //    cleanly if the key is missing, whereas `ls-remote --get-url` echoes
        //    the literal remote name back when the remote does not exist.
        let rawURL = stringOrNil(runGit(at: path, args: ["config", "--get", "remote.origin.url"], env: env, runner: runner))

        guard rawURL != nil else {
            return .failure(.noOrigin)
        }

        // 4. Effective origin URL (after insteadOf). git's own resolver runs all
        //    insteadOf rewrites so we do not have to reimplement them.
        let effectiveURL = stringOrNil(runGit(at: path, args: ["ls-remote", "--get-url", "origin"], env: env, runner: runner))

        // 5. Parse SSH alias from the effective URL
        let alias = extractSSHAlias(from: effectiveURL ?? rawURL ?? "")

        // 6. Match the alias against our parsed SSH config
        let matched: SSHHost? = alias.flatMap { a in
            model.sshHosts.first(where: { $0.alias == a })
        }

        return .success(ResolvedRepo(
            workingDirectory: path,
            repoRoot: repoRoot,
            userName: name,
            userEmail: email,
            originURL: rawURL,
            effectiveURL: effectiveURL,
            sshAlias: alias,
            matchedHost: matched,
            identityFile: matched?.identityFile
        ))
    }

    // MARK: - URL → alias

    static func extractSSHAlias(from url: String) -> String? {
        // Matches `git@<host>:`, where <host> can contain letters, digits, `.`, `-`, `_`.
        // Does not match https:// URLs.
        let pattern = #"^[^@\s]+@([^:\s]+):"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        guard let match = regex.firstMatch(in: url, range: range),
              match.numberOfRanges >= 2,
              let hostRange = Range(match.range(at: 1), in: url) else {
            return nil
        }
        return String(url[hostRange])
    }

    // MARK: - git runner

    private static func runGit(
        at workingDir: String,
        args: [String],
        env: [String: String]? = nil,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> Result<String, ResolveError> {
        let result = runner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", workingDir] + args,
            environment: env
        )
        if result.exitCode != 0 {
            return .failure(.gitFailed(
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return .success(result.stdout)
    }

    private static func stringOrNil(_ result: Result<String, ResolveError>) -> String? {
        guard case .success(let s) = result else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
