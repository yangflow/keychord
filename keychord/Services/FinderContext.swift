import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum FinderContext {
    /// POSIX path of Finder's frontmost window, or nil if:
    /// - Finder has no open windows
    /// - Automation permission is denied
    /// - any AppleScript error
    static func frontmostDirectory() async -> String? {
        await Task.detached(priority: .userInitiated) {
            frontmostDirectorySync()
        }.value
    }

    static func frontmostDirectorySync() -> String? {
        #if canImport(AppKit)
        let source = """
        tell application "Finder"
            if (count of windows) is 0 then return ""
            try
                return POSIX path of (target of front window as alias)
            on error
                return ""
            end try
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if errorInfo != nil { return nil }
        let path = descriptor.stringValue ?? ""
        return path.isEmpty ? nil : path
        #else
        return nil
        #endif
    }
}
