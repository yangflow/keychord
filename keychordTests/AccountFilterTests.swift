import Testing
import Foundation
@testable import keychord

@Suite("AccountFilter")
struct AccountFilterTests {

    static func account(
        label: String,
        alias: String = "",
        email: String = "",
        username: String = "",
        provider: Account.Provider = .github
    ) -> Account {
        var account = Account.new(
            label: label,
            sshAlias: alias,
            keyPath: "~/.ssh/id_\(label)",
            provider: provider,
            gitUserName: label,
            gitUserEmail: email
        )
        account.username = username
        return account
    }

    static let roster: [Account] = [
        account(label: "work-acme", alias: "github-acme", email: "alex@acme.com", provider: .github),
        account(label: "work-labs", alias: "github-labs", email: "alex@labs.dev", provider: .github),
        account(label: "personal", alias: "gl-personal", email: "alex@example.com", provider: .gitlab),
    ]

    // MARK: - When to show the field

    @Test func searchAppearsOnlyForThreeOrMoreAccounts() {
        #expect(!AccountFilter.shouldOfferSearch(accountCount: 0))
        #expect(!AccountFilter.shouldOfferSearch(accountCount: 1))
        #expect(!AccountFilter.shouldOfferSearch(accountCount: 2))
        #expect(AccountFilter.shouldOfferSearch(accountCount: 3))
        #expect(AccountFilter.shouldOfferSearch(accountCount: 9))
    }

    // MARK: - Provider chips

    @Test func chipsOnlyAppearWithMoreThanOneProvider() {
        #expect(AccountFilter.chipProviders(for: []).isEmpty)
        #expect(AccountFilter.chipProviders(for: [Self.roster[0], Self.roster[1]]).isEmpty)
        #expect(AccountFilter.chipProviders(for: Self.roster) == [.github, .gitlab])
    }

    @Test func chipOrderFollowsTheProviderEnumNotInsertionOrder() {
        let reversed: [Account] = [
            Self.account(label: "a", provider: .gitea),
            Self.account(label: "b", provider: .github),
        ]
        #expect(AccountFilter.chipProviders(for: reversed) == [.github, .gitea])
    }

    // MARK: - Text matching

    @Test func emptyQueryKeepsEveryone() {
        #expect(AccountFilter.apply(accounts: Self.roster).count == 3)
        #expect(AccountFilter.apply(accounts: Self.roster, query: "   ").count == 3)
    }

    @Test func typingWorkHidesNonMatches() {
        let hits = AccountFilter.apply(accounts: Self.roster, query: "work")
        #expect(hits.map(\.label) == ["work-acme", "work-labs"])
    }

    @Test func matchesAliasEmailUsernameAndProvider() {
        #expect(AccountFilter.apply(accounts: Self.roster, query: "gl-").map(\.label) == ["personal"])
        #expect(AccountFilter.apply(accounts: Self.roster, query: "labs.dev").map(\.label) == ["work-labs"])
        #expect(AccountFilter.apply(accounts: Self.roster, query: "gitlab").map(\.label) == ["personal"])

        let named = Self.account(label: "ops", username: "octocat")
        #expect(AccountFilter.matches(account: named, query: "octo"))
    }

    @Test func matchingIgnoresCase() {
        #expect(AccountFilter.apply(accounts: Self.roster, query: "WORK-ACME").map(\.label) == ["work-acme"])
        #expect(AccountFilter.apply(accounts: Self.roster, query: "AlEx@AcMe.CoM").map(\.label) == ["work-acme"])
    }

    @Test func noMatchYieldsAnEmptyList() {
        #expect(AccountFilter.apply(accounts: Self.roster, query: "nope").isEmpty)
    }

    @Test func blankFieldsAreNotSearchable() {
        let sparse = Self.account(label: "", alias: "", email: "")
        #expect(!AccountFilter.matches(account: sparse, query: "a"))
        #expect(AccountFilter.matches(account: sparse, query: ""))
    }

    // MARK: - Provider chip + text together

    @Test func providerChipNarrowsTheList() {
        #expect(
            AccountFilter.apply(accounts: Self.roster, provider: .github).map(\.label)
                == ["work-acme", "work-labs"]
        )
        #expect(
            AccountFilter.apply(accounts: Self.roster, query: "acme", provider: .github)
                .map(\.label) == ["work-acme"]
        )
        #expect(
            AccountFilter.apply(accounts: Self.roster, query: "acme", provider: .gitlab).isEmpty
        )
    }
}
