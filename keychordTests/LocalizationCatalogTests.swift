import Testing
import Foundation

/// Catalog-presence checks for Localizable.xcstrings.
/// These parse the String Catalog JSON on disk and do not require a GUI
/// or `xcodebuild` localization tooling — suitable for CI that skips macOS builds.
@Suite("LocalizationCatalog")
struct LocalizationCatalogTests {

    private static let requiredKeys: [String] = [
        "Identity",
        "Loading config…",
        "Clear current repo",
        "Use with this account",
        "Open GitHub SSH settings",
        "Open GitLab SSH settings",
        "Username",
        "Provider",
        "Apply rewrite preset",
        "Duplicate Host blocks",
        "Accounts",
        "Key Type",
        "Backups",
        "1 account",
        "%lld accounts",
        "0 accounts",
        "Unreadable snapshot",
        "Show backup contents",
        "Hide backup contents",
        "No accounts in this snapshot",
        "No URL rewrites",
        "%lld URL rewrites",
        "Port %@",
        "Refresh",
        "Settings",
        "General",
        "Keys",
        "Config",
        "Scan for accounts",
        "Scan ~/.ssh/config and ~/.gitconfig for accounts KeyChord can import.",
        "Includes",
        "Remove Include (keep accounts.json)",
        "Include markers removed",
        "org/repo",
        "Copy clone command",
        "Startup",
        "Open at Login",
        "Launch keychord in the menu bar when you log in to this Mac.",
        "Open at Login needs approval in System Settings → General → Login Items.",
        "Could not enable Open at Login. Check System Settings → Login Items.",
        "Language",
        "Follow System",
        "Overrides the system language for KeyChord only.",
        "Relaunch KeyChord to apply the language everywhere.",
        "Relaunch",
        "Account color",
    ]

    private static let requiredLocales = ["en", "zh-Hans"]

    @Test func catalogFileExists() throws {
        let url = try Self.catalogURL()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func catalogDeclaresEnglishAndSimplifiedChinese() throws {
        let catalog = try Self.loadCatalog()
        #expect(catalog.sourceLanguage == "en")

        for key in Self.requiredKeys {
            guard let entry = catalog.strings[key] else {
                Issue.record("Missing key in Localizable.xcstrings: \(key)")
                continue
            }
            for locale in Self.requiredLocales {
                guard let unit = entry.localizations[locale]?.stringUnit else {
                    Issue.record("Key \"\(key)\" missing locale \(locale)")
                    continue
                }
                #expect(!unit.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "Key \"\(key)\" has empty \(locale) value")
            }
        }
    }

    @Test func sectionHeadersPreferHeaderClosureStyle() throws {
        // Guard against regressing to Section("…") which bypasses Text localization.
        let viewsRoot = try Self.repoRoot()
            .appendingPathComponent("keychord/Views", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: viewsRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        var offenders: [String] = []
        let pattern = #"Section\s*\(\s*""#
        let regex = try NSRegularExpression(pattern: pattern)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            if regex.firstMatch(in: source, range: range) != nil {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty, "Avoid Section(\"…\"); use header: { Text(...) }. Offenders: \(offenders)")
    }

    // MARK: - Helpers

    private struct Catalog: Decodable {
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private struct Entry: Decodable {
        let localizations: [String: Localization]
    }

    private struct Localization: Decodable {
        let stringUnit: StringUnit?
    }

    private struct StringUnit: Decodable {
        let value: String
    }

    private static func catalogURL() throws -> URL {
        try repoRoot().appendingPathComponent("keychord/Localizable.xcstrings")
    }

    private static func repoRoot() throws -> URL {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testsDir.deletingLastPathComponent()
    }

    private static func loadCatalog() throws -> Catalog {
        let data = try Data(contentsOf: catalogURL())
        return try JSONDecoder().decode(Catalog.self, from: data)
    }
}
