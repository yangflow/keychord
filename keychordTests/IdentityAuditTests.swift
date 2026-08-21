import Testing
import Foundation
@testable import keychord

@Suite("IdentityAudit")
struct IdentityAuditTests {

    static func account(
        label: String,
        email: String,
        keyPath: String = "~/.ssh/id_work",
        scope: Account.Scope = .gitdir("~/work/")
    ) -> Account {
        Account.new(
            label: label,
            sshAlias: "github-\(label.lowercased())",
            keyPath: keyPath,
            gitUserName: label,
            gitUserEmail: email,
            scope: scope,
            color: .blue
        )
    }

    static func identity(
        email: String?,
        sshCommand: String? = nil
    ) -> CurrentRepoResolver.EffectiveGitIdentity {
        CurrentRepoResolver.EffectiveGitIdentity(
            userName: "Someone",
            userEmail: email,
            sshCommand: sshCommand
        )
    }

    // MARK: - Clean

    @Test func matchingEmailAndKeyProducesNoFindings() {
        let work = Self.account(label: "Work", email: "work@example.com")
        let audit = IdentityAudit.audit(
            account: work,
            repoRoot: "/tmp/repo",
            identity: Self.identity(
                email: "work@example.com",
                sshCommand: "ssh -i ~/.ssh/id_work -o IdentitiesOnly=yes"
            ),
            accounts: [work]
        )
        #expect(audit.isClean)
        #expect(audit.severity == nil)
    }

    @Test func emailComparisonIgnoresCaseAndSurroundingSpace() {
        let work = Self.account(label: "Work", email: "Work@Example.com")
        let audit = IdentityAudit.audit(
            account: work,
            repoRoot: "/tmp/repo",
            identity: Self.identity(email: " work@example.com "),
            accounts: [work]
        )
        #expect(audit.isClean)
    }

    // MARK: - Author belongs to another account

