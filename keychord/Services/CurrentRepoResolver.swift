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

/// Which keychord account would apply to a working directory, based on
/// `gitdir:` scopes (and falling back to a single global account).
enum AccountMatchResult: Equatable, Sendable {
    /// `originURL` is `remote.origin.url` when present — used to prefill the
    /// popover clone field so copy works without retyping org/repo.
    case matched(account: Account, repoRoot: String, originURL: String?)
    case notARepo(path: String)
    case noMatchingGitdir(repoRoot: String)
    case conflictingGlobals(repoRoot: String, accounts: [Account])

    /// Short, user-facing explanation for unresolved cases.
    var unresolvedReason: String? {
        switch self {
        case .matched:
            return nil
        case .notARepo(let path):
            return String(localized: "\(Self.displayPath(path)) is not a git repository")
        case .noMatchingGitdir(let root):
            return String(localized: "No matching gitdir for \(Self.displayPath(root))")
        case .conflictingGlobals(let root, let accounts):
            let labels = accounts.map {
                $0.label.isEmpty ? String(localized: "(unnamed)") : $0.label
            }
            let joined = labels.joined(separator: ", ")
            return String(localized: "Conflicting global accounts (\(joined)) for \(Self.displayPath(root))")
        }
    }

    /// Repository root a one-tap `gitdir:` bind should use, when binding can
    /// fix this result. `nil` when there is nothing to scope — a matched
    /// account needs no bind, and a folder that is not a repository would not
    /// gain an identity from one.
    var bindableRepoRoot: String? {
        switch self {
        case .noMatchingGitdir(let repoRoot):
            return repoRoot
        case .conflictingGlobals(let repoRoot, _):
            return repoRoot
        case .matched, .notARepo:
            return nil
        }
    }

    private static func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
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

    // MARK: - Account match (gitdir scope)

    /// Resolve which keychord account would apply to `path`, using the
    /// same `gitdir:` prefix rules the projector writes into managed
    /// gitconfig. Does not rewrite any user config files.
    static func matchAccount(
        path: String,
        accounts: [Account],
        env: [String: String]? = nil,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) async -> AccountMatchResult {
        await Task.detached(priority: .userInitiated) {
            matchAccountSync(path: path, accounts: accounts, env: env, runner: runner)
        }.value
    }

    // MARK: - Effective git identity in a work tree

    /// What git itself would use for a commit in a directory, after
    /// `includeIf` resolution — the numbers to compare against the account
    /// that owns the SSH alias.
    struct EffectiveGitIdentity: Equatable, Sendable {
        var userName: String?
        var userEmail: String?
        /// `core.sshCommand`, which can pin a different private key than the
        /// `IdentityFile` of the Host block the remote resolves to.
        var sshCommand: String?
    }

    static func readEffectiveIdentity(
        at path: String,
        env: [String: String]? = nil,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) async -> EffectiveGitIdentity {
        await Task.detached(priority: .userInitiated) {
            readEffectiveIdentitySync(at: path, env: env, runner: runner)
        }.value
    }

