import Testing
import Foundation
@testable import keychord

@Suite("IncludeInstaller")
struct IncludeInstallerTests {

    static func withTempRoot(_ test: (URL, BackupService) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backups = BackupService(
            backupRoot: root.appendingPathComponent("backups"),
            retentionCount: 10
        )
        try test(root, backups)
    }

    // MARK: - SSH install / uninstall

    @Test func installSSHIncludeInjectsBlockAtTop() throws {
        try Self.withTempRoot { root, backups in
            let target = root.appendingPathComponent("sshconfig").path
            let managed = root.appendingPathComponent("ssh_config.managed").path

            let existing = "Host original\n  HostName example.com\n"
            try existing.write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.installSSHInclude(
                targetPath: target,
                managedPath: managed,
                backups: backups
            )

            let result = try String(contentsOfFile: target, encoding: .utf8)
            #expect(result.hasPrefix(IncludeInstaller.markerBegin))
            #expect(result.contains("Include \(managed)") || result.contains("Include ~"))
            #expect(result.contains("Host original"))
            #expect(result.contains(IncludeInstaller.markerEnd))
        }
    }

    @Test func installSSHIncludeIsIdempotent() throws {
        try Self.withTempRoot { root, backups in
            let target = root.appendingPathComponent("sshconfig").path
            let managed = root.appendingPathComponent("ssh_config.managed").path
            try "Host foo\n".write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.installSSHInclude(
                targetPath: target,
                managedPath: managed,
                backups: backups
            )
            let after1 = try String(contentsOfFile: target, encoding: .utf8)

            try IncludeInstaller.installSSHInclude(
                targetPath: target,
                managedPath: managed,
                backups: backups
            )
            let after2 = try String(contentsOfFile: target, encoding: .utf8)

            #expect(after1 == after2)

            // Marker block should appear exactly once
            let beginCount = after2.components(separatedBy: IncludeInstaller.markerBegin).count - 1
            #expect(beginCount == 1)
        }
    }

    @Test func installSSHIncludeOnEmptyFileCreatesBlock() throws {
        try Self.withTempRoot { root, backups in
            let target = root.appendingPathComponent("sshconfig").path
            let managed = root.appendingPathComponent("ssh_config.managed").path
            // No file exists yet
            try IncludeInstaller.installSSHInclude(
                targetPath: target,
                managedPath: managed,
                backups: backups
            )
            let result = try String(contentsOfFile: target, encoding: .utf8)
            #expect(result.contains(IncludeInstaller.markerBegin))
            #expect(result.contains(IncludeInstaller.markerEnd))
        }
    }

    @Test func uninstallSSHIncludePreservesRestOfFile() throws {
        try Self.withTempRoot { root, backups in
            let target = root.appendingPathComponent("sshconfig").path
            let managed = root.appendingPathComponent("ssh_config.managed").path
            let userContent = "Host original\n  HostName example.com\n"
            try userContent.write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.installSSHInclude(
                targetPath: target,
                managedPath: managed,
                backups: backups
            )
            try IncludeInstaller.uninstallSSHInclude(
                targetPath: target,
                backups: backups
            )

            let result = try String(contentsOfFile: target, encoding: .utf8)
            #expect(result.contains("Host original"))
            #expect(!result.contains(IncludeInstaller.markerBegin))
            #expect(!result.contains(IncludeInstaller.markerEnd))
        }
    }

    @Test func uninstallOnUnmanagedFileIsNoOp() throws {
        try Self.withTempRoot { root, backups in
            let target = root.appendingPathComponent("sshconfig").path
            let userContent = "Host original\n  HostName example.com\n"
            try userContent.write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.uninstallSSHInclude(
                targetPath: target,
                backups: backups
            )

            let result = try String(contentsOfFile: target, encoding: .utf8)
            #expect(result == userContent)
        }
    }

    // MARK: - Git install / uninstall

    @Test func installGitIncludeInjectsIncludeSection() throws {
        try Self.withTempRoot { root, backups in
            let target = root.appendingPathComponent("gitconfig").path
            let managed = root.appendingPathComponent("gitconfig.managed").path
            try "[user]\n\tname = alice\n".write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.installGitInclude(
                targetPath: target,
                managedPath: managed,
                backups: backups
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
        try Self.withTempRoot { root, backups in
            let target = root.appendingPathComponent("gitconfig").path
            let managed = root.appendingPathComponent("gitconfig.managed").path
            try "".write(toFile: target, atomically: true, encoding: .utf8)

            try IncludeInstaller.installGitInclude(
                targetPath: target,
                managedPath: managed,
                backups: backups
            )
            try IncludeInstaller.installGitInclude(
                targetPath: target,
                managedPath: managed,
                backups: backups
            )
            let result = try String(contentsOfFile: target, encoding: .utf8)
            let beginCount = result.components(separatedBy: IncludeInstaller.markerBegin).count - 1
            #expect(beginCount == 1)
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
