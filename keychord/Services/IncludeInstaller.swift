import Foundation

/// Injects and removes the one-line `Include` / `[include]` pointer in
/// the user's ~/.ssh/config and ~/.gitconfig that hands off to the
/// keychord-managed files. Everything keychord writes is wrapped in
/// `# --- keychord managed ---` / `# --- keychord managed end ---`
/// marker comments so uninstall is a simple grep-and-delete. The
/// user's hand-written config below the marker block stays byte-
/// identical across install / uninstall round-trips.
enum IncludeInstaller {

    static let markerBegin = "# --- keychord managed ---"
    static let markerEnd   = "# --- keychord managed end ---"

    enum InstallerError: Swift.Error, Equatable, CustomStringConvertible {
        case conflictingInclude(existing: String)
        case writeFailed(String)

        var description: String {
            switch self {
            case .conflictingInclude(let e):
                return "Target already has an unrelated include: \(e)"
            case .writeFailed(let m):
                return "Install failed: \(m)"
            }
        }
    }

    // MARK: - Public API

    static func installSSHInclude(
        targetPath: String,
        managedPath: String,
        backups: BackupService
    ) throws {
        let block = """
        \(markerBegin)
        Include \(toTilde(managedPath))
        \(markerEnd)

        """
        try installBlock(targetPath: targetPath, block: block, backups: backups)
    }

    static func uninstallSSHInclude(
        targetPath: String,
        backups: BackupService
    ) throws {
        try uninstallBlock(targetPath: targetPath, backups: backups)
    }

    static func installGitInclude(
        targetPath: String,
        managedPath: String,
        backups: BackupService
    ) throws {
        let block = """
        \(markerBegin)
        [include]
        \tpath = \(toTilde(managedPath))
        \(markerEnd)

        """
        try installBlock(targetPath: targetPath, block: block, backups: backups)
    }

    static func uninstallGitInclude(
        targetPath: String,
        backups: BackupService
    ) throws {
        try uninstallBlock(targetPath: targetPath, backups: backups)
    }

    // MARK: - Core install / uninstall

    static func installBlock(
        targetPath: String,
        block: String,
        backups: BackupService
    ) throws {
        let current = (try? String(contentsOfFile: targetPath, encoding: .utf8)) ?? ""

        // If an existing keychord marker block is already present, the
        // install is a no-op (idempotent). We could detect path
        // changes here, but the pragmatic answer is: uninstall first,
        // then install again.
        if current.contains(markerBegin) {
            return
        }

        // Back up anything that's about to be modified.
        let parent = (targetPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: parent,
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: targetPath) {
            _ = try backups.backup(originalPath: targetPath)
        }

        // Prepend the block at the top so keychord's Hosts take
        // precedence over any duplicates the user may have below.
        let newContents: String
        if current.isEmpty {
            newContents = block
        } else if current.hasPrefix("\n") || current.hasPrefix(markerBegin) {
            newContents = block + current
        } else {
            newContents = block + "\n" + current
        }

        do {
            try newContents.write(
                toFile: targetPath,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            throw InstallerError.writeFailed(error.localizedDescription)
        }
    }

    static func uninstallBlock(
        targetPath: String,
        backups: BackupService
    ) throws {
        guard let current = try? String(contentsOfFile: targetPath, encoding: .utf8),
              current.contains(markerBegin) else {
            return
        }
        if FileManager.default.fileExists(atPath: targetPath) {
            _ = try backups.backup(originalPath: targetPath)
        }
        let cleaned = stripMarkerBlock(current)
        do {
            try cleaned.write(
                toFile: targetPath,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            throw InstallerError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Marker-block string ops (pure, for tests)

    static func stripMarkerBlock(_ text: String) -> String {
        guard let beginRange = text.range(of: markerBegin) else {
            return text
        }
        guard let endRange = text.range(
            of: markerEnd,
            range: beginRange.upperBound..<text.endIndex
        ) else {
            return text
        }

        // Walk the `end` cursor forward past any trailing \n characters
        // so the leftover doesn't start with a stray blank line.
        var afterEnd = endRange.upperBound
        while afterEnd < text.endIndex, text[afterEnd] == "\n" {
            afterEnd = text.index(after: afterEnd)
        }

        let before = text[..<beginRange.lowerBound]
        let after  = text[afterEnd...]
        return String(before) + String(after)
    }

    // MARK: - Path helpers

    static func toTilde(_ absolute: String) -> String {
        let home = NSHomeDirectory()
        if absolute.hasPrefix(home) {
            return "~" + absolute.dropFirst(home.count)
        }
        return absolute
    }
}
