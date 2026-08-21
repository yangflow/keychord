import Testing
import Foundation
@testable import keychord

@Suite("KeyAttachment")
@MainActor
struct KeyAttachmentTests {

    static func withTempURL(_ test: (URL) async throws -> Void) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-attach-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tmp,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = tmp.appendingPathComponent("accounts.json")
        try await test(url)
    }

    static func makeStore(url: URL) -> AccountsStore {
        let backups = BackupService(
            backupRoot: url.deletingLastPathComponent().appendingPathComponent("backups"),
            retentionCount: 10
        )
        return AccountsStore(storageURL: url, backups: backups, autoLoad: false)
    }

    static func sampleAccount(label: String = "Personal") -> Account {
        Account.new(
            label: label,
            sshAlias: "github-personal",
            keyPath: "",
            gitUserName: "yangflow",
            gitUserEmail: "you@example.com"
        )
    }

    static func sampleResult(
        privateKeyPath: String = "\(NSHomeDirectory())/.ssh/id_keychord_test",
        fingerprint: String? = "SHA256:abcdefghijklmnopqrstuvwxyz0123456789ABCDE"
    ) -> KeygenResult {
        KeygenResult(
            privateKeyPath: privateKeyPath,
            publicKeyPath: privateKeyPath + ".pub",
            publicKeyContent: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakePublicKeyMaterialOnly you@example.com",
            fingerprint: fingerprint
        )
    }

    // MARK: - Pure apply

    @Test func applySetsKeyPathAndFingerprint() {
        let account = Self.sampleAccount()
        let result = Self.sampleResult()
        let updated = KeyAttachment.apply(result: result, to: account)

        #expect(updated.id == account.id)
        #expect(updated.keyPath == "~/.ssh/id_keychord_test")
        #expect(updated.keyFingerprint == result.fingerprint)
        // Identity fields unchanged
        #expect(updated.label == account.label)
        #expect(updated.sshAlias == account.sshAlias)
    }

    @Test func makeNewAccountPrefillsKeyOnly() {
        let result = Self.sampleResult()
        let fresh = KeyAttachment.makeNewAccount(
            from: result,
            suggestedEmail: "new@example.com"
        )

        #expect(fresh.keyPath == "~/.ssh/id_keychord_test")
        #expect(fresh.keyFingerprint == result.fingerprint)
        #expect(fresh.gitUserEmail == "new@example.com")
        #expect(fresh.label.isEmpty)
        #expect(fresh.sshAlias.isEmpty)
        #expect(fresh.username.isEmpty)
        #expect(fresh.provider == .github)
    }

    // MARK: - Persist / cancel

    @Test func commitAttachUpdatesExistingAccountKeyPath() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            let account = Self.sampleAccount()
            try store.add(account)

            let result = Self.sampleResult()
            let attached = KeyAttachment.apply(result: result, to: account)

            var regenerated = false
            try KeyAttachment.commit(
                account: attached,
                isNew: false,
                store: store,
                regenerate: { accounts in
                    regenerated = true
                    #expect(accounts.count == 1)
                    #expect(accounts[0].keyPath == "~/.ssh/id_keychord_test")
                }
            )

            #expect(regenerated)
            #expect(store.accounts.first?.keyPath == "~/.ssh/id_keychord_test")
            #expect(store.accounts.first?.keyFingerprint == result.fingerprint)

            // Survives reload
            let reloaded = Self.makeStore(url: url)
            try reloaded.load()
            #expect(reloaded.accounts.first?.keyPath == "~/.ssh/id_keychord_test")
            #expect(reloaded.accounts.first?.keyFingerprint == result.fingerprint)
        }
    }

    @Test func commitCreateNewWritesAccountWithKeyPath() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            let result = Self.sampleResult()
            let fresh = KeyAttachment.makeNewAccount(from: result)

            try KeyAttachment.commit(
                account: fresh,
                isNew: true,
                store: store,
                regenerate: { _ in }
            )

            #expect(store.accounts.count == 1)
            #expect(store.accounts[0].id == fresh.id)
            #expect(store.accounts[0].keyPath == "~/.ssh/id_keychord_test")
        }
    }

    @Test func cancelAttachDoesNotWriteAccount() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            #expect(store.accounts.isEmpty)

            // Simulate opening the attach picker then cancelling: never call commit.
            let result = Self.sampleResult()
            _ = KeyAttachment.makeNewAccount(from: result)
            _ = KeyAttachment.apply(result: result, to: Self.sampleAccount())

            #expect(store.accounts.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    // MARK: - No secrets in accounts.json

    @Test func accountsJSONDoesNotContainPrivateKeyMaterial() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            let privateKeyBody = """
            -----BEGIN OPENSSH PRIVATE KEY-----
            b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
            SECRET_PRIVATE_KEY_MATERIAL_MUST_NOT_LEAK
            -----END OPENSSH PRIVATE KEY-----
            """
            let result = KeygenResult(
                privateKeyPath: "\(NSHomeDirectory())/.ssh/id_secret_test",
                publicKeyPath: "\(NSHomeDirectory())/.ssh/id_secret_test.pub",
                publicKeyContent: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOnlyPublic you@example.com",
                fingerprint: "SHA256:onlyFingerprintStored"
            )

            // Pure apply must never embed key body — only the path string.
            var account = Self.sampleAccount()
            account = KeyAttachment.apply(result: result, to: account)
            try store.add(account)

            let data = try Data(contentsOf: url)
            let json = String(data: data, encoding: .utf8) ?? ""

            #expect(json.contains("keyPath"))
            #expect(json.contains("~/.ssh/id_secret_test"))
            #expect(json.contains("SHA256:onlyFingerprintStored"))
            #expect(!json.contains("BEGIN OPENSSH PRIVATE KEY"))
            #expect(!json.contains("SECRET_PRIVATE_KEY_MATERIAL_MUST_NOT_LEAK"))
            #expect(!json.contains(privateKeyBody))
            #expect(!json.contains(result.publicKeyContent))
        }
    }

    @Test func sshSettingsURLIsProviderAware() {
        #expect(
            KeyAttachment.sshSettingsURL(for: .github)?.absoluteString
                == "https://github.com/settings/keys"
        )
        #expect(
            KeyAttachment.sshSettingsURL(for: .gitlab)?.absoluteString
                == "https://gitlab.com/-/user_settings/ssh_keys"
        )
        #expect(
            KeyAttachment.sshSettingsURL(for: .gitea)?.absoluteString
                == "https://gitea.com/user/settings/keys"
        )
        #expect(KeyAttachment.sshSettingsURL(for: .custom) == nil)
    }

    @Test func makeNewAccountCarriesSelectedProvider() {
        let result = Self.sampleResult()
        let fresh = KeyAttachment.makeNewAccount(
            from: result,
            suggestedEmail: "new@example.com",
            provider: .gitlab
        )
        #expect(fresh.provider == .gitlab)
    }
}
