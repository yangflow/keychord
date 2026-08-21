import Testing
import Foundation
@testable import keychord

/// #50. Remembering the pane is per app, so a plain `UserDefaults` suite is the
/// whole story.
@Suite("SettingsPaneMemory")
struct SettingsPaneMemoryTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "keychord.tests.settingsPane.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func firstOpenLandsOnGeneral() {
        let defaults = freshDefaults()
        let pane = SettingsPaneMemory.paneOnOpen(pending: nil, defaults: defaults)
        #expect(pane == .general)
        #expect(SettingsPaneMemory.remembered(defaults: defaults) == nil)
    }

    @Test func reopeningRestoresTheLastPane() {
        let defaults = freshDefaults()
        SettingsPaneMemory.remember(.backups, defaults: defaults)

        let remembered = SettingsPaneMemory.remembered(defaults: defaults)
        let pane = SettingsPaneMemory.paneOnOpen(pending: nil, defaults: defaults)
        #expect(remembered == .backups)
        #expect(pane == .backups)
    }

    @Test func laterSelectionsReplaceTheRememberedPane() {
        let defaults = freshDefaults()
        SettingsPaneMemory.remember(.backups, defaults: defaults)
        SettingsPaneMemory.remember(.config, defaults: defaults)

        let pane = SettingsPaneMemory.paneOnOpen(pending: nil, defaults: defaults)
        #expect(pane == .config)
    }

    @Test func aPaneThatNoLongerExistsFallsBackToGeneral() {
        let defaults = freshDefaults()
        defaults.set("retiredPane", forKey: SettingsPaneMemory.paneKey)

        let remembered = SettingsPaneMemory.remembered(defaults: defaults)
        let pane = SettingsPaneMemory.paneOnOpen(pending: nil, defaults: defaults)
        #expect(remembered == nil)
        #expect(pane == .general)
    }

    /// The popover's empty state asks for Import explicitly; that beats whatever
    /// the user was last looking at.
    @Test func aRequestedPaneWinsOverTheRememberedOne() {
        let defaults = freshDefaults()
        SettingsPaneMemory.remember(.backups, defaults: defaults)

        let pane = SettingsPaneMemory.paneOnOpen(
            pending: .importAccounts,
            defaults: defaults
        )
        #expect(pane == .importAccounts)
    }

    @Test func everyPaneRoundTripsThroughDefaults() {
        let defaults = freshDefaults()
        for pane in SettingsPane.allCases {
            SettingsPaneMemory.remember(pane, defaults: defaults)
            let restored = SettingsPaneMemory.remembered(defaults: defaults)
            #expect(restored == pane)
        }
    }
}
