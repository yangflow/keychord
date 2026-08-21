import Testing
import Foundation
@testable import keychord

@Suite("Fixer")
struct FixerTests {

    static func withTempRoot(_ test: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-fixer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await test(root)
    }

    static let dupConfig = """
    Host github.com
      HostName ssh.github.com
      Port 443
      User git
      IdentityFile ~/.ssh/id_ed25519
      IdentitiesOnly yes
      HostKeyAlias github.com

    Host github-yangflow
      HostName ssh.github.com
      Port 443
      User git
      IdentityFile ~/.ssh/id_ed25519
      IdentitiesOnly yes
      HostKeyAlias github.com
    """

    // MARK: - SSH001

    @Test func ssh001RemovesOneDuplicate() async throws {
        try await Self.withTempRoot { root in
            let sshPath = root.appendingPathComponent("sshconfig").path
            let gitPath = root.appendingPathComponent("gitconfig").path
            try Self.dupConfig.write(toFile: sshPath, atomically: true, encoding: .utf8)
            try "".write(toFile: gitPath, atomically: true, encoding: .utf8)

            try await Fixer.execute(
                .ssh001_removeHost(alias: "github-yangflow"),
                sshConfigPath: sshPath,
                gitConfigPath: gitPath
            )

            let text = try String(contentsOfFile: sshPath, encoding: .utf8)
            #expect(text.contains("Host github.com"))
            #expect(!text.contains("Host github-yangflow"))
        }
    }

    @Test func ssh001ThrowsForUnknownAlias() async throws {
        try await Self.withTempRoot { root in
            let sshPath = root.appendingPathComponent("sshconfig").path
            let gitPath = root.appendingPathComponent("gitconfig").path
            try "Host foo\n  HostName bar\n".write(toFile: sshPath, atomically: true, encoding: .utf8)
            try "".write(toFile: gitPath, atomically: true, encoding: .utf8)

            do {
                try await Fixer.execute(
                    .ssh001_removeHost(alias: "nope"),
                    sshConfigPath: sshPath,
                    gitConfigPath: gitPath
                )
                Issue.record("Expected hostNotFound, got success")
            } catch let Fixer.FixError.hostNotFound(alias) {
                #expect(alias == "nope")
            } catch {
                Issue.record("Expected hostNotFound, got \(error)")
            }
        }
    }

    // MARK: - SSH003

    @Test func ssh003AddsHostKeyAlias() async throws {
        try await Self.withTempRoot { root in
            let sshPath = root.appendingPathComponent("sshconfig").path
            let gitPath = root.appendingPathComponent("gitconfig").path
            let before = """
            Host gh
              HostName ssh.github.com
              Port 443
            """
            try before.write(toFile: sshPath, atomically: true, encoding: .utf8)
            try "".write(toFile: gitPath, atomically: true, encoding: .utf8)

            try await Fixer.execute(
                .ssh003_addHostKeyAlias(alias: "gh"),
                sshConfigPath: sshPath,
                gitConfigPath: gitPath
            )

            let after = try String(contentsOfFile: sshPath, encoding: .utf8)
            #expect(after.contains("HostKeyAlias github.com"))
            #expect(after.contains("Host gh"))
            #expect(after.contains("HostName ssh.github.com"))
        }
    }

    // MARK: - GIT001 re-project managed files

    @Test func git001RewritesManagedFilesForEveryGitdirPath() async throws {
        try await Self.withTempRoot { root in
            let paths = AccountProjector.ManagedPaths(
                sshManaged: root.appendingPathComponent("ssh_config.managed").path,
                gitManaged: root.appendingPathComponent("gitconfig.managed").path,
                userSSHConfig: root.appendingPathComponent("user-ssh").path,
                userGitConfig: root.appendingPathComponent("user-git").path
            )
            let account = Account.new(
                label: "work",
                sshAlias: "github-work",
                keyPath: "~/.ssh/id_work",
                gitUserName: "Work",
                gitUserEmail: "work@company.com",
                scope: .gitdir(paths: ["~/work/", "~/src/new-app/"])
            )

            try await Fixer.execute(
                .git001_reprojectManagedFiles,
                sshConfigPath: paths.userSSHConfig,
                gitConfigPath: paths.userGitConfig,
                accounts: [account],
                managedPaths: paths
            )

            let git = try String(contentsOfFile: paths.gitManaged, encoding: .utf8)
            #expect(git.contains("[includeIf \"gitdir:~/work/\"]"))
            #expect(git.contains("[includeIf \"gitdir:~/src/new-app/\"]"))

            let ssh = try String(contentsOfFile: paths.sshManaged, encoding: .utf8)
            #expect(ssh.contains("Host github-work"))

            // Include lines land in the user files the fix was pointed at.
            let userGit = try String(contentsOfFile: paths.userGitConfig, encoding: .utf8)
            #expect(userGit.contains("gitconfig.managed"))
        }
    }
}
