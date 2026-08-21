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

    // MARK: - Undo toast (#42)

    static func sampleAccount(label: String = "work") -> Account {
        Account.new(
            label: label,
            sshAlias: "github-\(label)",
            keyPath: "~/.ssh/id_\(label)",
            gitUserName: label,
            gitUserEmail: "\(label)@company.com",
            scope: .gitdir("~/work/")
        )
    }

    @Test func recordingAnUndoKeepsThePreviousScopes() {
        let state = Self.makeState()
        let before = Self.sampleAccount()

        state.recordScopeUndo(
            previousAccounts: [before],
            boundLabel: "work",
            repoRoot: "/tmp/repo",
            now: Date(timeIntervalSince1970: 1_000_000)
        )

        let undo = state.scopeUndo
        #expect(undo?.boundLabel == "work")
        #expect(undo?.repoRoot == "/tmp/repo")
        #expect(undo?.previousAccounts.first?.scope.directories == ["~/work/"])
        // Five seconds, measured from the moment of the change.
        #expect(
            undo?.expiresAt == Date(timeIntervalSince1970: 1_000_000)
                .addingTimeInterval(AppState.ScopeUndo.window)
        )
    }

    @Test func recordingASecondUndoReplacesTheFirst() {
        let state = Self.makeState()
        state.recordScopeUndo(
            previousAccounts: [Self.sampleAccount(label: "work")],
            boundLabel: "work",
            repoRoot: "/tmp/one"
        )
        let first = state.scopeUndo?.id
        state.recordScopeUndo(
            previousAccounts: [Self.sampleAccount(label: "personal")],
            boundLabel: "personal",
            repoRoot: "/tmp/two"
        )
        #expect(state.scopeUndo?.id != first)
        #expect(state.scopeUndo?.boundLabel == "personal")
    }

    @Test func clearingTheMatchDropsTheUndo() {
        let state = Self.makeState()
        state.recordScopeUndo(
            previousAccounts: [Self.sampleAccount()],
            boundLabel: "work",
            repoRoot: "/tmp/repo"
        )
        state.clearAccountMatch()
        #expect(state.scopeUndo == nil)
    }

    @Test func undoWithNothingRecordedIsHarmless() async {
        let state = Self.makeState()
        #expect(await state.undoScopeChange() == nil)
        #expect(state.scopeUndo == nil)
    }

    @Test func toastCountdownRoundsUpAndFloorsAtZero() {
        let deadline = Date(timeIntervalSince1970: 1_000_005)
        #expect(
            UndoBindToast.remainingSeconds(
                until: deadline,
                now: Date(timeIntervalSince1970: 1_000_000)
            ) == 5
        )
        #expect(
            UndoBindToast.remainingSeconds(
                until: deadline,
                now: Date(timeIntervalSince1970: 1_000_004.2)
            ) == 1
        )
        #expect(
            UndoBindToast.remainingSeconds(
                until: deadline,
                now: Date(timeIntervalSince1970: 1_000_009)
            ) == 0
        )
    }

    // MARK: - New identity from a failed drop (#41)

    @Test func preparingADraftNeedsABindableFolder() async {
        let state = Self.makeState()
        state.accountMatch = .notARepo(path: "/tmp/plain")
        #expect(await state.prepareNewAccountDraftForMatch() == false)
        #expect(state.pendingNewAccountDraft == nil)
        #expect(state.pendingBindFolder == nil)
    }

    @Test func preparingADraftScopesItToTheDroppedFolder() async {
        let state = Self.makeState()
        state.accountMatch = .noMatchingGitdir(repoRoot: "\(NSHomeDirectory())/src/new-app")

        #expect(await state.prepareNewAccountDraftForMatch())
        #expect(state.pendingNewAccountDraft?.scope.directories == ["~/src/new-app/"])
        #expect(state.pendingNewAccountDraft?.sshPort == .port443)
        #expect(state.pendingBindFolder == "\(NSHomeDirectory())/src/new-app")
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
