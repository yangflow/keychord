import Testing
import Foundation
@testable import keychord

@Suite("IncludeInstaller")
struct IncludeInstallerTests {

    static func withTempRoot(_ test: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try test(root)
    }

    // MARK: - SSH install / uninstall

    @Test func installSSHIncludeInjectsBlockAtTop() throws {
        try Self.withTempRoot { root in
            let target = root.appendingPathComponent("sshconfig").path
            let managed = root.appendingPathComponent("ssh_config.managed").path

            let existing = "Host original\n  HostName example.com\n"
            try existing.write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.installSSHInclude(
                targetPath: target,
                managedPath: managed
            )

            let result = try String(contentsOfFile: target, encoding: .utf8)
            #expect(result.hasPrefix(IncludeInstaller.markerBegin))
            #expect(result.contains("Include \(managed)") || result.contains("Include ~"))
            #expect(result.contains("Host original"))
            #expect(result.contains(IncludeInstaller.markerEnd))
        }
    }

    @Test func installSSHIncludeIsIdempotent() throws {
        try Self.withTempRoot { root in
            let target = root.appendingPathComponent("sshconfig").path
            let managed = root.appendingPathComponent("ssh_config.managed").path
            try "Host foo\n".write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.installSSHInclude(
                targetPath: target,
                managedPath: managed
            )
            let after1 = try String(contentsOfFile: target, encoding: .utf8)

            try IncludeInstaller.installSSHInclude(
                targetPath: target,
                managedPath: managed
            )
            let after2 = try String(contentsOfFile: target, encoding: .utf8)

            #expect(after1 == after2)

            // Marker block should appear exactly once
            let beginCount = after2.components(separatedBy: IncludeInstaller.markerBegin).count - 1
            #expect(beginCount == 1)
        }
    }

    @Test func installSSHIncludeOnEmptyFileCreatesBlock() throws {
        try Self.withTempRoot { root in
            let target = root.appendingPathComponent("sshconfig").path
            let managed = root.appendingPathComponent("ssh_config.managed").path
            // No file exists yet
            try IncludeInstaller.installSSHInclude(
                targetPath: target,
                managedPath: managed
            )
            let result = try String(contentsOfFile: target, encoding: .utf8)
            #expect(result.contains(IncludeInstaller.markerBegin))
            #expect(result.contains(IncludeInstaller.markerEnd))
        }
    }

    @Test func uninstallSSHIncludePreservesRestOfFile() throws {
        try Self.withTempRoot { root in
            let target = root.appendingPathComponent("sshconfig").path
            let managed = root.appendingPathComponent("ssh_config.managed").path
            let userContent = "Host original\n  HostName example.com\n"
            try userContent.write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.installSSHInclude(
                targetPath: target,
                managedPath: managed
            )
            try IncludeInstaller.uninstallSSHInclude(
                targetPath: target
            )

            let result = try String(contentsOfFile: target, encoding: .utf8)
            #expect(result.contains("Host original"))
            #expect(!result.contains(IncludeInstaller.markerBegin))
            #expect(!result.contains(IncludeInstaller.markerEnd))
        }
    }

    @Test func uninstallOnUnmanagedFileIsNoOp() throws {
        try Self.withTempRoot { root in
            let target = root.appendingPathComponent("sshconfig").path
            let userContent = "Host original\n  HostName example.com\n"
            try userContent.write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.uninstallSSHInclude(
                targetPath: target
            )

            let result = try String(contentsOfFile: target, encoding: .utf8)
            #expect(result == userContent)
        }
    }

    @Test func uninstallUserIncludesStripsMarkersFromRealConfigFixtures() throws {
        try Self.withTempRoot { root in
            let sshTarget = root.appendingPathComponent("sshconfig").path
            let gitTarget = root.appendingPathComponent("gitconfig").path
            let sshManaged = root.appendingPathComponent("ssh_config.managed").path
            let gitManaged = root.appendingPathComponent("gitconfig.managed").path

            // Realistic hand-written bodies that must survive uninstall.
            let sshUser = """
            Include ~/.orbstack/ssh/config

            Host myserver
              HostName 203.0.113.10
              User deploy
              IdentityFile ~/.ssh/id_deploy

            """
            let gitUser = """
            [user]
            \tname = Alice
            \temail = alice@example.com
            [alias]
            \tst = status
            """
            try sshUser.write(toFile: sshTarget, atomically: true, encoding: .utf8)
            try gitUser.write(toFile: gitTarget, atomically: true, encoding: .utf8)

            try IncludeInstaller.installSSHInclude(
                targetPath: sshTarget,
                managedPath: sshManaged
            )
            try IncludeInstaller.installGitInclude(
                targetPath: gitTarget,
                managedPath: gitManaged
            )

            #expect(try String(contentsOfFile: sshTarget, encoding: .utf8)
                .contains(IncludeInstaller.markerBegin))
            #expect(try String(contentsOfFile: gitTarget, encoding: .utf8)
                .contains(IncludeInstaller.markerBegin))

            try IncludeInstaller.uninstallUserIncludes(
                sshConfigPath: sshTarget,
                gitConfigPath: gitTarget
            )

            let sshAfter = try String(contentsOfFile: sshTarget, encoding: .utf8)
            let gitAfter = try String(contentsOfFile: gitTarget, encoding: .utf8)

            #expect(!sshAfter.contains(IncludeInstaller.markerBegin))
            #expect(!sshAfter.contains(IncludeInstaller.markerEnd))
            #expect(!sshAfter.contains("ssh_config.managed"))
            #expect(sshAfter.contains("Host myserver"))
            #expect(sshAfter.contains("Include ~/.orbstack/ssh/config"))

