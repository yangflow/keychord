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
final class ActivationPolicyController: NSObject {
    static let shared = ActivationPolicyController()

    private var didStart = false
    private var restoreTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        // Selector-based observer: the block-based API is @Sendable and cannot
        // capture `self` under Swift 6 for this MainActor type.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    /// Pure check used by the restore path and unit tests. `nonisolated`
    /// because it only reads a Sendable snapshot — no window, no main actor.
    nonisolated static func shouldRestoreAccessory(windows: [TitledWindowPresence]) -> Bool {
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

    /// NotificationCenter may invoke this off the main actor; hop back without
    /// sending a non-Sendable `NSWindow` across isolation (use its identity).
    @objc nonisolated private func windowWillClose(_ notification: Notification) {
        let excludingID = (notification.object as AnyObject?).map { ObjectIdentifier($0) }
        Task { @MainActor in
            ActivationPolicyController.shared.scheduleRestoreAccessory(excludingID: excludingID)
        }
    }

    private func scheduleRestoreAccessory(excludingID: ObjectIdentifier?) {
        restoreTask?.cancel()
        restoreTask = Task { @MainActor in
            // willClose fires before the window leaves the list / clears isVisible.
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            restoreAccessoryIfNeeded(excludingID: excludingID)
        }
    }

    func restoreAccessoryIfNeeded(excluding closing: NSWindow? = nil) {
        restoreAccessoryIfNeeded(excludingID: closing.map { ObjectIdentifier($0) })
    }

    private func restoreAccessoryIfNeeded(excludingID: ObjectIdentifier?) {
        let hasTitledVisible = NSApp.windows.contains { window in
            if let excludingID, ObjectIdentifier(window) == excludingID {
                return false
            }
            return window.styleMask.contains(.titled) && window.isVisible
        }
        guard !hasTitledVisible else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
