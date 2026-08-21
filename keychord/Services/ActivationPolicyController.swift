import AppKit

/// Snapshot of the bits ActivationPolicy cares about — keeps the decision
/// testable without spinning up a full window hierarchy.
struct TitledWindowPresence: Equatable, Sendable {
    var isTitled: Bool
    var isVisible: Bool
    /// True for the window currently posting `willClose` (still in `NSApp.windows`).
    var isClosing: Bool
}

/// Keeps KeyChord as a menubar accessory (no Dock icon) whenever the last
/// titled window closes. About, Accounts, Sparkle update UI, and any other
/// AppKit window all share this single listener — callers still switch to
/// `.regular` when opening a window; this only restores `.accessory`.
///
/// Does **not** quit the process. `LSUIElement` stays YES.
@MainActor
final class ActivationPolicyController {
    static let shared = ActivationPolicyController()

    private var observer: NSObjectProtocol?
    private var restoreTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let closing = notification.object as? NSWindow
            Task { @MainActor in
                self?.scheduleRestoreAccessory(excluding: closing)
            }
        }
    }

    /// Pure check used by the restore path and unit tests.
    static func shouldRestoreAccessory(windows: [TitledWindowPresence]) -> Bool {
        !windows.contains { !$0.isClosing && $0.isTitled && $0.isVisible }
    }

    static func hasTitledVisibleWindow(
        in windows: [NSWindow],
        excluding closing: NSWindow? = nil
    ) -> Bool {
        !shouldRestoreAccessory(
            windows: windows.map { window in
                TitledWindowPresence(
                    isTitled: window.styleMask.contains(.titled),
                    isVisible: window.isVisible,
                    isClosing: window === closing
                )
            }
        )
    }

    private func scheduleRestoreAccessory(excluding closing: NSWindow?) {
        restoreTask?.cancel()
        restoreTask = Task { @MainActor in
            // willClose fires before the window leaves the list / clears isVisible.
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            restoreAccessoryIfNeeded(excluding: closing)
        }
    }

    func restoreAccessoryIfNeeded(excluding closing: NSWindow? = nil) {
        guard !Self.hasTitledVisibleWindow(in: NSApp.windows, excluding: closing) else {
            return
        }
        NSApp.setActivationPolicy(.accessory)
    }
}
