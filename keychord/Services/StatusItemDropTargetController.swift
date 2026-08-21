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
        // Let the drag session finish before mimicking a status-item click.
        try? await Task.sleep(for: .milliseconds(50))
        openPopoverShowingMatch()
    }

    /// Opens the MenuBarExtra window if it is not already presented.
    func openPopoverShowingMatch() {
        ensureInstalled()
        guard let item = MenuBarStatusItemLocator.keychordStatusItem(),
              let button = item.button else {
            return
        }
        // Already open — AppState.accountMatch update is enough.
        if button.state == .on {
            return
        }
        button.performClick(nil)
    }
}
