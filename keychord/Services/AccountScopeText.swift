import Foundation

/// One place that turns a scope into words, so the popover row tooltip, the
/// match card, and the snapshot detail sheet cannot drift apart.
enum AccountScopeText {

    /// Separator between several `gitdir:` paths.
    static let pathSeparator = " · "

    /// Every usable `gitdir:` path in display form. Empty for a global scope
    /// (or one whose entries are all blank).
    static func paths(of scope: Account.Scope) -> [String] {
        scope.directories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.abbreviatedHomePath() }
    }

    static func paths(of account: Account) -> [String] {
        paths(of: account.scope)
    }

    /// Hover / VoiceOver answer to “where does this identity apply?”:
    /// `gitdir: ~/work/ · ~/src/new-app/`, or the localized “Global”.
    static func summary(of scope: Account.Scope) -> String {
        let dirs = paths(of: scope)
        guard !dirs.isEmpty else { return String(localized: "Global") }
        return "gitdir: " + dirs.joined(separator: pathSeparator)
    }

    static func summary(for account: Account) -> String {
        summary(of: account.scope)
    }

    /// Longer form for cards and forms that spell out “scope:”.
    static func scopeLine(of scope: Account.Scope) -> String {
        let dirs = paths(of: scope)
        guard !dirs.isEmpty else { return String(localized: "scope: global") }
        return String(localized: "scope: gitdir:\(dirs.joined(separator: pathSeparator))")
    }

    static func scopeLine(for account: Account) -> String {
        scopeLine(of: account.scope)
    }
}