    static func readEffectiveIdentitySync(
        at path: String,
        env: [String: String]? = nil,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> EffectiveGitIdentity {
        EffectiveGitIdentity(
            userName: stringOrNil(
                runGit(at: path, args: ["config", "--get", "user.name"], env: env, runner: runner)
            ),
            userEmail: stringOrNil(
                runGit(at: path, args: ["config", "--get", "user.email"], env: env, runner: runner)
            ),
            sshCommand: stringOrNil(
                runGit(at: path, args: ["config", "--get", "core.sshCommand"], env: env, runner: runner)
            )
        )
    }

    /// Read `remote.origin.url`, falling back to `ls-remote --get-url origin`.
    static func readOriginURL(
        at path: String,
        env: [String: String]? = nil,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) async -> String? {
        await Task.detached(priority: .userInitiated) {
            readOriginURLSync(at: path, env: env, runner: runner)
        }.value
    }

    static func readOriginURLSync(
        at path: String,
        env: [String: String]? = nil,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> String? {
        stringOrNil(
            runGit(at: path, args: ["config", "--get", "remote.origin.url"], env: env, runner: runner)
        ) ?? stringOrNil(
            runGit(at: path, args: ["ls-remote", "--get-url", "origin"], env: env, runner: runner)
        )
    }

    static func matchAccountSync(
        path: String,
        accounts: [Account],
        env: [String: String]? = nil,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> AccountMatchResult {
        let rootResult = runGit(at: path, args: ["rev-parse", "--show-toplevel"], env: env, runner: runner)
        guard case .success(let rootOut) = rootResult else {
            return .notARepo(path: path)
        }
        let repoRoot = rootOut.trimmingCharacters(in: .whitespacesAndNewlines)
        let originURL = readOriginURLSync(at: path, env: env, runner: runner)
        return matchAccounts(forRepoRoot: repoRoot, accounts: accounts, originURL: originURL)
    }

    /// Pure matching against an already-known repo root. Prefer the most
    /// specific (longest) `gitdir:` prefix; otherwise fall back to a single
    /// global account; multiple globals with no scoped hit → conflict.
    static func matchAccounts(
        forRepoRoot repoRoot: String,
        accounts: [Account],
        originURL: String? = nil
    ) -> AccountMatchResult {
        // Every gitdir path of every account competes; the longest matching
        // prefix wins, so a leaf scope still beats its parent.
        let scopedHits = accounts.flatMap { account in
            account.scope.directories.compactMap { raw -> (Account, String)? in
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                let pattern = normalizeGitdirPattern(raw)
                guard gitdirMatches(repoRoot: repoRoot, pattern: pattern) else { return nil }
                return (account, pattern)
            }
        }

        if let best = scopedHits.max(by: { $0.1.count < $1.1.count }) {
            return .matched(account: best.0, repoRoot: repoRoot, originURL: originURL)
        }

        let globals = accounts.filter { $0.scope == .global }
        switch globals.count {
        case 0:
            return .noMatchingGitdir(repoRoot: repoRoot)
        case 1:
            return .matched(account: globals[0], repoRoot: repoRoot, originURL: originURL)
        default:
            return .conflictingGlobals(repoRoot: repoRoot, accounts: globals)
        }
    }

    /// Ensure a path ends with `/` (empty string stays empty).
    static func ensureTrailingSlash(_ path: String) -> String {
        if path.isEmpty || path.hasSuffix("/") { return path }
        return path + "/"
    }

    /// Storage / projection form for a `gitdir:` scope: tilde-abbreviate
    /// when under `$HOME`, always end with `/` (git includeIf prefix).
    /// Does not expand `~` away — keeps portable account JSON.
    static func normalizeGitdir(_ raw: String) -> String {
        var dir = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dir.isEmpty else { return dir }
        dir = AccountProjector.toTilde(dir)
        return ensureTrailingSlash(dir)
    }

    /// `gitdir:` patterns ending in `/` are prefixes of the `.git` path.
    /// Expands `~` and resolves symlinks so `/var/...` and
    /// `/private/var/...` compare equal.
    static func normalizeGitdirPattern(_ raw: String) -> String {
        ensureTrailingSlash(resolveFilesystemPath(ConfigStore.expand(raw)))
    }

    static func gitdirMatches(repoRoot: String, pattern: String) -> Bool {
        // git includeIf "gitdir:<pattern>/" matches when the repository's
        // .git directory path starts with <pattern>/.
        var root = resolveFilesystemPath(ConfigStore.expand(repoRoot))
        if root.hasSuffix("/") {
            root = String(root.dropLast())
        }
        let gitDirPath = root + "/.git"
        return gitDirPath.hasPrefix(pattern)
    }

    private static func resolveFilesystemPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
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
