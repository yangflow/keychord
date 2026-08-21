import Testing
import Foundation
@testable import keychord

@Suite("BackupService")
struct BackupServiceTests {

    // MARK: - Fixture helper

    static func withTempRoot(
        retention: Int = 10,
        _ test: (BackupService, URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-backup-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let backupRoot = root.appendingPathComponent("backups")
        let service = BackupService(backupRoot: backupRoot, retentionCount: retention)
        try test(service, root)
    }

    static func writeFile(_ content: String, at url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Timestamp helpers

    @Test func formatAndParseTimestampRoundTrip() {
        let original = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00:00 UTC
        let s = BackupService.formatTimestamp(original)
        #expect(s.count == 15)
        #expect(s[s.index(s.startIndex, offsetBy: 8)] == "-")

        let parsed = BackupService.parseTimestamp(s)
        #expect(parsed != nil)
        #expect(parsed?.timeIntervalSince1970 == 1_800_000_000)
    }

    @Test func parseTimestampRejectsBadInput() {
        #expect(BackupService.parseTimestamp("") == nil)
        #expect(BackupService.parseTimestamp("not-a-date") == nil)
        #expect(BackupService.parseTimestamp("20260411T153000") == nil) // wrong separator
    }

    @Test func backupBaseNameStripsLeadingDot() {
        #expect(BackupService.backupBaseName(for: "/home/u/.gitconfig") == "gitconfig")
        #expect(BackupService.backupBaseName(for: "/home/u/.ssh/config") == "config")
        #expect(BackupService.backupBaseName(for: "/home/u/.gitconfig-work") == "gitconfig-work")
        #expect(BackupService.backupBaseName(for: "/tmp/plain.txt") == "plain.txt")
    }

    // MARK: - backup()

    @Test func backupCreatesCopyAndReturnsRecord() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("gitconfig")
            try Self.writeFile("name = alice\n", at: source)

            let record = try service.backup(originalPath: source.path)
            #expect(FileManager.default.fileExists(atPath: record.backupPath))
            let contents = try String(contentsOfFile: record.backupPath, encoding: .utf8)
            #expect(contents == "name = alice\n")
        }
    }

    @Test func backupCreatesBackupRootIfMissing() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("config")
            try Self.writeFile("Host foo\n", at: source)

