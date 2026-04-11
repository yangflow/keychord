import Foundation

enum HostProbeState: Equatable, Sendable {
    case idle
    case probing
    case ok(username: String)
    case failed(reason: String)
}

enum Prober {

    // MARK: - Async API

    /// Probe an SSH alias by running `ssh -T -o BatchMode=yes git@<alias>`.
    /// Uses the user's own SSH config for everything (HostName, Port, IdentityFile),
    /// so this tests exactly what git would do.
    static func probeAlias(
        _ alias: String,
        timeoutSec: Int = 5,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) async -> HostProbeState {
        await Task.detached(priority: .userInitiated) {
            probeAliasSync(alias, timeoutSec: timeoutSec, runner: runner)
        }.value
    }

    /// Check whether a TCP port on a host is reachable, via `nc -z -G`.
    static func checkPort(
        host: String,
        port: Int,
        timeoutSec: Int = 3,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            checkPortSync(host: host, port: port, timeoutSec: timeoutSec, runner: runner)
        }.value
    }

    // MARK: - Sync impl (runs inside Task.detached)

    static func probeAliasSync(
        _ alias: String,
        timeoutSec: Int,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> HostProbeState {
        let result = runner.run(
            executable: "/usr/bin/ssh",
            arguments: [
                "-T",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=\(timeoutSec)",
                "git@\(alias)"
            ],
            environment: nil
        )
        // GitHub's greeting goes to stderr even on success exit 1, so the
        // parser reads stderr not stdout.
        return parseProbeOutput(result.stderr)
    }

    static func checkPortSync(
        host: String,
        port: Int,
        timeoutSec: Int,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) -> Bool {
        let result = runner.run(
            executable: "/usr/bin/nc",
            arguments: ["-z", "-G", String(timeoutSec), host, String(port)],
            environment: nil
        )
        return result.exitCode == 0
    }

    // MARK: - Output parser (internal for tests)

    static func parseProbeOutput(_ output: String) -> HostProbeState {
        // GitHub replies "Hi <user>! You've successfully authenticated..." on stderr
        // even though the session exits 1 (no shell access). The captured user
        // name is displayed in the UI, so we whitelist it to valid GitHub
        // username characters to keep a crafted remote from injecting weird
        // glyphs or mock error text.
        let pattern = #"Hi\s+([^!\s]+)!"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            if let match = regex.firstMatch(in: output, range: range),
               match.numberOfRanges >= 2,
               let userRange = Range(match.range(at: 1), in: output) {
                let raw = String(output[userRange])
                if isValidGitHubUsername(raw) {
                    return .ok(username: raw)
                }
            }
        }

        let lower = output.lowercased()
        if lower.contains("permission denied") {
            return .failed(reason: "permission denied (publickey)")
        }
        if lower.contains("could not resolve hostname") {
            return .failed(reason: "host unreachable")
        }
        if lower.contains("connection refused") {
            return .failed(reason: "connection refused")
        }
        if lower.contains("connection timed out") || lower.contains("operation timed out") {
            return .failed(reason: "timed out")
        }
        if lower.contains("host key verification failed") {
            return .failed(reason: "host key mismatch")
        }
        if lower.contains("no such identity") || lower.contains("no such file") {
            return .failed(reason: "key file missing")
        }

        let firstLine = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "unknown error"
        return .failed(reason: String(firstLine.prefix(80)))
    }

    /// GitHub usernames are alphanumeric or hyphen, 1–39 chars, and may not
    /// begin or end with a hyphen. We enforce a superset of that for the
    /// parsed probe greeting so a malicious `Hi *!` banner is rejected.
    static func isValidGitHubUsername(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 39 else { return false }
        if s.hasPrefix("-") || s.hasSuffix("-") { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
        return s.allSatisfy { allowed.contains($0) }
    }
}
