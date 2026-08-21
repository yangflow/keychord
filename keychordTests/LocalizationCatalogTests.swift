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
        "No backups yet — a snapshot is taken when you add an account or before a restore.",
        "No URL rewrites",
        "%lld URL rewrites",
        "Port %@",
        "Refresh",
        "Settings",
        "General",
        "Keys",
        "Config",
        "KeyChord",
        "Includes",
        "Remove Include (keep accounts.json)",
        "Include markers removed",
        "org/repo",
        "Copy clone command",
        "Startup",
        "Open at Login",
        "Open at Login needs approval in System Settings → General → Login Items.",
        "Could not enable Open at Login. Check System Settings → Login Items.",
        "Language",
        "Follow System",
        "Relaunch KeyChord to apply the language everywhere.",
        "Relaunch",
        "Account color",
        "Ed25519",
        "Delete",
        // Menubar drop hint (#24)
        "Drag a project folder onto the menu bar icon above",
        "See which identity would push from that folder",
        // One-click gitdir bind (#25) and multi-path scopes (#27)
        "Bind to",
        "Sets a gitdir scope for this folder",
        "Already scoped to %@ · adds another path",
        "Bind failed: %@",
        "Add gitdir path",
        "Remove gitdir path",
        // Clone under a popover account row (#26)
        "Clone",
        "Show clone command",
        "Hide clone command",
        // Zero-account empty state (#28)
        "No identities yet",
        "Import from your existing SSH / git config, or add one by hand",
        "Import from existing config",
        "Add identity",
        "You can also drag a folder onto the menu bar icon",
        // Probe-failure next actions (#29)
        "Authentication failed",
        "Probe again",
        "Copy public key",
        "Open Gitea SSH settings",
        "Open SSH settings",
        "No public key at %@",
        "This account has no private key yet.",
        // Restore confirmation (#30)
        "Restore this snapshot?",
        "1 current identity will be replaced with:",
        "%lld current identities will be replaced with:",
        // Git author vs SSH identity (#31)
        "Git author does not match the SSH identity",
        "Commits and pushes use different identities",
        "%@ pushes as %@. %@",
        "Commits would be authored as %@ (%@).",
        "Commits would be authored as %@, which no account owns.",
        "This repository has no git user.email, so commits have no author.",
        "core.sshCommand pins the key %@.",
        "Re-apply managed config",
        "Set this account's git email, or give it a gitdir scope that covers this folder.",
        // Menu-bar tooltip (#32)
        "no match",
        // Match-card folder actions (#33)
        "Open in Finder",
        "Unbind",
        "Rebind to",
        "Unbind failed: %@",
        "Rebind failed: %@",
        // Reason-specific probe actions (#34)
        "Key is locked",
        "Private key is missing",
        "Could not reach the host",
        "Remote is HTTPS, so clone and push take different paths",
        "ssh-agent does not hold %@.",
        "Nothing at %@.",
        "Unlock in Keychain",
        "Generate a key",
        "Add SSH rewrite",
        "No private key at %@",
        "Could not unlock the key: %@. Run %@ in Terminal to type the passphrase.",
        "Could not add the SSH rewrite: %@",
        // Identity filter (#35)
        "Filter identities",
        "Clear filter",
        "No identity matches this filter",
        // Delete leftovers (#36)
        "Delete identity %@?",
        "This removes the identity from KeyChord. These are not deleted for you:",
        "Also delete the private key",
        "Managed SSH and git config are regenerated. Folders on disk stay where they are.",
        "Delete identity",
        "Private key",
        "Deleted · private key removed",
        "Deleted, but the private key was kept: %@",
        "%@ is a symlink, so keychord will not delete it.",
        "%@ is not a regular file.",
        "%@ also uses this key, so it is kept.",
        "Could not delete the private key: %@",
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
