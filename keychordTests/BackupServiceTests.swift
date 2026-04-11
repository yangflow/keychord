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
}
