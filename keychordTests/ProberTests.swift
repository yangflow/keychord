import Testing
import Foundation
@testable import keychord

@Suite("Prober.parseProbeOutput")
struct ProberTests {

    @Test func parsesGithubSuccessGreeting() {
        let output = "Hi yangflow! You've successfully authenticated, but GitHub does not provide shell access.\n"
        let state = Prober.parseProbeOutput(output)
        #expect(state == .ok(username: "yangflow"))
    }

    @Test func parsesGithubSuccessWithHyphenUsername() {
        let output = "Hi bob! You've successfully authenticated, but GitHub does not provide shell access.\n"
        let state = Prober.parseProbeOutput(output)
        #expect(state == .ok(username: "bob"))
    }

    @Test func rejectsGarbageUsernameAsFailure() {
        // Crafted banner with invalid chars — should not be treated as success
        let output = "Hi evil$user! You've successfully authenticated\n"
        let state = Prober.parseProbeOutput(output)
        if case .ok = state {
            Issue.record("Expected .failed for garbage username, got \(state)")
        }
    }

    @Test func rejectsTooLongUsernameAsFailure() {
        let tooLong = String(repeating: "a", count: 40)
        let output = "Hi \(tooLong)!\n"
        let state = Prober.parseProbeOutput(output)
        if case .ok = state {
            Issue.record("Expected .failed for >39-char username, got \(state)")
        }
    }

    // MARK: - Injected runner

    @Test func probeAliasSyncWiresUpSSHCommand() {
        let mock = MockProcessRunner(result: ProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "Hi yangflow! You've successfully authenticated\n"
        ))
        let state = Prober.probeAliasSync(
            "github.com",
            timeoutSec: 5,
            runner: mock
        )
        #expect(state == .ok(username: "yangflow"))
        #expect(mock.invocations.count == 1)
        let inv = mock.invocations[0]
        #expect(inv.executable == "/usr/bin/ssh")
        #expect(inv.arguments.contains("-T"))
        #expect(inv.arguments.contains("BatchMode=yes"))
        #expect(inv.arguments.contains("git@github.com"))
    }

    @Test func checkPortSyncMapsExitCode() {
        let ok = MockProcessRunner(result: ProcessResult(exitCode: 0, stdout: "", stderr: ""))
        let bad = MockProcessRunner(result: ProcessResult(exitCode: 1, stdout: "", stderr: "refused"))
        #expect(Prober.checkPortSync(host: "github.com", port: 22, timeoutSec: 3, runner: ok))
        #expect(!Prober.checkPortSync(host: "github.com", port: 22, timeoutSec: 3, runner: bad))
    }

    @Test func isValidGitHubUsernameBoundaries() {
        #expect(Prober.isValidGitHubUsername("yangflow"))
        #expect(Prober.isValidGitHubUsername("bob"))
        #expect(Prober.isValidGitHubUsername("a"))
        #expect(!Prober.isValidGitHubUsername(""))
        #expect(!Prober.isValidGitHubUsername("-leading"))
        #expect(!Prober.isValidGitHubUsername("trailing-"))
        #expect(!Prober.isValidGitHubUsername("with space"))
        #expect(!Prober.isValidGitHubUsername("with.dot"))
        #expect(!Prober.isValidGitHubUsername(String(repeating: "x", count: 40)))
    }

    @Test func parsesPermissionDenied() {
        let output = "git@github.com: Permission denied (publickey).\n"
        let state = Prober.parseProbeOutput(output)
        #expect(state == .failed(reason: "permission denied (publickey)"))
    }

    @Test func parsesHostUnreachable() {
        let output = "ssh: Could not resolve hostname github-nope: nodename nor servname provided\n"
        let state = Prober.parseProbeOutput(output)
        #expect(state == .failed(reason: "host unreachable"))
    }

    @Test func parsesConnectionRefused() {
        let output = "ssh: connect to host ssh.github.com port 443: Connection refused\n"
        let state = Prober.parseProbeOutput(output)
        #expect(state == .failed(reason: "connection refused"))
    }

    @Test func parsesTimeout() {
        let output = "ssh: connect to host ssh.github.com port 443: Operation timed out\n"
        let state = Prober.parseProbeOutput(output)
        #expect(state == .failed(reason: "timed out"))
    }

    @Test func parsesHostKeyMismatch() {
        let output = """
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        Host key verification failed.
        """
        let state = Prober.parseProbeOutput(output)
        #expect(state == .failed(reason: "host key mismatch"))
    }

    @Test func parsesMissingKeyFile() {
        let output = "Warning: Identity file /Users/u/.ssh/id_missing not accessible: No such file or directory.\n"
        let state = Prober.parseProbeOutput(output)
        #expect(state == .failed(reason: "key file missing"))
    }

    @Test func emptyOutputFailsGracefully() {
        let state = Prober.parseProbeOutput("")
        if case .failed = state {} else {
            Issue.record("Expected .failed for empty output, got \(state)")
        }
    }

    @Test func unknownErrorReturnsFirstLineTruncated() {
        let output = "ssh: some unusual error message that is quite long and should get truncated at eighty characters which this one definitely exceeds\nline 2\n"
        let state = Prober.parseProbeOutput(output)
        if case .failed(let reason) = state {
            #expect(reason.count <= 80)
            #expect(reason.contains("unusual error"))
        } else {
            Issue.record("Expected .failed, got \(state)")
        }
    }
}