    @Test func flagsCommitsAuthoredByAnotherAccount() {
        let work = Self.account(label: "Work", email: "work@company.com")
        let personal = Self.account(
            label: "Personal",
            email: "me@example.com",
            keyPath: "~/.ssh/id_personal",
            scope: .global
        )
        let audit = IdentityAudit.audit(
            account: work,
            repoRoot: "/tmp/repo",
            identity: Self.identity(email: "me@example.com"),
            accounts: [work, personal]
        )
        #expect(audit.findings == [
            .authorIsOtherAccount(email: "me@example.com", label: "Personal")
        ])
        #expect(audit.severity == .error)
        #expect(audit.findings[0].localizedDetail.contains("me@example.com"))
        #expect(audit.findings[0].localizedDetail.contains("Personal"))
    }

    @Test func flagsAnAuthorNoAccountOwns() {
        let work = Self.account(label: "Work", email: "work@company.com")
        let audit = IdentityAudit.audit(
            account: work,
            repoRoot: "/tmp/repo",
            identity: Self.identity(email: "someone-else@example.com"),
            accounts: [work]
        )
        #expect(audit.findings == [.authorIsUnmanaged(email: "someone-else@example.com")])
        #expect(audit.severity == .warning)
    }

    @Test func flagsMissingAuthorEmail() {
        let work = Self.account(label: "Work", email: "work@company.com")
        let audit = IdentityAudit.audit(
            account: work,
            repoRoot: "/tmp/repo",
            identity: Self.identity(email: nil),
            accounts: [work]
        )
        #expect(audit.findings == [.authorMissing])
    }

    @Test func accountWithoutAnEmailNeverBlamesTheAuthor() {
        let blank = Self.account(label: "Blank", email: "")
        let audit = IdentityAudit.audit(
            account: blank,
            repoRoot: "/tmp/repo",
            identity: Self.identity(email: "someone@example.com"),
            accounts: [blank]
        )
        #expect(audit.isClean)
    }

    @Test func staysQuietWhenNeitherSideHasAnEmail() {
        let blank = Self.account(label: "Blank", email: "")
        let audit = IdentityAudit.audit(
            account: blank,
            repoRoot: "/tmp/repo",
            identity: Self.identity(email: nil),
            accounts: [blank]
        )
        #expect(audit.isClean)
    }

    // MARK: - Key override

    @Test func flagsSSHCommandPinningAnotherKey() {
        let work = Self.account(label: "Work", email: "work@company.com")
        let audit = IdentityAudit.audit(
            account: work,
            repoRoot: "/tmp/repo",
            identity: Self.identity(
                email: "work@company.com",
                sshCommand: "ssh -i ~/.ssh/id_personal -o IdentitiesOnly=yes"
            ),
            accounts: [work]
        )
        #expect(audit.findings == [.keyOverride(keyPath: "~/.ssh/id_personal")])
    }

    @Test func absoluteAndTildeKeyPathsCompareEqual() {
        let work = Self.account(
            label: "Work",
            email: "work@company.com",
            keyPath: "~/.ssh/id_work"
        )
        let absolute = "\(NSHomeDirectory())/.ssh/id_work"
        let audit = IdentityAudit.audit(
            account: work,
            repoRoot: "/tmp/repo",
            identity: Self.identity(
                email: "work@company.com",
                sshCommand: "ssh -i \(absolute)"
            ),
            accounts: [work]
        )
        #expect(audit.isClean)
    }

    @Test func accountWithoutAKeyDoesNotFlagSSHCommand() {
        let work = Self.account(label: "Work", email: "work@company.com", keyPath: "")
        let audit = IdentityAudit.audit(
            account: work,
            repoRoot: "/tmp/repo",
            identity: Self.identity(
                email: "work@company.com",
                sshCommand: "ssh -i ~/.ssh/id_other"
            ),
            accounts: [work]
        )
        #expect(audit.isClean)
    }

    // MARK: - sshCommand parsing

    @Test func parsesIdentityFileFromSSHCommand() {
        #expect(IdentityAudit.identityFile(fromSSHCommand: "ssh -i ~/.ssh/id_a") == "~/.ssh/id_a")
        #expect(IdentityAudit.identityFile(fromSSHCommand: "ssh -o Foo=bar -i ~/.ssh/id_b -T") == "~/.ssh/id_b")
        #expect(IdentityAudit.identityFile(fromSSHCommand: "ssh -i\"~/.ssh/id_c\"") == "~/.ssh/id_c")
        #expect(IdentityAudit.identityFile(fromSSHCommand: "ssh -i '~/.ssh/id_d'") == "~/.ssh/id_d")
    }

    @Test func returnsNilWhenSSHCommandPinsNoKey() {
        #expect(IdentityAudit.identityFile(fromSSHCommand: nil) == nil)
        #expect(IdentityAudit.identityFile(fromSSHCommand: "   ") == nil)
        #expect(IdentityAudit.identityFile(fromSSHCommand: "ssh -o IdentitiesOnly=yes") == nil)
        #expect(IdentityAudit.identityFile(fromSSHCommand: "ssh -i") == nil)
    }

    // MARK: - Live work tree

    @Test func readsEffectiveIdentityFromARepository() throws {
        let repo = try CurrentRepoResolverTests.makeRepo(
            userName: "Personal Me",
            userEmail: "me@example.com"
        )
        defer { try? FileManager.default.removeItem(at: repo) }
        try CurrentRepoResolverTests.runGit(
            at: repo.path,
            args: ["config", "core.sshCommand", "ssh -i ~/.ssh/id_personal"]
        )

        let identity = CurrentRepoResolver.readEffectiveIdentitySync(
            at: repo.path,
            env: CurrentRepoResolverTests.isolatedEnv
        )
        #expect(identity.userEmail == "me@example.com")
        #expect(identity.userName == "Personal Me")
        #expect(identity.sshCommand == "ssh -i ~/.ssh/id_personal")

        // The gitdir scope says push as work, the work tree says commit as
        // personal: exactly the case that produces a bad commit.
        let work = Self.account(label: "Work", email: "work@company.com")
        let personal = Self.account(
            label: "Personal",
            email: "me@example.com",
            keyPath: "~/.ssh/id_personal",
            scope: .global
        )
        let audit = IdentityAudit.audit(
            account: work,
            repoRoot: repo.path,
            identity: identity,
            accounts: [work, personal]
        )
        #expect(audit.findings.contains(.authorIsOtherAccount(
            email: "me@example.com",
            label: "Personal"
        )))
        #expect(audit.findings.contains(.keyOverride(keyPath: "~/.ssh/id_personal")))
        #expect(audit.severity == .error)
    }
}
