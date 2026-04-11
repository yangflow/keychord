import Testing
import Foundation
@testable import keychord

@Suite("AccountImporter")
struct AccountImporterTests {

    // MARK: - Fixture matching the user's real ~/.ssh/config + ~/.gitconfig

    static func userLikeModel() -> ConfigModel {
        var model = ConfigModel()

        model.sshHosts = [
            SSHHost(
                alias: "github.com",
                hostName: "ssh.github.com",
                port: 443,
                user: "git",
                identityFile: "~/.ssh/id_ed25519",
                identitiesOnly: true,
                hostKeyAlias: "github.com"
            ),
            SSHHost(
                alias: "github-yangflow",
                hostName: "ssh.github.com",
                port: 443,
                user: "git",
                identityFile: "~/.ssh/id_ed25519",
                identitiesOnly: true,
                hostKeyAlias: "github.com"
            ),
            SSHHost(
                alias: "github-work",
                hostName: "ssh.github.com",
                port: 443,
                user: "git",
                identityFile: "~/.ssh/id_rsa",
                identitiesOnly: true,
                hostKeyAlias: "github.com"
            )
        ]

        model.gitIdentities = [
            GitIdentity(
                name: "yangflow",
                email: "ydongy02@gmail.com",
                sourceFile: "~/.gitconfig",
                includeCondition: nil,
                sshCommand: nil
            ),
            GitIdentity(
                name: "bob",
                email: "bob@example.com",
                sourceFile: "~/.gitconfig-work",
                includeCondition: "gitdir:~/work/",
                sshCommand: "ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes"
            )
        ]

        model.insteadOfRules = [
            InsteadOfRule(
                from: "https://github.com/acme-corp/",
                to: "git@github-work:acme-corp/",
                sourceFile: "~/.gitconfig",
                direction: .insteadOf
            ),
            InsteadOfRule(
                from: "https://github.com/",
                to: "git@github.com:",
                sourceFile: "~/.gitconfig",
                direction: .insteadOf
            )
        ]

        return model
    }

    // MARK: - Empty

    @Test func emptyModelYieldsNoRecords() {
        #expect(AccountImporter.importFromExistingConfig(ConfigModel()).isEmpty)
    }

    // MARK: - User's real shape

    @Test func userShapeYieldsTwoRecords() {
        let records = AccountImporter.importFromExistingConfig(Self.userLikeModel())
        #expect(records.count == 2)

        let personal = records.first { $0.gitUserName == "yangflow" }
        let work = records.first { $0.gitUserName == "bob" }
        #expect(personal != nil)
        #expect(work != nil)

        // Primary alias is the first one the merger encountered.
        #expect(personal?.sshAlias == "github.com")
        #expect(personal?.scope == .global)
        #expect(personal?.label == "yangflow")
        #expect(personal?.sshPort == .port443)
        #expect(personal?.urlRewrites.contains { $0.to == "git@github.com:" } == true)

        #expect(work?.sshAlias == "github-work")
        #expect(work?.sshPort == .port443)
        if case .gitdir(let dir) = work?.scope {
            #expect(dir == "~/work/")
        } else {
            Issue.record("work account should be .gitdir scoped")
        }
        #expect(work?.urlRewrites.count == 1)
        #expect(work?.urlRewrites.first?.to == "git@github-work:acme-corp/")
    }

    // MARK: - Label fallback

    @Test func labelFallsBackToAliasWhenIdentityMissing() {
        var model = ConfigModel()
        model.sshHosts = [
            SSHHost(alias: "keyless", hostName: "example.com")
        ]
        let records = AccountImporter.importFromExistingConfig(model)
        #expect(records.count == 1)
        #expect(records[0].label == "keyless")
        #expect(records[0].gitUserName == "")
        #expect(records[0].gitUserEmail == "")
        #expect(records[0].keyPath == "")
    }

    // MARK: - Merge

    @Test func hostsSharingKeyAndIdentityMergeIntoOneRecord() {
        let records = AccountImporter.importFromExistingConfig(Self.userLikeModel())
        let personal = records.first { $0.gitUserName == "yangflow" }
        // github.com + github-yangflow share the same key + global
        // identity and should collapse to a single Account.
        #expect(personal?.sshAlias == "github.com")
        #expect(records.count == 2)
    }

    // MARK: - Default-host fallback

    @Test func defaultHostFallbackBindsGlobalIdentity() {
        var model = ConfigModel()
        model.sshHosts = [
            SSHHost(
                alias: "github.com",
                hostName: "github.com",
                identityFile: "~/.ssh/id_ed25519"
            )
        ]
        model.gitIdentities = [
            GitIdentity(
                name: "alice",
                email: "alice@example.com",
                sourceFile: "~/.gitconfig",
                includeCondition: nil,
                sshCommand: nil
            )
        ]
        let records = AccountImporter.importFromExistingConfig(model)
        #expect(records.count == 1)
        #expect(records[0].gitUserName == "alice")
        #expect(records[0].scope == .global)
        #expect(records[0].sshPort == .port22)
    }

    // MARK: - Port detection

    @Test func port22DetectedFromExplicitPort() {
        var model = ConfigModel()
        model.sshHosts = [
            SSHHost(
                alias: "github-work",
                hostName: "github.com",
                port: 22,
                user: "git",
                identityFile: "~/.ssh/id_work"
            )
        ]
        let records = AccountImporter.importFromExistingConfig(model)
        #expect(records.count == 1)
        #expect(records[0].sshPort == .port22)
    }

    // MARK: - Deterministic color rotation + fresh UUIDs

    @Test func assignsRoundRobinColorsAndUniqueIDs() {
        var model = ConfigModel()
        model.sshHosts = (0..<8).map { i in
            SSHHost(alias: "host-\(i)", identityFile: "~/.ssh/key_\(i)")
        }
        let records = AccountImporter.importFromExistingConfig(model)
        let palette = Account.AccountColor.allCases
        #expect(records.count == 8)
        #expect(records[0].color == palette[0])
        // colorIndex wraps
        #expect(records[palette.count % records.count].color == palette[0])

        let ids = Set(records.map(\.id))
        #expect(ids.count == records.count)

        // A re-import produces different UUIDs.
        let second = AccountImporter.importFromExistingConfig(model)
        let firstIDs = Set(records.map(\.id))
        let secondIDs = Set(second.map(\.id))
        #expect(firstIDs.isDisjoint(with: secondIDs))
    }
}
