import Foundation

/// The `user.name` / `user.email` git would use when nothing else applies —
/// what a brand new account should start from instead of two empty fields.
enum GitGlobalIdentity {

    struct Identity: Equatable, Sendable {
        var name: String
        var email: String

        static let empty = Identity(name: "", email: "")

        var isEmpty: Bool { name.isEmpty && email.isEmpty }
    }

    static func read(
        env: [String: String]? = nil,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) async -> Identity {
        await Task.detached(priority: .userInitiated) {
            readSync(env: env, runner: runner)
        }.value
    }

    static func readSync(
        env: [String: String]? = nil,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> Identity {
        Identity(
            name: value(of: "user.name", env: env, runner: runner),
            email: value(of: "user.email", env: env, runner: runner)
        )
    }

    /// `git config --global --get <key>`; empty when unset (exit 1) or when git
    /// cannot run at all.
    private static func value(
        of key: String,
        env: [String: String]?,
        runner: any ProcessRunner
    ) -> String {
        let result = runner.run(
            executable: "/usr/bin/git",
            arguments: ["config", "--global", "--get", key],
            environment: env
        )
        guard result.exitCode == 0 else { return "" }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Builder for the account a failed drop offers to create. Pure so the prefill
/// rules are testable without opening a window.
enum DroppedFolderAccountDraft {

    /// A new, unsaved account already scoped to the dropped folder: gitdir in
    /// storage form, git identity seeded from the global config, port 443, and
    /// the next unused palette color. Label / alias / key stay empty for the
    /// user to fill in the Accounts window.
    static func make(
        folderPath: String,
        globalIdentity: GitGlobalIdentity.Identity = .empty,
        existingAccounts: [Account] = [],
        id: UUID = UUID(),
        now: Date = Date()
    ) -> Account? {
        let scopePath = CurrentRepoResolver.normalizeGitdir(folderPath)
        guard !scopePath.isEmpty else { return nil }

        return Account(
            id: id,
            label: "",
            username: "",
            provider: .github,
            sshAlias: "",
            keyPath: "",
            keyFingerprint: nil,
            sshPort: .port443,
            gitUserName: globalIdentity.name,
            gitUserEmail: globalIdentity.email,
            scope: .gitdir(paths: [scopePath]),
            urlRewrites: [],
            color: nextColor(after: existingAccounts),
            notes: "",
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil
        )
    }

    /// First preset color no account uses yet, else cycle by count so two new
    /// accounts in a row do not look identical.
    static func nextColor(after accounts: [Account]) -> Account.AccountColor {
        let taken = Set(accounts.map(\.color.rawValue))
        let presets = Account.AccountColor.presets
        if let free = presets.first(where: { !taken.contains($0.rawValue) }) {
            return free
        }
        return presets[accounts.count % presets.count]
    }
}
