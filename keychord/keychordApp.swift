import SwiftUI
import AppKit

@main
struct KeychordApp: App {
    @State private var appState = AppState()

    init() {
        NSApp?.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(appState)
        } label: {
            MenuBarIconLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("KeyChord · Accounts", id: "accounts") {
            AccountsWindowView()
                .environment(appState)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        let hasVisibleWindow = NSApp.windows.contains {
                            $0.styleMask.contains(.titled) && $0.isVisible
                        }
                        if !hasVisibleWindow {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 520)

        Window("About keychord", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
