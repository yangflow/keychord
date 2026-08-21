import Foundation

struct KeygenResult: Equatable, Sendable {
    let privateKeyPath: String
    let publicKeyPath: String
    let publicKeyContent: String
    /// SHA256 fingerprint from `ssh-keygen -lf` (e.g. `SHA256:…`), if readable.
    let fingerprint: String?
}

enum KeygenService {

    enum KeyType: String, CaseIterable, Identifiable, Sendable {
        case ed25519
        case rsa4096

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .ed25519: return String(localized: "Ed25519")
            case .rsa4096: return String(localized: "RSA 4096-bit")
            }
        }

        fileprivate var sshKeygenArgs: [String] {
            switch self {
            case .ed25519: return ["-t", "ed25519"]
            case .rsa4096: return ["-t", "rsa", "-b", "4096"]
            }
        }
    }

    enum KeygenError: Swift.Error, Equatable, CustomStringConvertible {
        case invalidName(String)
        case fileExists(String)
        case directoryCreateFailed(String)
        case commandFailed(stderr: String)
        case publicKeyUnreadable(String)
        case fingerprintFailed(stderr: String)

        var description: String {
            switch self {
            case .invalidName(let n):
                return String(localized: "Invalid key file name: \(n)")
            case .fileExists(let p):
                return String(localized: "A key file already exists at \(p)")
            case .directoryCreateFailed(let p):
                return String(localized: "Failed to create directory \(p)")
            case .commandFailed(let err):
                return String(localized: "ssh-keygen failed: \(err)")
            case .publicKeyUnreadable(let p):
                return String(localized: "Generated key but could not read \(p)")
            case .fingerprintFailed(let err):
                return String(localized: "ssh-keygen -lf failed: \(err)")
            }
        }
    }

    static func generate(
        type: KeyType,
        name: String,
        comment: String,
        directory: String = "~/.ssh",
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) async throws -> KeygenResult {
        try await Task.detached(priority: .userInitiated) {
            try generateSync(
                type: type,
                name: name,
                comment: comment,
                directory: directory,
                runner: runner
            )
        }.value
    }

    static func generateSync(
        type: KeyType,
        name: String,
        comment: String,
        directory: String,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) throws -> KeygenResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidKeyName(trimmedName) else {
            throw KeygenError.invalidName(name)
        }
        // Strip any CR/LF from the comment so it can't forge extra lines in
        // the generated .pub file.
        let sanitizedComment = comment
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")

        let expandedDir = (directory as NSString).expandingTildeInPath
        let privatePath = (expandedDir as NSString).appendingPathComponent(trimmedName)
        let publicPath = privatePath + ".pub"

        if FileManager.default.fileExists(atPath: privatePath) {
            throw KeygenError.fileExists(privatePath)
        }
        if FileManager.default.fileExists(atPath: publicPath) {
            throw KeygenError.fileExists(publicPath)
        }

        do {
            try FileManager.default.createDirectory(
                atPath: expandedDir,
                withIntermediateDirectories: true
            )
        } catch {
            throw KeygenError.directoryCreateFailed(expandedDir)
        }

        var args = type.sshKeygenArgs
        args += ["-C", sanitizedComment, "-f", privatePath, "-N", ""]
        let result = runner.run(
            executable: "/usr/bin/ssh-keygen",
            arguments: args,
            environment: nil
        )

        if result.exitCode != 0 {
            throw KeygenError.commandFailed(
                stderr: result.stderr.isEmpty ? "exit \(result.exitCode)" : result.stderr
            )
        }

        guard let publicContent = try? String(contentsOfFile: publicPath, encoding: .utf8) else {
            throw KeygenError.publicKeyUnreadable(publicPath)
        }

        // Fingerprint is best-effort: key material is already on disk even
        // if -lf fails (rare). Callers can still attach via keyPath alone.
        let fingerprint = try? fingerprintSync(ofPublicKeyAt: publicPath, runner: runner)

        return KeygenResult(
            privateKeyPath: privatePath,
            publicKeyPath: publicPath,
            publicKeyContent: publicContent.trimmingCharacters(in: .whitespacesAndNewlines),
            fingerprint: fingerprint
        )
    }

    /// Read the SHA256 fingerprint of a public key file via `ssh-keygen -lf`.
    static func fingerprintSync(
        ofPublicKeyAt path: String,
        runner: any ProcessRunner = SystemProcessRunner.shared
    ) throws -> String {
        let result = runner.run(
            executable: "/usr/bin/ssh-keygen",
            arguments: ["-lf", path, "-E", "sha256"],
            environment: nil
        )
        if result.exitCode != 0 {
            throw KeygenError.fingerprintFailed(
                stderr: result.stderr.isEmpty ? "exit \(result.exitCode)" : result.stderr
            )
        }
        guard let parsed = parseFingerprint(from: result.stdout) else {
            throw KeygenError.fingerprintFailed(stderr: "unrecognized output: \(result.stdout)")
        }
        return parsed
    }

    /// Extract `SHA256:…` from `ssh-keygen -lf` stdout
    /// (`256 SHA256:abc… comment (ED25519)`).
    static func parseFingerprint(from stdout: String) -> String? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for token in trimmed.split(whereSeparator: { $0.isWhitespace }) {
            let s = String(token)
            if s.hasPrefix("SHA256:") || s.hasPrefix("MD5:") {
                return s
            }
        }
        return nil
    }

    /// Accept `A-Z a-z 0-9 . _ -`, reject `..`, leading dot, empty,
    /// control characters, and anything that might escape the target dir.
    static func isValidKeyName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix(".") else { return false }
        if name.contains("..") { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return name.allSatisfy { allowed.contains($0) }
    }
}
