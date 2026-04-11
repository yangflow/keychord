import Foundation
@testable import keychord

/// In-memory ProcessRunner that records every invocation and returns
/// a canned ProcessResult. Use in tests where a real subprocess would
/// be slow or unavailable.
final class MockProcessRunner: ProcessRunner, @unchecked Sendable {
    struct Invocation: Equatable {
        let executable: String
        let arguments: [String]
        let environment: [String: String]?
    }

    private let lock = NSLock()
    private var _invocations: [Invocation] = []
    private var _result: ProcessResult

    init(result: ProcessResult = ProcessResult(exitCode: 0, stdout: "", stderr: "")) {
        self._result = result
    }

    var invocations: [Invocation] {
        lock.lock(); defer { lock.unlock() }
        return _invocations
    }

    func setResult(_ result: ProcessResult) {
        lock.lock(); defer { lock.unlock() }
        _result = result
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?
    ) -> ProcessResult {
        lock.lock(); defer { lock.unlock() }
        _invocations.append(Invocation(
            executable: executable,
            arguments: arguments,
            environment: environment
        ))
        return _result
    }
}
