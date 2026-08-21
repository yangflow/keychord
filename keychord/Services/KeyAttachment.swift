import Foundation

/// Pure helpers for binding a generated SSH key to an `Account`.
/// Persistence (AccountsStore save + AccountProjector regenerate) stays
/// in the UI layer so cancelling the attach picker never writes.
enum KeyAttachment {

    /// SSH keys settings URL for a provider. `nil` for `.custom` — callers
    /// must copy the public key only and must not invent a GitHub URL.
    static func sshSettingsURL(for provider: Account.Provider) -> URL? {
        provider.sshSettingsURL
    }

    /// Apply a generated key's path + fingerprint onto an existing account.
    /// Private key bytes are never copied — only the filesystem path.
    static func apply(result: KeygenResult, to account: Account) -> Account {
        apply(
            privateKeyPath: result.privateKeyPath,
            fingerprint: result.fingerprint,
            to: account
        )
    }

    static func apply(
        privateKeyPath: String,
        fingerprint: String?,
        to account: Account
    ) -> Account {
        var next = account
        next.keyPath = AccountProjector.toTilde(privateKeyPath)
        next.keyFingerprint = fingerprint
        return next
    }

    /// Build a new unsaved account with the key already filled in.
    /// Label / alias / identity fields stay empty for the user to complete
    /// in AccountDetailView — Host projection still requires a non-empty alias.
    static func makeNewAccount(
        from result: KeygenResult,
        suggestedEmail: String = "",
        provider: Account.Provider = .github
    ) -> Account {
        makeNewAccount(
            privateKeyPath: result.privateKeyPath,
            fingerprint: result.fingerprint,
            suggestedEmail: suggestedEmail,
            provider: provider
        )
    }

    static func makeNewAccount(
        privateKeyPath: String,
        fingerprint: String?,
        suggestedEmail: String = "",
        provider: Account.Provider = .github
    ) -> Account {
        let now = Date()
        let email = suggestedEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return Account(
            id: UUID(),
            label: "",
            username: "",
            provider: provider,
            sshAlias: "",
            keyPath: AccountProjector.toTilde(privateKeyPath),
            keyFingerprint: fingerprint,
            sshPort: .port443,
            gitUserName: "",
            gitUserEmail: email,
            scope: .global,
            urlRewrites: [],
            color: .blue,
            notes: "",
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil
        )
    }

    /// Persist an attach decision: update an existing account or add a new one.
    /// Call only after the user confirms a target — cancel must not invoke this.
    @MainActor
    static func commit(
        account: Account,
        isNew: Bool,
        store: AccountsStore,
        regenerate: ([Account]) throws -> Void
    ) throws {
        if isNew {
            try store.add(account)
        } else {
            try store.update(account)
        }
        try regenerate(store.accounts)
    }
}
