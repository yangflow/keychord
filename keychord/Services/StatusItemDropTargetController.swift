import AppKit

/// Installs a folder drag destination on the existing MenuBarExtra status-item
/// button (no second status item). Forwards drops into ``AppState`` and opens
/// the popover so the match is visible.
@MainActor
final class StatusItemDropTargetController {
    static let shared = StatusItemDropTargetController()

    private weak var appState: AppState?
    private var dropView: StatusItemFolderDropView?
    private weak var installedButton: NSStatusBarButton?
    private var pollTask: Task<Void, Never>?

    private init() {}

    func start(appState: AppState) {
        self.appState = appState
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            // MenuBarExtra creates the status item shortly after launch; keep
            // re-checking in case SwiftUI recreates the button when the label changes.
            for _ in 0..<30 {
                guard !Task.isCancelled else { return }
                ensureInstalled()
                if installedButton != nil { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            while !Task.isCancelled {
                ensureInstalled()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func ensureInstalled() {
        guard let button = MenuBarStatusItemLocator.keychordStatusItem()?.button else {
            return
        }
        // SwiftUI can recreate the button; the tooltip lives on the button, so
        // reapply it here as well as when the match changes.
        button.toolTip = MenuBarTooltip.text(for: appState?.accountMatch)
        if installedButton === button, dropView?.superview === button {
            return
        }

        dropView?.removeFromSuperview()
        let view = StatusItemFolderDropView(frame: button.bounds)
        view.autoresizingMask = [.width, .height]
        view.onFolderURLs = { [weak self] urls in
            Task { @MainActor in
                await self?.handleDroppedFolders(urls)
            }
        }
        button.addSubview(view)
        dropView = view
        installedButton = button
    }

    private func handleDroppedFolders(_ urls: [URL]) async {
        guard let appState, let path = urls.first?.path else { return }

        await appState.resolveCurrentRepo(at: path)

        // Let the drag session finish before mimicking a status-item click. The
        // match now outlives the popover, so nothing has to be restored here.
        // Finder's drag can still own the click stream at 150ms on a cold launch.
        try? await Task.sleep(for: .milliseconds(280))
        await openPopoverShowingMatch()
    }

    /// Closes the MenuBarExtra window if it is showing, by toggling the status
    /// item the same way a click outside would. No-op when already closed.
    func closePopover() {
        guard let button = MenuBarStatusItemLocator.keychordStatusItem()?.button,
              button.state == .on else {
            return
        }
        button.performClick(nil)
    }

    /// Opens the MenuBarExtra window if it is not already presented.
    /// Does not click when already open — that would toggle closed and clear
    /// the match card.
    ///
    /// `performClick` often no-ops on a never-opened `MenuBarExtra` (the window
    /// scene is created on the first real click). Lift our drop overlay, dismiss
    /// the first-launch hint, and send a mouseDown/Up through the button so a
    /// cold-launch drop still presents.
    func openPopoverShowingMatch() async {
        MenuBarHintController.shared.dismiss()
        ensureInstalled()
        guard let button = MenuBarStatusItemLocator.keychordStatusItem()?.button else {
            return
        }
        if button.state == .on {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        presentStatusItem(button)
        if button.state == .on { return }

        try? await Task.sleep(for: .milliseconds(120))
        guard let retry = MenuBarStatusItemLocator.keychordStatusItem()?.button,
              retry.state != .on else { return }
        presentStatusItem(retry)
    }

    /// Click the real status-item button, not the drop overlay sitting on top.
    /// Overlay is reinstalled immediately after so the next drag still lands.
    private func presentStatusItem(_ button: NSStatusBarButton) {
        let overlay = dropView
        overlay?.removeFromSuperview()
        defer { ensureInstalled() }

        button.performClick(nil)
        if button.state == .on { return }

        sendSyntheticClick(to: button)
    }

    private func sendSyntheticClick(to button: NSStatusBarButton) {
        guard let window = button.window else {
            button.performClick(nil)
            return
        }
        let locationInWindow = button.convert(
            NSPoint(x: button.bounds.midX, y: button.bounds.midY),
            to: nil
        )
        func mouseEvent(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type,
                location: locationInWindow,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        }
        if let down = mouseEvent(.leftMouseDown) {
            button.mouseDown(with: down)
            window.sendEvent(down)
        }
        if let up = mouseEvent(.leftMouseUp) {
            button.mouseUp(with: up)
            window.sendEvent(up)
        }
    }
}