            _ = try service.backup(originalPath: source.path)
            #expect(FileManager.default.fileExists(atPath: service.backupRoot.path))
        }
    }

    @Test func backupOfMissingSourceThrows() throws {
        try Self.withTempRoot { service, root in
            let bogus = root.appendingPathComponent("does-not-exist").path
            #expect(throws: BackupError.self) {
                try service.backup(originalPath: bogus)
            }
        }
    }

    @Test func backupCollisionAppendsSuffix() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("config")
            try Self.writeFile("x\n", at: source)

            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let r1 = try service.backup(originalPath: source.path, at: date)
            let r2 = try service.backup(originalPath: source.path, at: date)

            #expect(r1.backupPath != r2.backupPath)
            #expect(FileManager.default.fileExists(atPath: r1.backupPath))
            #expect(FileManager.default.fileExists(atPath: r2.backupPath))
        }
    }

    // MARK: - list()

    @Test func listEmptyWhenNoBackupsExist() throws {
        try Self.withTempRoot { service, root in
            let records = try service.list(for: "/any/path/config")
            #expect(records.isEmpty)
        }
    }

    @Test func listSortsNewestFirst() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("config")
            try Self.writeFile("x\n", at: source)

            let dates = [
                Date(timeIntervalSince1970: 1_800_000_000),
                Date(timeIntervalSince1970: 1_800_000_120),
                Date(timeIntervalSince1970: 1_800_000_060)
            ]
            for d in dates {
                _ = try service.backup(originalPath: source.path, at: d)
            }

            let records = try service.list(for: source.path)
            #expect(records.count == 3)
            #expect(records[0].timestamp.timeIntervalSince1970 == 1_800_000_120)
            #expect(records[1].timestamp.timeIntervalSince1970 == 1_800_000_060)
            #expect(records[2].timestamp.timeIntervalSince1970 == 1_800_000_000)
        }
    }

    @Test func listEntriesSummarizesAccountsJson() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("accounts.json")

            let work = Account(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                label: "work",
                username: "alice",
                provider: .github,
                sshAlias: "gh-work",
                keyPath: "/Users/demo/.ssh/id_ed25519_work",
                keyFingerprint: nil,
                sshPort: .port443,
                gitUserName: "Alice",
                gitUserEmail: "alice@example.com",
                scope: .global,
                urlRewrites: [
                    Account.URLRewrite(from: "https://github.com/", to: "git@gh-work:")
                ],
                color: .blue,
                notes: "",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastUsedAt: nil
            )
            let personal = Account(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                label: "",
                username: "bob",
                provider: .gitlab,
                sshAlias: "gh-b",
                keyPath: "/Users/demo/.ssh/id_ed25519_b",
                keyFingerprint: nil,
                sshPort: .port22,
                gitUserName: "Bob",
                gitUserEmail: "bob@example.com",
                scope: .gitdir("~/work/"),
                urlRewrites: [],
                color: .green,
                notes: "",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastUsedAt: nil
            )

            struct Envelope: Encodable {
                var version: Int
                var accounts: [Account]
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Envelope(version: 1, accounts: [work, personal]))
            try data.write(to: source)

            let date = Date(timeIntervalSince1970: 1_800_000_000)
            _ = try service.backup(originalPath: source.path, at: date)

            let entries = try service.listEntries(for: source.path)
            #expect(entries.count == 1)
            #expect(entries[0].accountCount == 2)
            #expect(entries[0].labels == ["work", ""])
            #expect(entries[0].byteCount != nil)
            #expect((entries[0].byteCount ?? 0) > 0)
            #expect(entries[0].isReadable)
            #expect(entries[0].accounts.count == 2)

            let previewWork = entries[0].accounts[0]
            #expect(previewWork.label == "work")
            #expect(previewWork.gitUserName == "Alice")
            #expect(previewWork.gitUserEmail == "alice@example.com")
            #expect(previewWork.sshAlias == "gh-work")
            #expect(previewWork.provider == .github)
            #expect(previewWork.sshPort == .port443)
            #expect(previewWork.keyPath.hasSuffix("id_ed25519_work"))
            #expect(previewWork.scope == .global)
            #expect(previewWork.urlRewrites.count == 1)

            let unnamed = entries[0].accounts[1]
            #expect(unnamed.label.isEmpty)
            #expect(unnamed.provider == .gitlab)
            #expect(unnamed.sshPort == .port22)
            #expect(unnamed.scope == .gitdir("~/work/"))
            #expect(unnamed.urlRewrites.isEmpty)
        }
    }

    @Test func listEntriesMarksUnreadableSnapshots() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("accounts.json")
            try Self.writeFile("not-json\n", at: source)

            _ = try service.backup(
                originalPath: source.path,
                at: Date(timeIntervalSince1970: 1_800_000_000)
            )

            let entries = try service.listEntries(for: source.path)
            #expect(entries.count == 1)
            #expect(entries[0].accountCount == nil)
            #expect(entries[0].labels.isEmpty)
            #expect(entries[0].accounts.isEmpty)
            #expect(!entries[0].isReadable)
            #expect(entries[0].byteCount != nil)
        }
    }

    @Test func listDistinguishesSimilarlyNamedSources() throws {
        try Self.withTempRoot { service, root in
            // ~/.gitconfig and ~/.gitconfig-work share the prefix "gitconfig"
            // but should not bleed into each other's backup lists.
            let gitconfig = root.appendingPathComponent(".gitconfig")
            let work = root.appendingPathComponent(".gitconfig-work")
            try Self.writeFile("main\n", at: gitconfig)
            try Self.writeFile("work\n", at: work)

            let d1 = Date(timeIntervalSince1970: 1_800_000_000)
            let d2 = Date(timeIntervalSince1970: 1_800_000_060)
            _ = try service.backup(originalPath: gitconfig.path, at: d1)
            _ = try service.backup(originalPath: work.path, at: d2)

            let mainRecords = try service.list(for: gitconfig.path)
            let workRecords = try service.list(for: work.path)

            #expect(mainRecords.count == 1)
            #expect(workRecords.count == 1)
            #expect(mainRecords[0].timestamp == d1)
            #expect(workRecords[0].timestamp == d2)
        }
    }

    // MARK: - Retention

    @Test func retentionEvictsOldestBeyondLimit() throws {
        try Self.withTempRoot(retention: 3) { service, root in
            let source = root.appendingPathComponent("config")
            try Self.writeFile("x\n", at: source)

            for i in 0..<5 {
                let d = Date(timeIntervalSince1970: Double(1_800_000_000 + i * 60))
                _ = try service.backup(originalPath: source.path, at: d)
            }

            let records = try service.list(for: source.path)
            #expect(records.count == 3)
            let kept = Set(records.map(\.timestamp.timeIntervalSince1970))
            #expect(kept.contains(1_800_000_240))
            #expect(kept.contains(1_800_000_180))
            #expect(kept.contains(1_800_000_120))
            #expect(!kept.contains(1_800_000_060))
            #expect(!kept.contains(1_800_000_000))
        }
    }

    // MARK: - Restore

    @Test func restoreOverwritesCurrentFile() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("config")
            try Self.writeFile("original\n", at: source)

            let record = try service.backup(originalPath: source.path)

            try Self.writeFile("mutated\n", at: source)
            #expect(try String(contentsOf: source, encoding: .utf8) == "mutated\n")

            try service.restore(record)
            #expect(try String(contentsOf: source, encoding: .utf8) == "original\n")
        }
    }

    @Test func safeRestoreBacksUpCurrentBeforeOverwriting() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("config")
            try Self.writeFile("v1\n", at: source)
            let rec1 = try service.backup(
                originalPath: source.path,
                at: Date(timeIntervalSince1970: 1_800_000_000)
            )

            try Self.writeFile("v2-uncommitted\n", at: source)

            try service.safeRestore(rec1)

            #expect(try String(contentsOf: source, encoding: .utf8) == "v1\n")

            let records = try service.list(for: source.path)
            #expect(records.count >= 2)
            let contents = try records.map {
                try String(contentsOfFile: $0.backupPath, encoding: .utf8)
            }
            #expect(contents.contains("v2-uncommitted\n"))
            #expect(contents.contains("v1\n"))
        }
    }

    @Test func collisionSuffixedSnapshotsStayVisibleInTheList() throws {
        try Self.withTempRoot { service, root in
            // Two snapshots in the same second — what a restore right after an
            // add produces. Both must remain listable, or the pre-restore
            // snapshot is unreachable and the restore is not undoable.
            let source = root.appendingPathComponent("accounts.json")
            try Self.writeFile("v1\n", at: source)
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            _ = try service.backup(originalPath: source.path, at: date)
            try Self.writeFile("v2\n", at: source)
            _ = try service.backup(originalPath: source.path, at: date)

            let records = try service.list(for: source.path)
            #expect(records.count == 2)
            #expect(records.allSatisfy { $0.timestamp == date })
            let contents = Set(try records.map {
                try String(contentsOfFile: $0.backupPath, encoding: .utf8)
            })
            #expect(contents == ["v1\n", "v2\n"])
        }
    }

    @Test func preRestoreSnapshotCanUndoTheRestore() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("accounts.json")
            try Self.writeFile("old-list\n", at: source)
            let oldSnapshot = try service.backup(
                originalPath: source.path,
                at: Date(timeIntervalSince1970: 1_800_000_000)
            )

            try Self.writeFile("current-list\n", at: source)
            try service.safeRestore(oldSnapshot)
            #expect(try String(contentsOf: source, encoding: .utf8) == "old-list\n")

            // The snapshot taken immediately before the restore is listed, so
            // the pre-restore list can be restored in turn.
            let preRestore = try #require(
                try service.list(for: source.path).first {
                    (try? String(contentsOfFile: $0.backupPath, encoding: .utf8)) == "current-list\n"
                }
            )
            try service.restore(preRestore)
            #expect(try String(contentsOf: source, encoding: .utf8) == "current-list\n")
        }
    }

    @Test func backupRefusesSymlinkSource() throws {
        try Self.withTempRoot { service, root in
            let target = root.appendingPathComponent("real-file")
            try Self.writeFile("payload", at: target)

            let linkPath = root.appendingPathComponent("evil-link").path
            try FileManager.default.createSymbolicLink(
                atPath: linkPath,
                withDestinationPath: target.path
            )

            #expect(throws: BackupError.self) {
                try service.backup(originalPath: linkPath)
            }
        }
    }

    @Test func restoreRefusesSymlinkDestination() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("config")
            try Self.writeFile("original", at: source)
            let record = try service.backup(originalPath: source.path)

            // Now replace the current file with a symlink to a "sensitive" file
            try FileManager.default.removeItem(at: source)
            let elsewhere = root.appendingPathComponent("elsewhere")
            try Self.writeFile("other", at: elsewhere)
            try FileManager.default.createSymbolicLink(
                at: source,
                withDestinationURL: elsewhere
            )

            #expect(throws: BackupError.self) {
                try service.restore(record)
            }
            // The target of the symlink must be unchanged
            #expect(try String(contentsOf: elsewhere, encoding: .utf8) == "other")
        }
    }

    @Test func restoreThrowsIfBackupMissing() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("config")
            try Self.writeFile("x\n", at: source)
            let record = try service.backup(originalPath: source.path)

            try FileManager.default.removeItem(atPath: record.backupPath)
            #expect(throws: BackupError.self) {
                try service.restore(record)
            }
        }
    }

    @Test func deleteRemovesBackupFile() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("accounts.json")
            try Self.writeFile("{}\n", at: source)
            let record = try service.backup(originalPath: source.path)
            #expect(FileManager.default.fileExists(atPath: record.backupPath))

            try service.delete(record)

            #expect(!FileManager.default.fileExists(atPath: record.backupPath))
            #expect(try service.list(for: source.path).isEmpty)
        }
    }

    @Test func deleteThrowsIfBackupMissing() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("accounts.json")
            try Self.writeFile("{}\n", at: source)
            let record = try service.backup(originalPath: source.path)
            try FileManager.default.removeItem(atPath: record.backupPath)

            #expect(throws: BackupError.self) {
                try service.delete(record)
            }
        }
    }

    @Test func deleteRefusesSymlinkBackup() throws {
        try Self.withTempRoot { service, root in
            let source = root.appendingPathComponent("accounts.json")
            try Self.writeFile("{}\n", at: source)
            let record = try service.backup(originalPath: source.path)

            let real = URL(fileURLWithPath: record.backupPath)
            let sibling = real.deletingLastPathComponent()
                .appendingPathComponent("real-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: real, to: sibling)
            try FileManager.default.createSymbolicLink(
                atPath: record.backupPath,
                withDestinationPath: sibling.path
            )

            #expect(throws: BackupError.self) {
                try service.delete(record)
            }
            #expect(FileManager.default.fileExists(atPath: sibling.path))
        }
    }
}
