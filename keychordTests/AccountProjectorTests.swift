import Testing
import Foundation
@testable import keychord

@Suite("AccountProjector")
struct AccountProjectorTests {

    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Fixture builders

    static func globalAccount() -> Account {
        Account(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            label: "Personal",
            githubUsername: "yangflow",
            sshAlias: "github.com",
            keyPath: "\(NSHomeDirectory())/.ssh/id_ed25519",
            keyFingerprint: nil,
            sshPort: .port443,
            gitUserName: "yangflow",
            gitUserEmail: "ydongy02@gmail.com",
            scope: .global,
            urlRewrites: [
                Account.URLRewrite(
                    from: "https://github.com/",
                    to: "git@github.com:"
                )
            ],
            color: .blue,
            notes: "",
            createdAt: fixedDate,
            updatedAt: fixedDate,
            lastUsedAt: nil
        )
    }

    static func scopedAccount() -> Account {
        Account(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            label: "work",
            githubUsername: "bob",
            sshAlias: "github-work",
            keyPath: "\(NSHomeDirectory())/.ssh/id_rsa",
            keyFingerprint: nil,
            sshPort: .port443,
            gitUserName: "bob",
            gitUserEmail: "bob@example.com",
            scope: .gitdir("~/work/"),
            urlRewrites: [
                Account.URLRewrite(
                    from: "https://github.com/acme-corp/",
                    to: "git@github-work:acme-corp/"
                ),
                Account.URLRewrite(
                    from: "git@github.com:acme-corp/",
                    to: "git@github-work:acme-corp/"
                )
            ],
            color: .orange,
            notes: "",
            createdAt: fixedDate,
            updatedAt: fixedDate,
            lastUsedAt: nil
        )
    }

    // MARK: - Empty projection

    @Test func emptyAccountsYieldsHeaderOnly() {
        let output = AccountProjector.project([], generatedAt: Self.fixedDate)
        #expect(output.sshConfig.contains("AUTO-GENERATED"))
        #expect(output.gitConfig.contains("AUTO-GENERATED"))
        #expect(output.subFiles.isEmpty)
        // No Host blocks
        #expect(!output.sshConfig.contains("Host "))
    }

    // MARK: - Global account

    @Test func globalAccountEmitsHostBlockAndUserSection() {
        let account = Self.globalAccount()
        let output = AccountProjector.project([account], generatedAt: Self.fixedDate)

        // SSH Host block with tilde-abbreviated key path
        #expect(output.sshConfig.contains("Host github.com"))
        #expect(output.sshConfig.contains("HostName ssh.github.com"))
        #expect(output.sshConfig.contains("IdentityFile ~/.ssh/id_ed25519"))
        #expect(output.sshConfig.contains("HostKeyAlias github.com"))

        // Git main config has [user] and [url]
        #expect(output.gitConfig.contains("[user]"))
        #expect(output.gitConfig.contains("name = yangflow"))
        #expect(output.gitConfig.contains("email = ydongy02@gmail.com"))
        #expect(output.gitConfig.contains("[url \"git@github.com:\"]"))
        #expect(output.gitConfig.contains("insteadOf = https://github.com/"))

        // No sub files for global accounts
        #expect(output.subFiles.isEmpty)
    }

    // MARK: - Scoped account

    @Test func scopedAccountEmitsIncludeIfAndSubFile() {
        let account = Self.scopedAccount()
        let paths = AccountProjector.ManagedPaths.default
        let output = AccountProjector.project(
            [account],
            generatedAt: Self.fixedDate,
            paths: paths
        )

        // Host block
        #expect(output.sshConfig.contains("Host github-work"))
        #expect(output.sshConfig.contains("IdentityFile ~/.ssh/id_rsa"))

        // Main gitconfig has includeIf
        #expect(output.gitConfig.contains("[includeIf \"gitdir:~/work/\"]"))
        #expect(output.gitConfig.contains(".managed"))
        // No [user] section — scoped account's user lives in sub file
        #expect(!output.gitConfig.contains("[user]"))

        // Main gitconfig still has the url rewrites
        #expect(output.gitConfig.contains("[url \"git@github-work:acme-corp/\"]"))
        #expect(output.gitConfig.contains("insteadOf = https://github.com/acme-corp/"))
        #expect(output.gitConfig.contains("insteadOf = git@github.com:acme-corp/"))

        // Sub file exists with user + sshCommand
        #expect(output.subFiles.count == 1)
        #expect(output.subFiles[0].accountID == account.id)
        #expect(output.subFiles[0].content.contains("name = bob"))
        #expect(output.subFiles[0].content.contains("email = bob@example.com"))
        #expect(output.subFiles[0].content.contains("sshCommand = ssh -i ~/.ssh/id_rsa"))
    }

    // MARK: - Mixed

