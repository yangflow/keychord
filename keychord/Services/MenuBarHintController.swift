import AppKit

/// First-launch onboarding for a menubar-only app: glow the status item and hang
/// a small callout under it so the first run can find the icon. Shown once —
/// the flag is written the moment it appears, so a second launch is quiet.
///
/// Deliberately not a window: nothing to close, nothing to accept. It goes away
/// on the next click or by itself.
@MainActor
final class MenuBarHintController {
    static let shared = MenuBarHintController()

    private let defaults: UserDefaults
    private var hasStarted = false
    private var panel: NSPanel?
    private var glow: StatusItemHintGlowView?
    private var monitors: [Any] = []
    private var dismissTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Safe to call on every `onAppear`: it runs at most once per process, and
    /// only when the hint has never been shown.
    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        guard FirstLaunchHint.shouldShow(defaults: defaults) else { return }
        Task { await present() }
    }

    private func present() async {
        guard let button = await waitForStatusItemButton() else { return }
        // Written on appearance rather than on dismissal: quitting while the
        // callout is up still counts as having been pointed at the icon.
        FirstLaunchHint.markShown(defaults: defaults)

        showGlow(on: button)
        showCallout(anchoredTo: button)
        installDismissMonitors()

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(FirstLaunchHint.autoDismissAfter))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// `MenuBarExtra` creates the status item shortly after launch.
    private func waitForStatusItemButton() async -> NSStatusBarButton? {
        for _ in 0..<FirstLaunchHint.statusItemWaitAttempts {
            if let button = MenuBarStatusItemLocator.keychordStatusItem()?.button {
                return button
            }
            try? await Task.sleep(for: .seconds(FirstLaunchHint.statusItemWaitInterval))
        }
        return nil
    }

    // MARK: - Chrome

    private func showGlow(on button: NSStatusBarButton) {
        glow?.removeFromSuperview()
        let view = StatusItemHintGlowView(frame: button.bounds)
        view.autoresizingMask = [.width, .height]
        button.addSubview(view)
        view.startPulsing(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        glow = view
    }

    private func showCallout(anchoredTo button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        // visibleFrame, so the callout hangs below the menu bar rather than
        // under it, and stays clear of the Dock.
        let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? anchor
        let content = MenuBarHintCalloutView { [weak self] in self?.dismiss() }
        let frame = FirstLaunchHint.calloutFrame(
            anchor: anchor,
            size: content.fittingSize,
            screen: screenFrame
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = content
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.setFrame(frame, display: false)
        // Never steals focus: the app is an accessory and stays that way.
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Any click dismisses. Global monitors do not see our own app's events, so
    /// clicking the status item itself needs the local one.
    private func installDismissMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in
            Task { @MainActor [weak self] in self?.dismiss() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            Task { @MainActor [weak self] in self?.dismiss() }
            return event
        }) {
            monitors.append(local)
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        glow?.stopPulsing()
        glow?.removeFromSuperview()
        glow = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Contents of the callout: a title line and one line of what the icon is for.
/// Clicking it counts as “got it”.
private final class MenuBarHintCalloutView: NSVisualEffectView {
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)

        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        let title = NSTextField(labelWithString: String.loc("KeyChord is up here"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let subtitle = NSTextField(
            labelWithString: String.loc("Click the icon to manage Git identities")
        )
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])

        setAccessibilityRole(.popover)
        setAccessibilityLabel("\(title.stringValue). \(subtitle.stringValue)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}
