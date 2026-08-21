import Foundation

/// Abstracts spawning a child process so Services can be unit-tested with
/// stubbed results instead of requiring real `git`, `ssh`, `ssh-keygen`,
/// `nc`, or `curl` binaries to be installed.
///
/// All Services accept `ProcessRunner` as a default parameter
/// (`SystemProcessRunner.shared`) so existing call sites stay unchanged.
/// Tests can inject a `MockProcessRunner` to assert behaviour deterministically.
protocol ProcessRunner: Sendable {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?
    ) -> ProcessResult
}

struct ProcessResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

// MARK: - Real implementation

struct SystemProcessRunner: ProcessRunner {
    static let shared = SystemProcessRunner()

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?
    ) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let environment {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in environment { merged[k] = v }
            process.environment = merged
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // None of the tools we spawn need input, and a menu-bar app has no
        // terminal to answer a prompt on: `ssh-add` asking for a passphrase
        // must fail fast instead of hanging `waitUntilExit()`.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ProcessResult(
                exitCode: -1,
                stdout: "",
                stderr: "launch failed: \(error.localizedDescription)"
            )
        }
        process.waitUntilExit()

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}
