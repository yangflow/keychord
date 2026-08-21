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
}

extension NSWindow {
    /// When called on an `NSStatusBarWindow`, returns the associated status item.
    fileprivate func fetchStatusItem() -> NSStatusItem? {
        value(forKey: "statusItem") as? NSStatusItem
            ?? Mirror(reflecting: self).descendant("statusItem") as? NSStatusItem
    }
}
