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
        "Choose Folder…",
        "Use with this account",
        "Open GitHub SSH settings",
        "Duplicate Host blocks",
        "Accounts",
        "Key Type",
        "iCloud Sync",
        "Backups",
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
