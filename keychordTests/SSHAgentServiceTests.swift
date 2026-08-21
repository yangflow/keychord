import Testing
import Foundation
@testable import keychord

@Suite("SSHAgentService")
struct SSHAgentServiceTests {

    static func account(keyPath: String, fingerprint: String? = nil) -> Account {
        var account = Account.new(
            label: "work",
            sshAlias: "github-work",
            keyPath: keyPath,
            gitUserName: "Work",
            gitUserEmail: "work@company.com"
        )
        account.keyFingerprint = fingerprint
        return account
    }

    /// `Result<Void, _>` is not Equatable (Void is not), so unwrap by hand.
    static func unlockError(
        _ result: Result<Void, SSHAgentService.UnlockError>
    ) -> SSHAgentService.UnlockError? {
        guard case .failure(let error) = result else { return nil }
        return error
    }

    static func isSuccess(_ result: Result<Void, SSHAgentService.UnlockError>) -> Bool {
        if case .success = result { return true }
        return false
    }

    static func withTempDir(_ test: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try test(dir)
    }

    // MARK: - ssh-add -l parsing

    @Test func parsesAgentFingerprints() {
        let stdout = """
        256 SHA256:AAAAfirst work@company.com (ED25519)
        3072 SHA256:BBBBsecond me@example.com (RSA)
        """
        let parsed = SSHAgentService.parseFingerprints(stdout)
        #expect(parsed == ["SHA256:AAAAfirst", "SHA256:BBBBsecond"])
    }

    @Test func emptyAgentListingParsesToNothing() {
        #expect(SSHAgentService.parseFingerprints("The agent has no identities.").isEmpty)
        #expect(SSHAgentService.parseFingerprints("").isEmpty)
    }

    @Test func agentWithIdentitiesIsReachable() {
        let runner = MockProcessRunner(result: ProcessResult(
            exitCode: 0,
            stdout: "256 SHA256:AAAA work@company.com (ED25519)\n",
            stderr: ""
        ))
        let result = SSHAgentService.loadedFingerprintsSync(runner: runner)
        #expect(result.reachable)
        #expect(result.fingerprints == ["SHA256:AAAA"])
        #expect(runner.invocations.first?.executable == "/usr/bin/ssh-add")
        #expect(runner.invocations.first?.arguments == ["-l", "-E", "sha256"])
    }

