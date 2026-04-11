import Foundation

struct GitConfigIO: Sendable {
    let filePath: String
    let runner: any ProcessRunner

    init(filePath: String, runner: any ProcessRunner = SystemProcessRunner.shared) {
        self.filePath = filePath
        self.runner = runner
    }

    struct Entry: Equatable, Hashable {
        var key: String
        var value: String
    }

    struct Extraction: Equatable {
        var identity: GitIdentity?
        var insteadOf: [InsteadOfRule]
        var includeIf: [IncludeIfRule]
    }

    enum IOError: Swift.Error, CustomStringConvertible {
        case gitNotFound
        case fileNotFound(String)
        case commandFailed(code: Int32, stderr: String)

        var description: String {
            switch self {
            case .gitNotFound:
                return "git not found at /usr/bin/git"
            case .fileNotFound(let p):
                return "gitconfig file not found: \(p)"
            case .commandFailed(let code, let stderr):
                return "git config exited \(code): \(stderr)"
            }
        }
    }

    // MARK: - Read

    func listAll() throws -> [Entry] {
        let out = try runGitConfig(args: ["--file", filePath, "--list", "-z"])
        return Self.parseListOutput(out)
    }

    static func parseListOutput(_ raw: String) -> [Entry] {
        var entries: [Entry] = []
        for chunk in raw.split(separator: "\0", omittingEmptySubsequences: true) {
            let s = String(chunk)
            if let nl = s.firstIndex(of: "\n") {
                let key = String(s[..<nl])
                let value = String(s[s.index(after: nl)...])
                entries.append(Entry(key: key, value: value))
            } else {
                entries.append(Entry(key: s, value: ""))
            }
        }
        return entries
    }

    // MARK: - Model extraction

    func extractModel(includeCondition: String? = nil) throws -> Extraction {
        let entries = try listAll()

        var userName: String?
        var userEmail: String?
        var sshCommand: String?
        var insteadOf: [InsteadOfRule] = []
        var includeIf: [IncludeIfRule] = []

        for entry in entries {
            let key = entry.key
            let value = entry.value

            if key == "user.name" {
                userName = value
            } else if key == "user.email" {
                userEmail = value
            } else if key == "core.sshcommand" {
                sshCommand = value
            } else if key.hasPrefix("url.") && key.hasSuffix(".insteadof") {
                let subsection = String(
                    key.dropFirst("url.".count).dropLast(".insteadof".count)
                )
                insteadOf.append(InsteadOfRule(
                    from: value,
                    to: subsection,
                    sourceFile: filePath,
                    direction: .insteadOf
                ))
            } else if key.hasPrefix("url.") && key.hasSuffix(".pushinsteadof") {
                let subsection = String(
                    key.dropFirst("url.".count).dropLast(".pushinsteadof".count)
                )
                insteadOf.append(InsteadOfRule(
                    from: value,
                    to: subsection,
                    sourceFile: filePath,
                    direction: .pushInsteadOf
                ))
            } else if key.hasPrefix("includeif.") && key.hasSuffix(".path") {
                let condition = String(
                    key.dropFirst("includeif.".count).dropLast(".path".count)
                )
                includeIf.append(IncludeIfRule(
                    condition: condition,
                    path: value,
                    sourceFile: filePath
                ))
            }
        }

        let identity: GitIdentity?
        if let userName, let userEmail {
            identity = GitIdentity(
                name: userName,
                email: userEmail,
                sourceFile: filePath,
                includeCondition: includeCondition,
                sshCommand: sshCommand
            )
        } else {
            identity = nil
        }

        return Extraction(identity: identity, insteadOf: insteadOf, includeIf: includeIf)
    }

    // MARK: - Write

    func set(_ key: String, to value: String) throws {
        try runGitConfig(args: ["--file", filePath, key, value])
    }

    func add(_ key: String, _ value: String) throws {
        try runGitConfig(args: ["--file", filePath, "--add", key, value])
    }

    func unsetAll(_ key: String) throws {
        do {
            try runGitConfig(args: ["--file", filePath, "--unset-all", key])
        } catch IOError.commandFailed(let code, _) where code == 5 {
            // exit 5 = key not found, treat as idempotent success
            return
        }
    }

    // MARK: - Process runner

    @discardableResult
    private func runGitConfig(args: [String]) throws -> String {
        let result = runner.run(
            executable: "/usr/bin/git",
            arguments: ["config"] + args,
            environment: nil
        )
        if result.exitCode != 0 {
            throw IOError.commandFailed(code: result.exitCode, stderr: result.stderr)
        }
        return result.stdout
    }
}
