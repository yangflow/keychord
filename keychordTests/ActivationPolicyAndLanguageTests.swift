import Testing
import Foundation
import AppKit
@testable import keychord

@Suite("ActivationPolicyController")
struct ActivationPolicyControllerTests {

    @Test func restoresWhenNoTitledVisibleWindows() {
        let windows = [
            TitledWindowPresence(isTitled: true, isVisible: true, isClosing: true),
            TitledWindowPresence(isTitled: false, isVisible: true, isClosing: false),
        ]
        #expect(ActivationPolicyController.shouldRestoreAccessory(windows: windows))
    }

    @Test func keepsRegularWhenAnotherTitledWindowRemains() {
        let windows = [
            TitledWindowPresence(isTitled: true, isVisible: true, isClosing: true),
            TitledWindowPresence(isTitled: true, isVisible: true, isClosing: false),
        ]
        #expect(!ActivationPolicyController.shouldRestoreAccessory(windows: windows))
    }

    @Test func ignoresInvisibleTitledWindows() {
        let windows = [
            TitledWindowPresence(isTitled: true, isVisible: false, isClosing: false),
        ]
        #expect(ActivationPolicyController.shouldRestoreAccessory(windows: windows))
    }

    @Test func untitledMenubarWindowDoesNotBlockAccessory() {
        let windows = [
            TitledWindowPresence(isTitled: false, isVisible: true, isClosing: false),
        ]
        #expect(ActivationPolicyController.shouldRestoreAccessory(windows: windows))
    }
}

@Suite("AppLanguageStore")
@MainActor
struct AppLanguageStoreTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "keychord.tests.language.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultsToSystem() {
        let defaults = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)
        let preference = store.preference
        #expect(preference == .system)
        #expect(preference.appleLanguageCode == nil)
    }

    @Test func persistingEnglishWritesAppleLanguages() {
        let defaults = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)

        store.preference = .english

        let identifier = store.locale.identifier
        #expect(defaults.string(forKey: AppLanguageStore.preferenceKey) == "english")
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["en"])
        #expect(identifier.hasPrefix("en"))
    }

    /// #51: no relaunch demand. The note only appears while the choice differs
    /// from the language the process started in, which is exactly when window
    /// titles and the app menu are still reading the launch catalog.
    @Test func theNoteAppearsOnlyAfterAChange() {
        let defaults = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)
        let quietAtLaunch = store.showsLaunchCatalogNote

        store.preference = .english
        let afterChange = store.showsLaunchCatalogNote

        #expect(!quietAtLaunch)
        #expect(afterChange)
    }

    @Test func switchingBackToTheLaunchLanguageClearsTheNote() {
        let defaults = freshDefaults()
        defaults.set(
            AppLanguagePreference.simplifiedChinese.rawValue,
            forKey: AppLanguageStore.preferenceKey
        )
        let store = AppLanguageStore(defaults: defaults)
        let launchPreference = store.launchPreference

        store.preference = .english
        let afterChange = store.showsLaunchCatalogNote
        store.preference = .simplifiedChinese
        let afterSwitchingBack = store.showsLaunchCatalogNote

        #expect(launchPreference == .simplifiedChinese)
        #expect(afterChange)
        #expect(!afterSwitchingBack)
    }

    @Test func persistingSimplifiedChineseWritesAppleLanguages() {
        let defaults = freshDefaults()
        let store = AppLanguageStore(defaults: defaults)

        store.preference = .simplifiedChinese

        #expect(defaults.string(forKey: AppLanguageStore.preferenceKey) == "simplifiedChinese")
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["zh-Hans"])
    }

    @Test func returningToSystemClearsAppleLanguagesOverride() {
        let defaults = freshDefaults()
        defaults.set(["en"], forKey: "AppleLanguages")
        defaults.set(AppLanguagePreference.english.rawValue, forKey: AppLanguageStore.preferenceKey)
        let store = AppLanguageStore(defaults: defaults)

        store.preference = .system

        #expect(defaults.object(forKey: "AppleLanguages") == nil)
        #expect(defaults.string(forKey: AppLanguageStore.preferenceKey) == "system")
    }

    @Test func storedPreferenceSurvivesAnUnknownRawValue() {
        let defaults = freshDefaults()
        defaults.set("klingon", forKey: AppLanguageStore.preferenceKey)

        let stored = AppLanguageStore.storedPreference(defaults: defaults)
        #expect(stored == .system)
    }

    @Test func bootstrapAppliesStoredPreference() {
        let defaults = freshDefaults()
        defaults.set(AppLanguagePreference.simplifiedChinese.rawValue, forKey: AppLanguageStore.preferenceKey)

        AppLanguageStore.bootstrapAppleLanguages(defaults: defaults)

        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["zh-Hans"])
    }

    @Test func bootstrapSystemRemovesOverride() {
        let defaults = freshDefaults()
        defaults.set(["zh-Hans"], forKey: "AppleLanguages")

        AppLanguageStore.bootstrapAppleLanguages(defaults: defaults)

        #expect(defaults.object(forKey: "AppleLanguages") == nil)
    }
}
