import AppKit

/// Locates the `MenuBarExtra` status item without adding a second item or a
/// third-party package. Uses the same window introspection pattern as
/// MenuBarExtraAccess (MIT): `NSStatusBarWindow` → KVC `statusItem`.
enum MenuBarStatusItemLocator {
    /// Class name of the real (non-replica) status item for this OS.
    static var statusItemClassName: String {
        if #available(macOS 26.0, *) {
            "NSSceneStatusItem"
        } else {
            "NSStatusItem"
        }
    }

    /// Approximate width of ``MenuBarPopoverView`` (`KC.popoverWidth`).
    static let popoverContentWidth: CGFloat = 340

    @MainActor
    static func statusItems() -> [NSStatusItem] {
        NSApp.windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .compactMap { window -> NSStatusItem? in
                guard let statusItem = window.fetchStatusItem(),
                      statusItem.className == statusItemClassName
                else { return nil }
                return statusItem
            }
    }

    /// Keychord has a single `MenuBarExtra`.
    @MainActor
    static func keychordStatusItem() -> NSStatusItem? {
        statusItems().first
    }

    /// The MenuBarExtra *content* window (popover), not the status-item chrome.
    /// Prefer `MenuBarExtraWindow`; fall back to a visible ~popover-width window.
    @MainActor
    static func contentWindow() -> NSWindow? {
        let visible = NSApp.windows.filter(\.isVisible)
        if let named = visible.first(where: { $0.className.contains("MenuBarExtraWindow") }) {
            return named
        }
        return visible.first { window in
            if window.className.contains("NSStatusBarWindow") { return false }
            let width = window.frame.width
            return abs(width - popoverContentWidth) < 48
        }
    }
}

extension NSWindow {
    /// When called on an `NSStatusBarWindow`, returns the associated status item.
    fileprivate func fetchStatusItem() -> NSStatusItem? {
        value(forKey: "statusItem") as? NSStatusItem
            ?? Mirror(reflecting: self).descendant("statusItem") as? NSStatusItem
    }
}

// MARK: - Pin MenuBarExtra content while an open-panel sheet is up

/// Keeps the MenuBarExtra content window from auto-dismissing when an
/// `NSOpenPanel` sheet steals key focus (resign-key / click-away).
@MainActor
final class MenuBarExtraWindowPin {
    private weak var window: NSWindow?
    private var previousHidesOnDeactivate: Bool?
    private var previousIsFloatingPanel: Bool?
    private weak var previousDelegate: NSWindowDelegate?
    private var pinDelegate: MenuBarExtraPinWindowDelegate?

    func pin(_ window: NSWindow) {
        unpin()
        self.window = window
        previousHidesOnDeactivate = window.hidesOnDeactivate
        window.hidesOnDeactivate = false

        if let panel = window as? NSPanel {
            previousIsFloatingPanel = panel.isFloatingPanel
            panel.isFloatingPanel = true
        }

        previousDelegate = window.delegate
        let delegate = MenuBarExtraPinWindowDelegate(forwardingTo: window.delegate)
        pinDelegate = delegate
        window.delegate = delegate
    }

    func unpin() {
        guard let window else {
            clearLocals()
            return
        }
        if let previousHidesOnDeactivate {
            window.hidesOnDeactivate = previousHidesOnDeactivate
        }
        if let panel = window as? NSPanel, let previousIsFloatingPanel {
            panel.isFloatingPanel = previousIsFloatingPanel
        }
        if window.delegate === pinDelegate {
            window.delegate = previousDelegate
        }
        clearLocals()
    }

    private func clearLocals() {
        window = nil
        previousHidesOnDeactivate = nil
        previousIsFloatingPanel = nil
        previousDelegate = nil
        pinDelegate = nil
    }
}

/// Forwards to the previous delegate while refusing close and re-fronting on resign-key.
private final class MenuBarExtraPinWindowDelegate: NSObject, NSWindowDelegate {
    private weak var forward: NSWindowDelegate?

    init(forwardingTo forward: NSWindowDelegate?) {
        self.forward = forward
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        false
    }

    func windowDidResignKey(_ notification: Notification) {
        // Keep the extra visible under the sheet without stealing key from it.
        if let window = notification.object as? NSWindow {
            window.orderFront(nil)
        }
        forward?.windowDidResignKey?(notification)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        forward?.windowDidBecomeKey?(notification)
    }

    func windowWillClose(_ notification: Notification) {
        forward?.windowWillClose?(notification)
    }

    func windowDidResignMain(_ notification: Notification) {
        forward?.windowDidResignMain?(notification)
    }
}
