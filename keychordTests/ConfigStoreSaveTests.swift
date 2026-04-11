import Testing
import Foundation
@testable import keychord

@Suite("ConfigStore save")
struct ConfigStoreSaveTests {

    static func withTempRoot(
        _ test: (BackupService, URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-save-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let backupRoot = root.appendingPathComponent("backups")
        let service = BackupService(backupRoot: backupRoot, retentionCount: 10)
        try test(service, root)
    }

    // MARK: - saveSSHConfig

    @Test func saveSSHConfigWritesByteIdentical() throws {
        try Self.withTempRoot { backups, root in
            let source = """
            Host github.com
              HostName ssh.github.com
              Port 443
              User git
              IdentityFile ~/.ssh/id_ed25519

            Host github-work
              HostName ssh.github.com
              Port 443
              User git
              IdentityFile ~/.ssh/id_rsa
            """
            let target = root.appendingPathComponent("ssh_config").path

            let doc = SSHConfigDocument.parse(source)
            try ConfigStore.saveSSHConfig(doc, to: target, backups: backups)

            let written = try String(contentsOfFile: target, encoding: .utf8)
            #expect(written == source)
        }
    }

    @Test func saveSSHConfigBacksUpExistingFile() throws {
        try Self.withTempRoot { backups, root in
            let target = root.appendingPathComponent("ssh_config").path
            try "Host old\n  HostName old.example\n".write(
                toFile: target, atomically: true, encoding: .utf8
            )

            var doc = SSHConfigDocument.parse("Host new\n  HostName new.example\n")
            doc.setField("Port", to: "22", forHost: "new")
            try ConfigStore.saveSSHConfig(doc, to: target, backups: backups)

            let records = try backups.list(for: target)
            #expect(records.count == 1)
            let backupContent = try String(contentsOfFile: records[0].backupPath, encoding: .utf8)
            #expect(backupContent == "Host old\n  HostName old.example\n")

            let writtenContent = try String(contentsOfFile: target, encoding: .utf8)
            #expect(writtenContent.contains("Host new"))
            #expect(writtenContent.contains("Port 22"))
        }
    }

    @Test func saveSSHConfigFirstTimeCreateSkipsBackup() throws {
        try Self.withTempRoot { backups, root in
            let target = root.appendingPathComponent("ssh_config").path
            #expect(!FileManager.default.fileExists(atPath: target))

            let doc = SSHConfigDocument.parse("Host foo\n  HostName bar\n")
            try ConfigStore.saveSSHConfig(doc, to: target, backups: backups)

            #expect(FileManager.default.fileExists(atPath: target))
            let records = try backups.list(for: target)
            #expect(records.isEmpty)
        }
    }

    @Test func saveSSHConfigPreservesCommentsAfterEdit() throws {
        try Self.withTempRoot { backups, root in
            let source = """
            # Personal GitHub
            Host github.com
              HostName ssh.github.com
              Port 443
              # key for yangflow
              IdentityFile ~/.ssh/id_ed25519
            """
            let target = root.appendingPathComponent("ssh_config").path
            try source.write(toFile: target, atomically: true, encoding: .utf8)

            var doc = SSHConfigDocument.parse(source)
            doc.setField("Port", to: "22", forHost: "github.com")
            try ConfigStore.saveSSHConfig(doc, to: target, backups: backups)

            let written = try String(contentsOfFile: target, encoding: .utf8)
            #expect(written.contains("# Personal GitHub"))
            #expect(written.contains("# key for yangflow"))
            #expect(written.contains("Port 22"))
            #expect(!written.contains("Port 443"))
        }
    }

    // MARK: - modifyGitConfig

    @Test func modifyGitConfigBacksUpThenMutates() throws {
        try Self.withTempRoot { backups, root in
            let target = root.appendingPathComponent("gitconfig").path
            try "[user]\n\tname = alice\n\temail = a@example.com\n".write(
                toFile: target, atomically: true, encoding: .utf8
            )

            try ConfigStore.modifyGitConfig(at: target, backups: backups) { io in
                try io.set("user.name", to: "bob")
            }

            let io = GitConfigIO(filePath: target)
            let model = try io.extractModel()
            #expect(model.identity?.name == "bob")

            let records = try backups.list(for: target)
            #expect(records.count == 1)
            let backed = try String(contentsOfFile: records[0].backupPath, encoding: .utf8)
            #expect(backed.contains("alice"))
        }
    }

    @Test func modifyGitConfigFirstTimeCreateSkipsBackup() throws {
        try Self.withTempRoot { backups, root in
            let target = root.appendingPathComponent("gitconfig").path
            #expect(!FileManager.default.fileExists(atPath: target))

            try ConfigStore.modifyGitConfig(at: target, backups: backups) { io in
                try io.set("user.name", to: "new")
            }

            let records = try backups.list(for: target)
            #expect(records.isEmpty)

            let io = GitConfigIO(filePath: target)
            let entries = try io.listAll()
            #expect(entries.contains(GitConfigIO.Entry(key: "user.name", value: "new")))
        }
    }
}
