import Testing
import Foundation
@testable import keychord

@Suite("MenuBarTooltip")
struct MenuBarTooltipTests {

    static func account(label: String) -> Account {
        Account.new(
            label: label,
            sshAlias: "github-work",
            keyPath: "~/.ssh/id_work",
            gitUserName: "Work",
            gitUserEmail: "work@example.com",
            scope: .gitdir("~/work/")
        )
    }

    @Test func idleTooltipIsJustTheAppName() {
        #expect(MenuBarTooltip.text(for: nil) == "KeyChord")
    }

    @Test func matchTooltipNamesTheIdentity() {
        let match = AccountMatchResult.matched(
            account: Self.account(label: "work"),
            repoRoot: "/tmp/repo",
            originURL: nil
        )
        #expect(MenuBarTooltip.text(for: match) == "KeyChord · work")
    }

    @Test func unnamedAccountFallsBackToAPlaceholder() {
        let match = AccountMatchResult.matched(
            account: Self.account(label: "   "),
            repoRoot: "/tmp/repo",
            originURL: nil
        )
        let text = MenuBarTooltip.text(for: match)
        #expect(text.hasPrefix("KeyChord · "))
        #expect(text != "KeyChord · ")
        #expect(!text.contains("   "))
    }

    @Test func unresolvedMatchesShareOneTooltip() throws {
        let unresolved: [AccountMatchResult] = [
            .notARepo(path: "/tmp/plain"),
            .noMatchingGitdir(repoRoot: "/tmp/repo"),
            .conflictingGlobals(repoRoot: "/tmp/repo", accounts: []),
        ]
        let texts = Set(unresolved.map { MenuBarTooltip.text(for: $0) })
        #expect(texts.count == 1)
        let text = try #require(texts.first)
        #expect(text.hasPrefix("KeyChord · "))
        #expect(text != "KeyChord")
    }
}
