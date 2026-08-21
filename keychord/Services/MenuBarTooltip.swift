import AppKit

/// Tooltip text for the status item, so the identity a drop resolved to is
/// readable without opening the popover. The icon itself is untouched: idle
/// stays the plain key glyph.
enum MenuBarTooltip {
    static let appName = "KeyChord"

    /// `KeyChord · work` while a match is active, `KeyChord · no match` when a
    /// drop resolved to nothing, plain `KeyChord` when idle.
    static func text(for match: AccountMatchResult?) -> String {
        guard let match else { return appName }
        switch match {
        case .matched(let account, _, _):
            let label = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = label.isEmpty ? String.loc("(unnamed)") : label
            return "\(appName) · \(name)"
        case .notARepo, .noMatchingGitdir, .conflictingGlobals:
            return "\(appName) · \(String.loc("no match"))"
        }
    }

    @MainActor
    static func apply(_ text: String) {
        MenuBarStatusItemLocator.keychordStatusItem()?.button?.toolTip = text
    }
}
