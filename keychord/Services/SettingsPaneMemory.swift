import Foundation

/// Remembers which Settings pane was last open so reopening the window lands
/// where the user left off instead of snapping back to General.
///
/// Per app, not per account: the pane is about the tool, not the identity being
/// edited. A one-shot request — the popover's empty state asking for Import —
/// still wins, because the user just said where they want to go.
enum SettingsPaneMemory {
    static let paneKey = "keychord.settings.lastPane"

    /// Last pane the user selected, or `nil` when nothing is stored or the
    /// stored pane no longer exists in this build.
    static func remembered(defaults: UserDefaults = .standard) -> SettingsPane? {
        guard let raw = defaults.string(forKey: paneKey) else { return nil }
        return SettingsPane(rawValue: raw)
    }

    static func remember(_ pane: SettingsPane, defaults: UserDefaults = .standard) {
        defaults.set(pane.rawValue, forKey: paneKey)
    }

    /// Pane the window should open on.
    static func paneOnOpen(
        pending: SettingsPane?,
        defaults: UserDefaults = .standard
    ) -> SettingsPane {
        pending ?? remembered(defaults: defaults) ?? .general
    }
}
