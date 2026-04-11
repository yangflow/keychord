import Foundation

struct BackupRecord: Equatable, Hashable, Identifiable, Sendable {
    let originalPath: String
    let backupPath: String
    let timestamp: Date

    var id: String { backupPath }
}

enum BackupError: Swift.Error, CustomStringConvertible {
    case sourceNotFound(String)
    case backupNotFound(String)
    case symlinkNotAllowed(String)

    var description: String {
        switch self {
        case .sourceNotFound(let p): return "Source file not found: \(p)"
        case .backupNotFound(let p): return "Backup file not found: \(p)"
        case .symlinkNotAllowed(let p): return "Refusing to operate on symlink: \(p)"
        }
    }
}

struct BackupService: Sendable {
    let backupRoot: URL
    let retentionCount: Int

    init(
        backupRoot: URL? = nil,
        retentionCount: Int = 10
    ) {
        self.backupRoot = backupRoot ?? Self.defaultBackupRoot
        self.retentionCount = retentionCount
    }

    static var defaultBackupRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/keychord/backups")
    }

    // MARK: - Backup

    @discardableResult
    func backup(originalPath: String, at date: Date = Date()) throws -> BackupRecord {
        guard FileManager.default.fileExists(atPath: originalPath) else {
            throw BackupError.sourceNotFound(originalPath)
        }
        try Self.refuseIfSymlink(originalPath)

        try FileManager.default.createDirectory(
            at: backupRoot,
            withIntermediateDirectories: true
        )

        let base = Self.backupBaseName(for: originalPath)
        let ts = Self.formatTimestamp(date)
        var fileName = "\(base).\(ts)"
        var fileURL = backupRoot.appendingPathComponent(fileName)
        var suffix = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileName = "\(base).\(ts)-\(suffix)"
            fileURL = backupRoot.appendingPathComponent(fileName)
            suffix += 1
        }

        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: originalPath),
            to: fileURL
        )

        try prune(forBaseName: base)

        return BackupRecord(
            originalPath: originalPath,
            backupPath: fileURL.path,
            timestamp: date
        )
    }

    // MARK: - List

    func list(for originalPath: String) throws -> [BackupRecord] {
        let base = Self.backupBaseName(for: originalPath)
        return try list(forBaseName: base, mapTo: originalPath)
    }

    private func list(forBaseName base: String, mapTo originalPath: String) throws -> [BackupRecord] {
        guard FileManager.default.fileExists(atPath: backupRoot.path) else {
            return []
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: backupRoot.path)
        let prefix = "\(base)."
        var records: [BackupRecord] = []

        for name in entries where name.hasPrefix(prefix) {
            let tail = String(name.dropFirst(prefix.count))
            // tail = "yyyyMMdd-HHmmss" or "yyyyMMdd-HHmmss-N"
            let tsPart: String
            if let dashRange = tail.range(of: "-", options: .backwards),
               tail.distance(from: tail.startIndex, to: dashRange.lowerBound) > 8 + 1 + 6 {
                // There are three dashes worth of structure; the last one is the collision suffix.
                tsPart = String(tail[..<dashRange.lowerBound])
            } else {
                tsPart = tail
            }
            guard let date = Self.parseTimestamp(tsPart) else { continue }

            let path = backupRoot.appendingPathComponent(name).path
            records.append(BackupRecord(
                originalPath: originalPath,
                backupPath: path,
                timestamp: date
            ))
        }

        records.sort { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
            return lhs.backupPath > rhs.backupPath
        }
        return records
    }

    // MARK: - Restore

    func restore(_ record: BackupRecord) throws {
        guard FileManager.default.fileExists(atPath: record.backupPath) else {
            throw BackupError.backupNotFound(record.backupPath)
        }
        // If the current file at the destination has been replaced with a
        // symlink since the backup was taken, refuse to overwrite — it could
        // be pointing anywhere.
        if FileManager.default.fileExists(atPath: record.originalPath) {
            try Self.refuseIfSymlink(record.originalPath)
        }
        let originalURL = URL(fileURLWithPath: record.originalPath)
        let backupURL = URL(fileURLWithPath: record.backupPath)

        let tmpURL = originalURL
            .deletingLastPathComponent()
            .appendingPathComponent(".keychord-restore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        try FileManager.default.copyItem(at: backupURL, to: tmpURL)
        _ = try FileManager.default.replaceItemAt(originalURL, withItemAt: tmpURL)
    }

    /// Back up the current file (if any) before overwriting it with the
    /// selected backup, so a restore can itself be rolled back.
    func safeRestore(_ record: BackupRecord) throws {
        if FileManager.default.fileExists(atPath: record.originalPath) {
            _ = try backup(originalPath: record.originalPath)
        }
        try restore(record)
    }

    // MARK: - Prune

    private func prune(forBaseName base: String) throws {
        let records = try list(forBaseName: base, mapTo: "")
        guard records.count > retentionCount else { return }
        for stale in records.dropFirst(retentionCount) {
            try? FileManager.default.removeItem(atPath: stale.backupPath)
        }
    }

    // MARK: - Safety helpers

    /// Refuse to operate on a path that is itself a symbolic link. This
    /// prevents an attacker from racing the file between our existence
    /// check and the copy/replace step to aim the operation at a file
    /// outside the user's intended directory (e.g. /etc/hosts).
    static func refuseIfSymlink(_ path: String) throws {
        // `destinationOfSymbolicLink` throws when the path is not a symlink,
        // succeeds when it is — so a successful call means "refuse".
        if let _ = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
            throw BackupError.symlinkNotAllowed(path)
        }
    }

    // MARK: - Helpers

    static func backupBaseName(for originalPath: String) -> String {
        let name = URL(fileURLWithPath: originalPath).lastPathComponent
        return name.hasPrefix(".") ? String(name.dropFirst()) : name
    }

    static func formatTimestamp(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? cal.timeZone
        let c = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "%04d%02d%02d-%02d%02d%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    static func parseTimestamp(_ s: String) -> Date? {
        // Expected format: yyyyMMdd-HHmmss (15 chars)
        guard s.count == 15,
              s[s.index(s.startIndex, offsetBy: 8)] == "-" else { return nil }

        func intSlice(_ start: Int, _ length: Int) -> Int? {
            let from = s.index(s.startIndex, offsetBy: start)
            let to = s.index(from, offsetBy: length)
            return Int(s[from..<to])
        }

        guard
            let year = intSlice(0, 4),
            let month = intSlice(4, 2),
            let day = intSlice(6, 2),
            let hour = intSlice(9, 2),
            let minute = intSlice(11, 2),
            let second = intSlice(13, 2)
        else { return nil }

        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        c.second = second
        c.timeZone = TimeZone(identifier: "UTC")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? cal.timeZone
        return cal.date(from: c)
    }
}
