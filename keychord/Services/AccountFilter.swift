import Foundation

/// Pure filtering for the popover's identity list: free text over label,
/// alias, email, username and provider, plus an optional provider chip.
enum AccountFilter {

    /// Below this the list is short enough to scan, so the popover hides the
    /// search field entirely.
    static let minimumAccountsForSearch = 3

    static func shouldOfferSearch(accountCount: Int) -> Bool {
        accountCount >= minimumAccountsForSearch
    }

    /// Providers worth showing as chips: only when more than one is in use.
    /// Ordered by `Account.Provider.allCases` so the chips never reshuffle.
    static func chipProviders(for accounts: [Account]) -> [Account.Provider] {
        let present = Set(accounts.map(\.provider))
        guard present.count > 1 else { return [] }
        return Account.Provider.allCases.filter { present.contains($0) }
    }

    static func apply(
        accounts: [Account],
        query: String = "",
        provider: Account.Provider? = nil
    ) -> [Account] {
        accounts.filter { account in
            (provider == nil || account.provider == provider)
                && matches(account: account, query: query)
        }
    }

    /// Case- and diacritic-insensitive substring match across the fields a user
    /// would type: label, SSH alias, git email, forge username, provider name.
    static func matches(account: Account, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return searchableFields(of: account).contains { field in
            field.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    static func searchableFields(of account: Account) -> [String] {
        [
            account.label,
            account.sshAlias,
            account.gitUserEmail,
            account.gitUserName,
            account.username,
            account.provider.rawValue,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
}
