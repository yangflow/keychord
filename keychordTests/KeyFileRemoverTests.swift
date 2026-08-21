import Testing
import Foundation
@testable import keychord

@Suite("KeyFileRemover")
struct KeyFileRemoverTests {

    static func withTempDir(_ test: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-keyfile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try test(dir)
    }

    static func account(
        label: String = "work",
        keyPath: String,
        scope: Account.Scope = .gitdir(paths: ["~/work/", "~/src/new-app/"])
    ) -> Account {
        Account.new(
            label: label,
            sshAlias: "github-work",
            keyPath: keyPath,
            gitUserName: "Work",
            gitUserEmail: "work@company.com",
            scope: scope
        )
    }

    // MARK: - Leftovers

    @Test func leftoversListTheKeyAndEveryGitdirPath() throws {
        try Self.withTempDir { dir in
            let key = dir.appendingPathComponent("id_work")
            try "private".write(to: key, atomically: true, encoding: .utf8)

            let account = Self.account(keyPath: key.path)
            let leftovers = KeyFileRemover.leftovers(for: account, in: [account])

            #expect(leftovers.privateKeyPath == key.path)
            #expect(leftovers.gitdirPaths == ["~/work/", "~/src/new-app/"])
            #expect(leftovers.canRemoveKey)
            #expect(leftovers.keyRemovalBlocker == nil)
        }
    }

    @Test func leftoversDropBlankGitdirEntries() throws {
        try Self.withTempDir { dir in
            let key = dir.appendingPathComponent("id_work")
            try "private".write(to: key, atomically: true, encoding: .utf8)
            let account = Self.account(
                keyPath: key.path,
                scope: .gitdir(paths: ["", "  ", "~/work/"])
            )
            #expect(KeyFileRemover.leftovers(for: account, in: [account]).gitdirPaths == ["~/work/"])
        }
    }

    @Test func globalAccountHasNoGitdirLeftovers() throws {
        try Self.withTempDir { dir in
            let key = dir.appendingPathComponent("id_work")
            try "private".write(to: key, atomically: true, encoding: .utf8)
            let account = Self.account(keyPath: key.path, scope: .global)
            #expect(KeyFileRemover.leftovers(for: account, in: [account]).gitdirPaths.isEmpty)
        }
    }

    // MARK: - Blockers

    @Test func accountWithoutAKeyCannotOptIn() {
        let account = Self.account(keyPath: "")
        let leftovers = KeyFileRemover.leftovers(for: account, in: [account])
        #expect(leftovers.keyRemovalBlocker == .noKeyPath)
        #expect(!leftovers.canRemoveKey)
    }

    @Test func missingKeyFileIsReported() {
        let path = "/tmp/keychord-absent-\(UUID().uuidString)"
        let account = Self.account(keyPath: path)
        #expect(
            KeyFileRemover.keyRemovalBlocker(for: account, in: [account]) == .missing(path)
        )
    }

    @Test func symlinkedKeyIsRefused() throws {
        try Self.withTempDir { dir in
            let real = dir.appendingPathComponent("real_key")
            try "private".write(to: real, atomically: true, encoding: .utf8)
            let link = dir.appendingPathComponent("linked_key")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

            let account = Self.account(keyPath: link.path)
            #expect(
                KeyFileRemover.keyRemovalBlocker(for: account, in: [account])
                    == .symlink(link.path)
            )
            #expect(throws: KeyFileRemover.RemoveError.self) {
                try KeyFileRemover.removePrivateKey(of: account, in: [account])
            }
            #expect(FileManager.default.fileExists(atPath: real.path))
        }
    }

    @Test func directoryPathIsNotAKeyFile() throws {
        try Self.withTempDir { dir in
            let account = Self.account(keyPath: dir.path)
            #expect(
                KeyFileRemover.keyRemovalBlocker(for: account, in: [account])
                    == .notARegularFile(dir.path)
            )
        }
    }

    @Test func keySharedWithAnotherAccountIsKept() throws {
        try Self.withTempDir { dir in
            let key = dir.appendingPathComponent("shared_key")
            try "private".write(to: key, atomically: true, encoding: .utf8)

            let work = Self.account(label: "work", keyPath: key.path)
            let personal = Self.account(label: "personal", keyPath: key.path)

            #expect(
                KeyFileRemover.keyRemovalBlocker(for: work, in: [work, personal])
                    == .sharedWith(["personal"])
            )
            #expect(throws: KeyFileRemover.RemoveError.self) {
                try KeyFileRemover.removePrivateKey(of: work, in: [work, personal])
            }
            #expect(FileManager.default.fileExists(atPath: key.path))
        }
    }

    @Test func tildeAndAbsolutePathsCountAsTheSameSharedKey() {
        let work = Self.account(label: "work", keyPath: "~/.ssh/id_shared")
        let personal = Self.account(
            label: "personal",
            keyPath: "\(NSHomeDirectory())/.ssh/id_shared"
        )
        #expect(
            KeyFileRemover.keyRemovalBlocker(for: work, in: [work, personal])
                == .sharedWith(["personal"])
        )
    }

    // MARK: - Removal

    @Test func optingInRemovesOnlyThePrivateKey() throws {
        try Self.withTempDir { dir in
            let key = dir.appendingPathComponent("id_work")
            let pub = dir.appendingPathComponent("id_work.pub")
            try "private".write(to: key, atomically: true, encoding: .utf8)
            try "ssh-ed25519 AAAA you@example.com".write(to: pub, atomically: true, encoding: .utf8)

            let account = Self.account(keyPath: key.path)
            try KeyFileRemover.removePrivateKey(of: account, in: [])

            #expect(!FileManager.default.fileExists(atPath: key.path))
            // The public half holds no secret and is left for the user.
            #expect(FileManager.default.fileExists(atPath: pub.path))
        }
    }

    @Test func removingAMissingKeyThrowsBlocked() {
        let account = Self.account(keyPath: "/tmp/keychord-absent-\(UUID().uuidString)")
        do {
            try KeyFileRemover.removePrivateKey(of: account, in: [])
            Issue.record("Expected a blocked error")
        } catch let error as KeyFileRemover.RemoveError {
            guard case .blocked(.missing) = error else {
                Issue.record("Expected .blocked(.missing), got \(error)")
                return
            }
        } catch {
            Issue.record("Expected KeyFileRemover.RemoveError, got \(error)")
        }
    }
}