            #expect(!gitAfter.contains(IncludeInstaller.markerBegin))
            #expect(!gitAfter.contains(IncludeInstaller.markerEnd))
            #expect(!gitAfter.contains("gitconfig.managed"))
            #expect(gitAfter.contains("name = Alice"))
            #expect(gitAfter.contains("st = status"))
        }
    }

    @Test func uninstallUserIncludesDoesNotTouchAccountsOrKeys() throws {
        try Self.withTempRoot { root in
            let sshTarget = root.appendingPathComponent("sshconfig").path
            let gitTarget = root.appendingPathComponent("gitconfig").path
            let sshManaged = root.appendingPathComponent("ssh_config.managed").path
            let gitManaged = root.appendingPathComponent("gitconfig.managed").path
            let accountsJSON = root.appendingPathComponent("accounts.json").path
            let privateKey = root.appendingPathComponent("id_ed25519").path

            try "Host x\n".write(toFile: sshTarget, atomically: true, encoding: .utf8)
            try "[user]\n\tname = a\n".write(toFile: gitTarget, atomically: true, encoding: .utf8)
            try #"{"accounts":[]}"#.write(toFile: accountsJSON, atomically: true, encoding: .utf8)
            try "PRIVATE KEY MATERIAL\n".write(toFile: privateKey, atomically: true, encoding: .utf8)

            try IncludeInstaller.installSSHInclude(
                targetPath: sshTarget,
                managedPath: sshManaged
            )
            try IncludeInstaller.installGitInclude(
                targetPath: gitTarget,
                managedPath: gitManaged
            )
            try IncludeInstaller.uninstallUserIncludes(
                sshConfigPath: sshTarget,
                gitConfigPath: gitTarget
            )

            #expect(FileManager.default.fileExists(atPath: accountsJSON))
            #expect(FileManager.default.fileExists(atPath: privateKey))
            #expect(try String(contentsOfFile: accountsJSON, encoding: .utf8) == #"{"accounts":[]}"#)
            #expect(try String(contentsOfFile: privateKey, encoding: .utf8) == "PRIVATE KEY MATERIAL\n")
        }
    }

    // MARK: - Git install / uninstall

    @Test func installGitIncludeInjectsIncludeSection() throws {
        try Self.withTempRoot { root in
            let target = root.appendingPathComponent("gitconfig").path
            let managed = root.appendingPathComponent("gitconfig.managed").path
            try "[user]\n\tname = alice\n".write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.installGitInclude(
                targetPath: target,
                managedPath: managed
            )

            let result = try String(contentsOfFile: target, encoding: .utf8)
            #expect(result.contains(IncludeInstaller.markerBegin))
            #expect(result.contains("[include]"))
            #expect(result.contains("path ="))
            #expect(result.contains("name = alice"))
            // Git include must appear AFTER existing content so includeIf
            // overrides earlier [user] values (last-write-wins in git).
            let userRange = result.range(of: "name = alice")!
            let markerRange = result.range(of: IncludeInstaller.markerBegin)!
            #expect(userRange.lowerBound < markerRange.lowerBound)
        }
    }

    @Test func installGitIncludeIsIdempotent() throws {
        try Self.withTempRoot { root in
            let target = root.appendingPathComponent("gitconfig").path
            let managed = root.appendingPathComponent("gitconfig.managed").path
            try "".write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.installGitInclude(
                targetPath: target,
                managedPath: managed
            )
            try IncludeInstaller.installGitInclude(
                targetPath: target,
                managedPath: managed
            )
            let result = try String(contentsOfFile: target, encoding: .utf8)
            let beginCount = result.components(separatedBy: IncludeInstaller.markerBegin).count - 1
            #expect(beginCount == 1)
        }
    }

    @Test func uninstallGitIncludePreservesRestOfFile() throws {
        try Self.withTempRoot { root in
            let target = root.appendingPathComponent("gitconfig").path
            let managed = root.appendingPathComponent("gitconfig.managed").path
            let userContent = "[user]\n\tname = alice\n\temail = a@example.com\n"
            try userContent.write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.installGitInclude(
                targetPath: target,
                managedPath: managed
            )
            try IncludeInstaller.uninstallGitInclude(targetPath: target)

            let result = try String(contentsOfFile: target, encoding: .utf8)
            #expect(result.contains("name = alice"))
            #expect(result.contains("email = a@example.com"))
            #expect(!result.contains(IncludeInstaller.markerBegin))
            #expect(!result.contains(IncludeInstaller.markerEnd))
            #expect(!result.contains("[include]"))
        }
    }

    // MARK: - Pure stripMarkerBlock

    @Test func stripMarkerBlockRemovesEntireBlock() {
        let text = """
        \(IncludeInstaller.markerBegin)
        Include /tmp/foo
        \(IncludeInstaller.markerEnd)

        Host rest
          HostName example.com
        """
        let cleaned = IncludeInstaller.stripMarkerBlock(text)
        #expect(cleaned.contains("Host rest"))
        #expect(!cleaned.contains(IncludeInstaller.markerBegin))
        #expect(!cleaned.contains(IncludeInstaller.markerEnd))
        #expect(!cleaned.contains("Include /tmp/foo"))
    }

    @Test func stripMarkerBlockLeavesFileUntouchedIfNoMarker() {
        let text = "Host foo\n  HostName bar\n"
        #expect(IncludeInstaller.stripMarkerBlock(text) == text)
    }
}
