import Testing
import Foundation
@testable import keychord

@Suite("AppStateCurrentRepoMatch")
@MainActor
struct AppStateCurrentRepoMatchTests {

    static func makeState() -> AppState {
        AppState(
            accountsStore: AccountsStore(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("keychord-match-\(UUID().uuidString).json"),
                autoLoad: false
            )
        )
    }

    @Test func clearAccountMatchResetsToNil() async {
        let state = Self.makeState()
        state.accountMatch = .notARepo(path: "/tmp/example")
        #expect(state.accountMatch != nil)

        state.clearAccountMatch()
        #expect(state.accountMatch == nil)
    }

    /// The match outlives the popover, so the clear control has to take the
    /// whole derived state with it.
    @Test func clearAccountMatchAlsoDropsDerivedState() async {
        let state = Self.makeState()
        let account = Account.new(
            label: "work",
            sshAlias: "github-work",
            keyPath: "~/.ssh/id_work",
            gitUserName: "Work",
            gitUserEmail: "work@company.com",
            scope: .gitdir("~/work/")
        )
        state.accountMatch = .matched(
            account: account,
            repoRoot: "/tmp/repo",
            originURL: nil
        )
        state.identityAudit = IdentityAudit(
            account: account,
            repoRoot: "/tmp/repo",
            findings: [.authorMissing]
        )
        state.gitdirOverlap = GitdirOverlap(
            repoRoot: "/tmp/repo",
            contenders: []
        )
        state.staleGitdir = StaleGitdirRepair.Candidate(
            account: account,
            stalePath: "~/src/old-app/",
            replacementPath: "~/src/new-app/"
        )

        state.clearAccountMatch()

        #expect(state.accountMatch == nil)
        #expect(state.identityAudit == nil)
        #expect(state.gitdirOverlap == nil)
        #expect(state.staleGitdir == nil)
    }

    @Test func dismissingAStaleSuggestionKeepsTheMatch() {
        let state = Self.makeState()
        state.accountMatch = .noMatchingGitdir(repoRoot: "/tmp/repo")
        state.staleGitdir = StaleGitdirRepair.Candidate(
            account: Account.new(
                label: "work",
                sshAlias: "github-work",
                keyPath: "~/.ssh/id_work",
                gitUserName: "Work",
                gitUserEmail: "work@company.com",
                scope: .gitdir("~/src/old-app/")
            ),
            stalePath: "~/src/old-app/",
            replacementPath: "~/src/renamed-app/"
        )

        state.dismissStaleGitdir()

        #expect(state.staleGitdir == nil)
        #expect(state.accountMatch == .noMatchingGitdir(repoRoot: "/tmp/repo"))
    }

    @Test func resolvingAgainReplacesThePreviousMatch() async {
        let state = Self.makeState()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-not-a-repo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        state.accountMatch = .noMatchingGitdir(repoRoot: "/tmp/previous")
        await state.resolveCurrentRepo(at: tmp.path)

        // The last drop wins; nothing accumulates.
        #expect(state.accountMatch == .notARepo(path: tmp.path))
    }
}
