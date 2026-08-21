import SwiftUI
import AppKit

@main
struct KeychordApp: App {
    @State private var appState = AppState()
    @State private var languageStore = AppLanguageStore()

    init() {
        AppLanguageStore.bootstrapAppleLanguages()
        NSApp?.setActivationPolicy(.accessory)
        ActivationPolicyController.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(appState)
                .environment(languageStore)
                .environment(\.locale, languageStore.locale)
        } label: {
            MenuBarIconLabel(appState: appState)
                .onAppear {
                    StatusItemDropTargetController.shared.start(appState: appState)
                }
        }
        .menuBarExtraStyle(.window)

        WindowGroup("KeyChord · Accounts", id: "accounts") {
            AccountsWindowView()
                .environment(appState)
                .environment(languageStore)
                .environment(\.locale, languageStore.locale)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 520)

        Window("About keychord", id: "about") {
            AboutView()
                .environment(languageStore)
                .environment(\.locale, languageStore.locale)
        }
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
            SettingsWindowView()
                .environment(appState)
                .environment(languageStore)
                .environment(\.locale, languageStore.locale)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 480)
    }
}