    @Test func mixedAccountsEmitBothHosts() {
        let output = AccountProjector.project(
            [Self.globalAccount(), Self.scopedAccount()],
            generatedAt: Self.fixedDate
        )
        #expect(output.sshConfig.contains("Host github.com"))
        #expect(output.sshConfig.contains("Host github-work"))
        #expect(output.subFiles.count == 1)
    }

    // MARK: - Determinism

    @Test func projectionIsDeterministic() {
        let accounts = [Self.scopedAccount(), Self.globalAccount()]
        let a = AccountProjector.project(accounts, generatedAt: Self.fixedDate)
        let b = AccountProjector.project(accounts, generatedAt: Self.fixedDate)
        #expect(a == b)
    }

    @Test func urlRewritesSortedByTarget() {
        var accA = Self.globalAccount()
        accA.urlRewrites = [
            Account.URLRewrite(from: "https://a/", to: "git@b:"),
            Account.URLRewrite(from: "https://c/", to: "git@a:"),
            Account.URLRewrite(from: "https://d/", to: "git@c:")
        ]
        let output = AccountProjector.project([accA], generatedAt: Self.fixedDate)
        let aIdx = output.gitConfig.range(of: "[url \"git@a:\"]")?.lowerBound
        let bIdx = output.gitConfig.range(of: "[url \"git@b:\"]")?.lowerBound
        let cIdx = output.gitConfig.range(of: "[url \"git@c:\"]")?.lowerBound
        #expect(aIdx != nil && bIdx != nil && cIdx != nil)
        if let a = aIdx, let b = bIdx, let c = cIdx {
            #expect(a < b)
            #expect(b < c)
        }
    }

    @Test func lastGlobalAccountWinsUserSection() {
        var first = Self.globalAccount()
        first.gitUserName = "first"
        first.gitUserEmail = "first@example.com"
        var second = Self.globalAccount()
        second = Account(
            id: UUID(),
            label: second.label,
            githubUsername: second.githubUsername,
            sshAlias: "github-second",
            keyPath: second.keyPath,
            keyFingerprint: nil,
            sshPort: .port443,
            gitUserName: "second",
            gitUserEmail: "second@example.com",
            scope: .global,
            urlRewrites: [],
            color: second.color,
            notes: "",
            createdAt: second.createdAt,
            updatedAt: second.updatedAt,
            lastUsedAt: nil
        )
        let output = AccountProjector.project([first, second], generatedAt: Self.fixedDate)
        #expect(output.gitConfig.contains("name = second"))
        #expect(!output.gitConfig.contains("name = first"))
    }

    // MARK: - Port 22 Host block

    @Test func port22AccountEmitsDirectHostBlock() {
        var account = Self.globalAccount()
        account = Account(
            id: account.id,
            label: account.label,
            githubUsername: account.githubUsername,
            sshAlias: account.sshAlias,
            keyPath: account.keyPath,
            keyFingerprint: nil,
            sshPort: .port22,
            gitUserName: account.gitUserName,
            gitUserEmail: account.gitUserEmail,
            scope: account.scope,
            urlRewrites: account.urlRewrites,
            color: account.color,
            notes: "",
            createdAt: account.createdAt,
            updatedAt: account.updatedAt,
            lastUsedAt: nil
        )
        let output = AccountProjector.project([account], generatedAt: Self.fixedDate)
        #expect(output.sshConfig.contains("HostName github.com"))
        #expect(output.sshConfig.contains("Port 22"))
        #expect(!output.sshConfig.contains("HostKeyAlias"))
        #expect(!output.sshConfig.contains("ssh.github.com"))
    }

    // MARK: - Disk write + reconcile

    @Test func writeAndReconcileRemovesStaleSubFiles() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-proj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let paths = AccountProjector.ManagedPaths(
            sshManaged: tmp.appendingPathComponent("ssh_config.managed").path,
            gitManaged: tmp.appendingPathComponent("gitconfig.managed").path,
            userSSHConfig: tmp.appendingPathComponent("dummy-ssh").path,
            userGitConfig: tmp.appendingPathComponent("dummy-git").path
        )
        let backups = BackupService(
            backupRoot: tmp.appendingPathComponent("backups"),
            retentionCount: 10
        )

        // Round 1: scoped account → creates sub file
        let scoped = Self.scopedAccount()
        let output1 = AccountProjector.project([scoped], paths: paths)
        try AccountProjector.write(output1, paths: paths, backups: backups)

        let subPath = paths.subFilePath(for: scoped.id)
        #expect(FileManager.default.fileExists(atPath: subPath))

        // Round 2: account removed → sub file should be gone
        let output2 = AccountProjector.project([], paths: paths)
        try AccountProjector.write(output2, paths: paths, backups: backups)
        #expect(!FileManager.default.fileExists(atPath: subPath))
    }
}
