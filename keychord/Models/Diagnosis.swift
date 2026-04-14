import Foundation

struct Diagnosis: Equatable, Identifiable, Hashable, Sendable {
    var severity: Severity
    var code: String
    var title: String
    var detail: String
    var fixHint: String?
    var affectedFiles: [String]
    var fixes: [FixOption] = []

    var id: String {
        "\(code)::\(affectedFiles.joined(separator: ","))::\(title)"
    }

    enum Severity: Int, Comparable, Hashable, Sendable {
        case info = 0
        case warning = 1
        case error = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var symbolName: String {
            switch self {
            case .info:    return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error:   return "xmark.octagon"
            }
        }
    }
}

// MARK: - Fix options

struct FixOption: Equatable, Hashable, Sendable, Identifiable {
    var label: String
    var fixID: FixID
    var isDestructive: Bool

    var id: FixID { fixID }

    /// Destructive fixes use a two-state inline confirm; automatic fixes
    /// run on first click.
    var requiresConfirmation: Bool {
        isDestructive
    }
}

/// A typed identifier the UI hands to Fixer.execute. All data the fix
/// needs to run is embedded in the associated values, so the fix stays
/// valid even if the Diagnosis was generated against slightly stale
/// state.
enum FixID: Equatable, Hashable, Sendable {
    /// Remove the given SSH Host block from ~/.ssh/config.
    case ssh001_removeHost(alias: String)

    /// Add `HostKeyAlias github.com` to the given SSH Host block.
    case ssh003_addHostKeyAlias(alias: String)
}
