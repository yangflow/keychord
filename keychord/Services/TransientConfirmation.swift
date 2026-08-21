import Foundation
import Observation

/// One-second “done” acknowledgement for actions that otherwise leave no trace:
/// a copy that reaches the clipboard, a save that reaches disk. Reverts itself
/// so a checkmark can never imply something that happened minutes ago.
///
/// Views hold this in `@State` and read ``isShowing``; the timer is a
/// cancellable Task, so back-to-back actions restart the window instead of
/// stacking timers.
@MainActor
@Observable
final class TransientConfirmation {
    /// `nonisolated` so the `init` default argument below — a nonisolated
    /// expression by rule — can read it, same as `ProbeCache.defaultTTL`.
    nonisolated static let defaultDuration: Duration = .milliseconds(1200)

    private(set) var isShowing = false

    private let duration: Duration
    private var task: Task<Void, Never>?

    init(duration: Duration = TransientConfirmation.defaultDuration) {
        self.duration = duration
    }

    func flash() {
        isShowing = true
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.duration)
            guard !Task.isCancelled else { return }
            self.isShowing = false
        }
    }

    /// Drop the acknowledgement immediately — used when the input it referred to
    /// changes, so the checkmark never describes stale text.
    func reset() {
        task?.cancel()
        task = nil
        isShowing = false
    }
}
