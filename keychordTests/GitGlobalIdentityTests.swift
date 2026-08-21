import Testing
import Foundation
@testable import keychord

@Suite("GitGlobalIdentity")
struct GitGlobalIdentityTests {

    @Test func readsNameAndEmailFromGlobalConfig() {
        let runner = MockProcessRunner(result: ProcessResult(
            exitCode: 0,
            stdout: "Alex Doe\n",
            stderr: ""
        ))
        let identity = GitGlobalIdentity.readSync(runner: runner)
        #expect(identity.name == "Alex Doe")
        #expect(identity.email == "Alex Doe")

        let invocation = runner.invocations.first
        #expect(invocation?.executable == "/usr/bin/git")
        #expect(invocation?.arguments == ["config", "--global", "--get", "user.name"])
        #expect(runner.invocations.count == 2)
    }

    @Test func unsetKeysReadAsEmpty() {
        let runner = MockProcessRunner(result: ProcessResult(exitCode: 1, stdout: "", stderr: ""))
        let identity = GitGlobalIdentity.readSync(runner: runner)
        #expect(identity == .empty)
        #expect(identity.isEmpty)
    }

    @Test func missingGitBinaryReadsAsEmpty() {
        let runner = MockProcessRunner(result: ProcessResult(
            exitCode: -1,
            stdout: "",
            stderr: "launch failed"
        ))
        #expect(GitGlobalIdentity.readSync(runner: runner).isEmpty)
    }
}

/// #49: the Accounts-window `+` form starts on the global author. The read is
/// async, so “the user typed something meanwhile” is the case that matters.
@Suite("GitGlobalIdentity.prefill")
struct GitGlobalIdentityPrefillTests {

    private static let global = GitGlobalIdentity.Identity(
        name: "Alex Doe",
        email: "alex@example.com"
    )

    private static func blankDraft() -> Account {
        Account.new(
            label: "",
            sshAlias: "",
            keyPath: "",
            gitUserName: "",
            gitUserEmail: ""
        )
    }

    @Test func emptyFieldsTakeTheGlobalAuthor() {
        let prefill = GitGlobalIdentity.prefill(Self.blankDraft(), with: Self.global)
        #expect(prefill.didFill)
        #expect(prefill.account.gitUserName == "Alex Doe")
        #expect(prefill.account.gitUserEmail == "alex@example.com")
    }

    @Test func aTypedNameIsNeverOverwritten() {
        var draft = Self.blankDraft()
        draft.gitUserName = "Typed Name"

        let prefill = GitGlobalIdentity.prefill(draft, with: Self.global)
        #expect(prefill.account.gitUserName == "Typed Name")
        // The still-empty field is fair game.
        #expect(prefill.account.gitUserEmail == "alex@example.com")
        #expect(prefill.didFill)
    }

    @Test func aFullyTypedIdentityIsLeftAlone() {
        var draft = Self.blankDraft()
        draft.gitUserName = "Typed Name"
        draft.gitUserEmail = "typed@example.com"

        let prefill = GitGlobalIdentity.prefill(draft, with: Self.global)
        #expect(!prefill.didFill)
        #expect(prefill.account == draft)
    }

    @Test func noGlobalAuthorLeavesTheFormBlank() {
        let draft = Self.blankDraft()
        let prefill = GitGlobalIdentity.prefill(draft, with: .empty)
        #expect(!prefill.didFill)
        #expect(prefill.account == draft)
    }

    /// Only `user.name` is set globally — that half still gets filled.
    @Test func aPartialGlobalIdentityFillsWhatItHas() {
        let identity = GitGlobalIdentity.Identity(name: "Alex Doe", email: "")
        let prefill = GitGlobalIdentity.prefill(Self.blankDraft(), with: identity)
        #expect(prefill.didFill)
        #expect(prefill.account.gitUserName == "Alex Doe")
        #expect(prefill.account.gitUserEmail.isEmpty)
    }

    /// A field holding only spaces counts as empty; the user did not mean that.
    @Test func whitespaceOnlyFieldsCountAsEmpty() {
        var draft = Self.blankDraft()
        draft.gitUserName = "   "
        draft.gitUserEmail = "\n"

        let prefill = GitGlobalIdentity.prefill(draft, with: Self.global)
        #expect(prefill.account.gitUserName == "Alex Doe")
        #expect(prefill.account.gitUserEmail == "alex@example.com")
    }

    @Test func prefillTouchesNothingElseOnTheDraft() {
        var draft = Self.blankDraft()
        draft.scope = .gitdir(paths: ["~/src/app/"])
        draft.sshPort = .port443

        let prefill = GitGlobalIdentity.prefill(draft, with: Self.global)
        #expect(prefill.account.id == draft.id)
        #expect(prefill.account.scope == .gitdir(paths: ["~/src/app/"]))
        #expect(prefill.account.sshPort == .port443)
        #expect(prefill.account.label.isEmpty)
        #expect(prefill.account.sshAlias.isEmpty)
    }
}

@Suite("DroppedFolderAccountDraft")
struct DroppedFolderAccountDraftTests {

    static func existing(label: String, color: Account.AccountColor) -> Account {
        var account = Account.new(
            label: label,
            sshAlias: "github-\(label)",
            keyPath: "~/.ssh/id_\(label)",
            gitUserName: label,
            gitUserEmail: "\(label)@example.com"
        )
        account.color = color
        return account
    }

    @Test func draftIsScopedToTheDroppedFolder() throws {
        let draft = try #require(
            DroppedFolderAccountDraft.make(
                folderPath: "\(NSHomeDirectory())/src/new-app",
                globalIdentity: GitGlobalIdentity.Identity(
                    name: "Alex Doe",
                    email: "alex@example.com"
                )
            )
        )
        #expect(draft.scope.directories == ["~/src/new-app/"])
        #expect(draft.gitUserName == "Alex Doe")
        #expect(draft.gitUserEmail == "alex@example.com")
        // 443 by default so the SSH-over-HTTPS fallback works out of the box.
        #expect(draft.sshPort == .port443)
        // Left for the user to fill in the Accounts window.
        #expect(draft.label.isEmpty)
        #expect(draft.sshAlias.isEmpty)
        #expect(draft.keyPath.isEmpty)
    }

    @Test func draftKeepsPathsOutsideHomeAbsolute() throws {
        let draft = try #require(
            DroppedFolderAccountDraft.make(folderPath: "/opt/repos/app")
        )
        #expect(draft.scope.directories == ["/opt/repos/app/"])
    }

    @Test func emptyGlobalIdentityLeavesTheFieldsBlank() throws {
        let draft = try #require(
            DroppedFolderAccountDraft.make(folderPath: "\(NSHomeDirectory())/src/app")
        )
        #expect(draft.gitUserName.isEmpty)
        #expect(draft.gitUserEmail.isEmpty)
    }

    @Test func blankFolderYieldsNoDraft() {
        #expect(DroppedFolderAccountDraft.make(folderPath: "   ") == nil)
    }

    @Test func colorPicksTheFirstUnusedPreset() {
        let taken = [
            Self.existing(label: "a", color: .blue),
            Self.existing(label: "b", color: .green),
        ]
        #expect(DroppedFolderAccountDraft.nextColor(after: taken) == .orange)
        #expect(DroppedFolderAccountDraft.nextColor(after: []) == .blue)
    }

    @Test func colorCyclesOncEveryPresetIsTaken() {
        let taken = Account.AccountColor.presets.map {
            Self.existing(label: $0.rawValue, color: $0)
        }
        let next = DroppedFolderAccountDraft.nextColor(after: taken)
        #expect(Account.AccountColor.presets.contains(next))
    }
}
