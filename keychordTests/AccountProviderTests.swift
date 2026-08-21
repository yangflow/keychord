import Testing
import Foundation
@testable import keychord

@Suite("AccountProvider")
struct AccountProviderTests {

    // MARK: - Legacy JSON decode

    @Test func legacyAccountsJSONWithoutProviderDecodesAsGitHub() throws {
        // Build a valid modern account, then strip provider and rename
        // username → githubUsername to simulate a pre-#7 accounts.json.
        var account = Account.new(
            label: "Personal",
            sshAlias: "github.com",
            keyPath: "~/.ssh/id_ed25519",
            gitUserName: "yangflow",
            gitUserEmail: "you@example.com"
        )
        account.username = "yangflow"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var obj = try #require(
            JSONSerialization.jsonObject(with: try encoder.encode(account)) as? [String: Any]
        )
        obj.removeValue(forKey: "provider")
        let username = obj.removeValue(forKey: "username") as? String
        obj["githubUsername"] = username

        let legacyData = try JSONSerialization.data(withJSONObject: obj)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Account.self, from: legacyData)

        #expect(decoded.provider == .github)
        #expect(decoded.username == "yangflow")
        #expect(decoded.label == "Personal")
        #expect(decoded.sshAlias == "github.com")
        #expect(decoded.id == account.id)
    }

    @Test func modernUsernameAndProviderRoundTrip() throws {
        var account = Account.new(
            label: "Work",
            sshAlias: "gitlab-work",
            keyPath: "~/.ssh/id_ed25519",
            provider: .gitlab,
            gitUserName: "bob",
            gitUserEmail: "bob@example.com"
        )
        account.username = "bob"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(account)

        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"username\""))
        #expect(json.contains("\"provider\""))
        #expect(!json.contains("githubUsername"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Account.self, from: data)
        #expect(decoded.provider == .gitlab)
        #expect(decoded.username == "bob")
    }

    // MARK: - insteadOf presets

    @Test func gitlabPresetWritesReasonableInsteadOf() {
        let presets = Account.Provider.gitlab.insteadOfPresets(sshAlias: "gitlab-work")
        #expect(presets.count == 2)
        #expect(presets.contains {
            $0.from == "https://gitlab.com/" && $0.to == "git@gitlab-work:"
        })
        #expect(presets.contains {
            $0.from == "git@gitlab.com:" && $0.to == "git@gitlab-work:"
        })
    }

    @Test func githubAndGiteaPresetsUseCanonicalHosts() {
        let github = Account.Provider.github.insteadOfPresets(sshAlias: "github-work")
        #expect(github.contains {
            $0.from == "https://github.com/" && $0.to == "git@github-work:"
        })

        let gitea = Account.Provider.gitea.insteadOfPresets(sshAlias: "gitea-home")
        #expect(gitea.contains {
            $0.from == "https://gitea.com/" && $0.to == "git@gitea-home:"
        })
        #expect(gitea.contains {
            $0.from == "git@gitea.com:" && $0.to == "git@gitea-home:"
        })
    }

    @Test func customPresetIsEmptyAndDoesNotInventGitHubSettingsURL() {
        #expect(Account.Provider.custom.insteadOfPresets(sshAlias: "anything").isEmpty)
        #expect(Account.Provider.custom.host == nil)
        #expect(Account.Provider.custom.sshSettingsURL == nil)
        #expect(KeyAttachment.sshSettingsURL(for: .custom) == nil)
    }

    @Test func emptyAliasYieldsNoPresets() {
        #expect(Account.Provider.github.insteadOfPresets(sshAlias: "  ").isEmpty)
        #expect(Account.Provider.gitlab.insteadOfPresets(sshAlias: "").isEmpty)
    }

    @Test func applyInsteadOfPresetMergesWithoutDuplicates() {
        var account = Account.new(
            label: "GL",
            sshAlias: "gitlab-work",
            keyPath: "~/.ssh/id_ed25519",
            provider: .gitlab,
            gitUserName: "bob",
            gitUserEmail: "bob@example.com"
        )
        account.applyInsteadOfPreset()
        #expect(account.urlRewrites.count == 2)
        account.applyInsteadOfPreset()
        #expect(account.urlRewrites.count == 2)
    }
}
