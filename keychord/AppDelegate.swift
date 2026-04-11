import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var accountsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPopover()
        setupStatusItem()
        observeState()
        installOutsideClickMonitor()
    }

    deinit {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        refreshButtonImage(severity: appState.highestSeverity)
        button.imagePosition = .imageOnly

        let dragView = DragTargetView(frame: button.bounds)
        dragView.autoresizingMask = [.width, .height]
        dragView.onClick = { [weak self] in
            self?.togglePopover()
        }
        dragView.onDrop = { [weak self] url in
            self?.handleDroppedURL(url)
        }
        button.addSubview(dragView)
    }

    private func refreshButtonImage(severity: Diagnosis.Severity?) {
        guard let button = statusItem?.button else { return }
        let symbolName: String
        switch severity {
        case .error:
            symbolName = "exclamationmark.octagon.fill"
        case .warning:
            symbolName = "exclamationmark.triangle.fill"
        case .info, .none:
            symbolName = "key.horizontal.fill"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "keychord"
        )?.withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(
            width: KC.popoverWidth,
            height: KC.popoverHeight
        )

        let rootView = MenuBarContent(
            appState: appState,
            onOpenAccountsWindow: { [weak self] in
                self?.showAccountsWindow()
            },
            onOpenAccount: { [weak self] id in
                self?.showAccountsWindow(selecting: id)
            },
            onOpenAbout: { [weak self] in
                self?.showAboutWindow()
            }
        )
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    // MARK: - Accounts window

    func showAccountsWindow(selecting accountID: UUID? = nil) {
        if let accountID {
            appState.pendingAccountSelection = accountID
        }

        if let existing = accountsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = AccountsWindowView(appState: appState)
        let hostingController = NSHostingController(rootView: root)
        hostingController.preferredContentSize = NSSize(width: 760, height: 520)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "keychord · Accounts"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 420)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        accountsWindow = window
    }

    // MARK: - About window

    private func showAboutWindow() {
        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = AboutView(onDismiss: { [weak self] in
            self?.aboutWindow?.close()
        })
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "About keychord"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow = window
    }

    /// Install a global event monitor that closes the popover whenever the
    /// user clicks somewhere outside our app. `.transient` NSPopover
    /// behavior alone is unreliable once a SwiftUI Menu has been opened
    /// inside the popover — the built-in event monitor gets detached.
    private func installOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        popover.contentViewController?.view.window?.makeKey()
    }

    private func handleDroppedURL(_ url: URL) {
        appState.droppedPath = url.path
        showPopover()
    }

    // MARK: - Observation

    private func observeState() {
        appState.$highestSeverity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] severity in
                self?.refreshButtonImage(severity: severity)
            }
            .store(in: &cancellables)
    }
}
