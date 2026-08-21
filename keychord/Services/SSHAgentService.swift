import Foundation

/// What we can learn about an account's private key without asking the user
/// for anything: does the file exist, is it passphrase-protected, and is it
/// already loaded in `ssh-agent`.
///
/// This is what separates “the forge has never seen this key” from “the key is
/// fine but the agent forgot it after a reboot”, which need different buttons.
struct SSHKeyState: Equatable, Sendable {
    /// No key path configured on the account at all.
    var hasKeyPath: Bool
    var privateKeyExists: Bool
    /// `true` only when `ssh-keygen` says the key needs a passphrase.
    var isEncrypted: Bool
    /// `true` when the key's fingerprint is in `ssh-add -l`. Always `false`
    /// when the agent is unreachable or the fingerprint is unknown.
    var isLoadedInAgent: Bool
    var agentReachable: Bool

    static let unknown = SSHKeyState(
        hasKeyPath: false,
        privateKeyExists: false,
        isEncrypted: false,
        isLoadedInAgent: false,
        agentReachable: false
    )
}

enum SSHAgentService {

    // MARK: - Gather

    static func keyState(
        for account: Account,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) async -> SSHKeyState {
        await Task.detached(priority: .userInitiated) {
            keyStateSync(for: account, runner: runner)
        }.value
    }

    static func keyStateSync(
        for account: Account,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> SSHKeyState {
        let path = account.keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return .unknown }

        let expanded = ConfigStore.expand(path)
        guard FileManager.default.fileExists(atPath: expanded) else {
            return SSHKeyState(
                hasKeyPath: true,
                privateKeyExists: false,
                isEncrypted: false,
                isLoadedInAgent: false,
                agentReachable: false
            )
        }

        let agent = loadedFingerprintsSync(runner: runner)
        let fingerprint = self.fingerprint(for: account, privateKeyPath: expanded, runner: runner)
        return SSHKeyState(
            hasKeyPath: true,
            privateKeyExists: true,
            isEncrypted: isEncryptedSync(privateKeyPath: expanded, runner: runner),
            isLoadedInAgent: fingerprint.map { agent.fingerprints.contains($0) } ?? false,
            agentReachable: agent.reachable
        )
    }

    /// Fingerprints currently held by `ssh-agent`, plus whether the agent
    /// answered at all (no agent → no “locked key” claims).
    static func loadedFingerprintsSync(
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> (reachable: Bool, fingerprints: Set<String>) {
        let result = runner.run(
            executable: "/usr/bin/ssh-add",
            arguments: ["-l", "-E", "sha256"],
            environment: nil
        )
        // 0 = identities listed, 1 = agent running but empty, 2 = no agent.
        guard result.exitCode == 0 || result.exitCode == 1 else {
            return (false, [])
        }
        return (true, parseFingerprints(result.stdout))
    }

    static func parseFingerprints(_ stdout: String) -> Set<String> {
        var out: Set<String> = []
        for line in stdout.split(whereSeparator: \.isNewline) {
            for token in line.split(whereSeparator: \.isWhitespace) {
                let value = String(token)
                if value.hasPrefix("SHA256:") {
                    out.insert(value)
                }
            }
        }
        return out
    }

    /// `ssh-keygen -y -P ""` never prompts: it exports the public half for an
    /// unprotected key and complains about the passphrase for a protected one.
    static func isEncryptedSync(
        privateKeyPath: String,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> Bool {
        let result = runner.run(
            executable: "/usr/bin/ssh-keygen",
            arguments: ["-y", "-P", "", "-f", privateKeyPath],
            environment: nil
        )
        guard result.exitCode != 0 else { return false }
        return result.stderr.lowercased().contains("incorrect passphrase")
    }

    /// Prefer the fingerprint stored on the account; fall back to reading the
    /// `.pub` sibling. `nil` when neither is available.
    static func fingerprint(
        for account: Account,
        privateKeyPath: String,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> String? {
        if let stored = account.keyFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines),
           stored.hasPrefix("SHA256:") {
            return stored
        }
        let publicPath = privateKeyPath.hasSuffix(".pub") ? privateKeyPath : privateKeyPath + ".pub"
        guard FileManager.default.fileExists(atPath: publicPath) else { return nil }
        return try? KeygenService.fingerprintSync(ofPublicKeyAt: publicPath, runner: runner)
    }

    // MARK: - Unlock

    /// Load the key into `ssh-agent`, taking the passphrase from the login
    /// keychain (`ssh-add --apple-use-keychain`). Never prompts: askpass is
    /// disabled so a passphrase that is not in the keychain fails fast with a
    /// message instead of hanging a menu-bar app.
    static func unlockWithKeychain(
        privateKeyPath: String,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) async -> Result<Void, UnlockError> {
        await Task.detached(priority: .userInitiated) {
            unlockWithKeychainSync(privateKeyPath: privateKeyPath, runner: runner)
        }.value
    }

    static func unlockWithKeychainSync(
        privateKeyPath: String,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> Result<Void, UnlockError> {
        let path = privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return .failure(.noKeyPath) }
        let expanded = ConfigStore.expand(path)
        guard FileManager.default.fileExists(atPath: expanded) else {
            return .failure(.keyMissing(expanded))
        }

        let result = runner.run(
            executable: "/usr/bin/ssh-add",
            arguments: ["--apple-use-keychain", expanded],
            environment: ["SSH_ASKPASS_REQUIRE": "never"]
        )
        guard result.exitCode == 0 else {
            let detail = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "exit \(result.exitCode)"
            return .failure(.commandFailed(
                command: "ssh-add --apple-use-keychain \(AccountProjector.toTilde(expanded))",
                detail: String(detail.prefix(200))
            ))
        }
        return .success(())
    }

    enum UnlockError: Swift.Error, Equatable, Sendable {
        case noKeyPath
        case keyMissing(String)
        /// `command` is safe to show so the user can finish the unlock in a
        /// terminal, where a passphrase prompt can actually be answered.
        case commandFailed(command: String, detail: String)

        var localizedMessage: String {
            switch self {
            case .noKeyPath:
                return String(localized: "This account has no private key yet.")
            case .keyMissing(let path):
                return String(localized: "No private key at \(path.abbreviatedHomePath())")
            case .commandFailed(let command, let detail):
                return String(localized: "Could not unlock the key: \(detail). Run \(command) in Terminal to type the passphrase.")
            }
        }
    }
}
