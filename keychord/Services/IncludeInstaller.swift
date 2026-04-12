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
        managedPath: String
    ) throws {
        let block = """
        \(markerBegin)
        Include \(toTilde(managedPath))
        \(markerEnd)

        """
        try installBlock(targetPath: targetPath, block: block)
    }

    static func uninstallSSHInclude(
        targetPath: String
    ) throws {
        try uninstallBlock(targetPath: targetPath)
    }

    static func installGitInclude(
        targetPath: String,
        managedPath: String
    ) throws {
        let block = """
        \(markerBegin)
        [include]
        \tpath = \(toTilde(managedPath))
        \(markerEnd)

        """
        try installBlock(targetPath: targetPath, block: block, position: .append)
    }

    static func uninstallGitInclude(
        targetPath: String
    ) throws {
        try uninstallBlock(targetPath: targetPath)
    }

    // MARK: - Core install / uninstall

    enum Position { case prepend, append }

    static func installBlock(
        targetPath: String,
        block: String,
        position: Position = .prepend
    ) throws {
        let current = (try? String(contentsOfFile: targetPath, encoding: .utf8)) ?? ""

        // If an existing keychord marker block is already present, the
        // install is a no-op (idempotent). We could detect path
        // changes here, but the pragmatic answer is: uninstall first,
        // then install again.
        if current.contains(markerBegin) {
            return
        }

        let parent = (targetPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: parent,
            withIntermediateDirectories: true
        )

        let newContents: String
        switch position {
        case .prepend:
            // SSH: first matched Host wins, so our block goes on top.
            if current.isEmpty {
                newContents = block
            } else if current.hasPrefix("\n") || current.hasPrefix(markerBegin) {
                newContents = block + current
            } else {
                newContents = block + "\n" + current
            }
        case .append:
            // Git: last value wins, so our block goes at the bottom.
            if current.isEmpty {
                newContents = block
            } else if current.hasSuffix("\n") {
                newContents = current + "\n" + block
            } else {
                newContents = current + "\n\n" + block
            }
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
        targetPath: String
    ) throws {
        guard let current = try? String(contentsOfFile: targetPath, encoding: .utf8),
              current.contains(markerBegin) else {
            return
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