    @Test func emptyAgentIsStillReachable() {
        let runner = MockProcessRunner(result: ProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "The agent has no identities."
        ))
        let result = SSHAgentService.loadedFingerprintsSync(runner: runner)
        #expect(result.reachable)
        #expect(result.fingerprints.isEmpty)
    }

    @Test func missingAgentIsNotReachable() {
        let runner = MockProcessRunner(result: ProcessResult(
            exitCode: 2,
            stdout: "",
            stderr: "Error connecting to agent: No such file or directory"
        ))
        let result = SSHAgentService.loadedFingerprintsSync(runner: runner)
        #expect(!result.reachable)
        #expect(result.fingerprints.isEmpty)
    }

    // MARK: - Passphrase detection

    @Test func unprotectedKeyIsNotEncrypted() {
        let runner = MockProcessRunner(result: ProcessResult(
            exitCode: 0,
            stdout: "ssh-ed25519 AAAAPublicOnly\n",
            stderr: ""
        ))
        #expect(!SSHAgentService.isEncryptedSync(privateKeyPath: "/tmp/id", runner: runner))
        #expect(runner.invocations.first?.arguments == ["-y", "-P", "", "-f", "/tmp/id"])
    }

    @Test func passphraseComplaintMeansEncrypted() {
        let runner = MockProcessRunner(result: ProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "Load key \"/tmp/id\": incorrect passphrase supplied to decrypt private key"
        ))
        #expect(SSHAgentService.isEncryptedSync(privateKeyPath: "/tmp/id", runner: runner))
    }

    @Test func otherKeygenFailuresDoNotMeanEncrypted() {
        let runner = MockProcessRunner(result: ProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "Load key \"/tmp/id\": No such file or directory"
        ))
        #expect(!SSHAgentService.isEncryptedSync(privateKeyPath: "/tmp/id", runner: runner))
    }

    // MARK: - keyState

    @Test func accountWithoutAKeyPathHasUnknownState() {
        let runner = MockProcessRunner()
        let state = SSHAgentService.keyStateSync(
            for: Self.account(keyPath: "  "),
            runner: runner
        )
        #expect(state == .unknown)
        // Nothing to inspect means nothing spawned.
        #expect(runner.invocations.isEmpty)
    }

    @Test func missingKeyFileIsReportedWithoutSpawning() {
        let runner = MockProcessRunner()
        let state = SSHAgentService.keyStateSync(
            for: Self.account(keyPath: "/tmp/keychord-absent-\(UUID().uuidString)"),
            runner: runner
        )
        #expect(state.hasKeyPath)
        #expect(!state.privateKeyExists)
        #expect(!state.agentReachable)
        #expect(runner.invocations.isEmpty)
    }

    @Test func storedFingerprintIsPreferredOverReadingThePubFile() throws {
        try Self.withTempDir { dir in
            let key = dir.appendingPathComponent("id_test")
            try "private".write(to: key, atomically: true, encoding: .utf8)

            let runner = MockProcessRunner()
            let fingerprint = SSHAgentService.fingerprint(
                for: Self.account(keyPath: key.path, fingerprint: "SHA256:STORED"),
                privateKeyPath: key.path,
                runner: runner
            )
            #expect(fingerprint == "SHA256:STORED")
            #expect(runner.invocations.isEmpty)
        }
    }

    @Test func fingerprintFallsBackToThePubSibling() throws {
        try Self.withTempDir { dir in
            let key = dir.appendingPathComponent("id_test")
            try "private".write(to: key, atomically: true, encoding: .utf8)
            try "ssh-ed25519 AAAA you@example.com\n".write(
                to: dir.appendingPathComponent("id_test.pub"),
                atomically: true,
                encoding: .utf8
            )

            let runner = MockProcessRunner(result: ProcessResult(
                exitCode: 0,
                stdout: "256 SHA256:FROMPUB you@example.com (ED25519)\n",
                stderr: ""
            ))
            let fingerprint = SSHAgentService.fingerprint(
                for: Self.account(keyPath: key.path),
                privateKeyPath: key.path,
                runner: runner
            )
            #expect(fingerprint == "SHA256:FROMPUB")
        }
    }

    // MARK: - Unlock

    @Test func unlockRefusesWithoutAKeyPath() {
        let runner = MockProcessRunner()
        let result = SSHAgentService.unlockWithKeychainSync(privateKeyPath: "", runner: runner)
        #expect(Self.unlockError(result) == .noKeyPath)
        #expect(runner.invocations.isEmpty)
    }

    @Test func unlockReportsAMissingKeyFile() {
        let path = "/tmp/keychord-absent-\(UUID().uuidString)"
        let result = SSHAgentService.unlockWithKeychainSync(
            privateKeyPath: path,
            runner: MockProcessRunner()
        )
        #expect(Self.unlockError(result) == .keyMissing(path))
    }

    @Test func unlockUsesTheKeychainAndNeverPrompts() throws {
        try Self.withTempDir { dir in
            let key = dir.appendingPathComponent("id_test")
            try "private".write(to: key, atomically: true, encoding: .utf8)

            let runner = MockProcessRunner(result: ProcessResult(exitCode: 0, stdout: "", stderr: ""))
            let result = SSHAgentService.unlockWithKeychainSync(
                privateKeyPath: key.path,
                runner: runner
            )
            #expect(Self.isSuccess(result))

            let invocation = try #require(runner.invocations.first)
            #expect(invocation.executable == "/usr/bin/ssh-add")
            #expect(invocation.arguments == ["--apple-use-keychain", key.path])
            // Askpass off, so a passphrase we cannot get fails instead of hanging.
            #expect(invocation.environment?["SSH_ASKPASS_REQUIRE"] == "never")
        }
    }

    @Test func unlockFailureSuggestsTheTerminalCommand() throws {
        try Self.withTempDir { dir in
            let key = dir.appendingPathComponent("id_test")
            try "private".write(to: key, atomically: true, encoding: .utf8)

            let runner = MockProcessRunner(result: ProcessResult(
                exitCode: 1,
                stdout: "",
                stderr: "Enter passphrase for /tmp/id: \nssh-add: communication with agent failed"
            ))
            let result = SSHAgentService.unlockWithKeychainSync(
                privateKeyPath: key.path,
                runner: runner
            )
            guard case .failure(let error) = result else {
                Issue.record("Expected failure, got \(result)")
                return
            }
            guard case .commandFailed(let command, let detail) = error else {
                Issue.record("Expected .commandFailed, got \(error)")
                return
            }
            #expect(command.hasPrefix("ssh-add --apple-use-keychain "))
            #expect(detail.contains("communication with agent failed"))
            #expect(error.localizedMessage.contains("ssh-add --apple-use-keychain"))
        }
    }
}
