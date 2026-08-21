import Foundation

/// Compares the git identity a work tree would actually commit with — the
/// live `user.email` / `core.sshCommand` after `includeIf` resolution — against
/// the keychord account that owns the SSH alias the push authenticates as.
///
/// An SSH probe can be green while `user.email` still belongs to another
/// identity, and the first signal is a commit authored by the wrong person.
/// Pure: `audit(...)` never reads the filesystem, so the git values come from
/// `CurrentRepoResolver.readEffectiveIdentity`.
struct IdentityAudit: Equatable, Sendable {
    /// Account the `gitdir:` scope (or lone global) resolved to — who the
    /// push authenticates as.
    let account: Account
    let repoRoot: String
    let findings: [Finding]

    var isClean: Bool { findings.isEmpty }

    var severity: Diagnosis.Severity? {
        findings.map(\.severity).max()
    }

    enum Finding: Equatable, Hashable, Sendable {
        /// Commits would be authored by a different managed account.
        case authorIsOtherAccount(email: String, label: String)
        /// Commits would be authored by an email no account owns.
        case authorIsUnmanaged(email: String)
        /// The work tree has no `user.email` at all.
        case authorMissing
        /// `core.sshCommand` pins a key other than the account's.
        case keyOverride(keyPath: String)

        var severity: Diagnosis.Severity {
            switch self {
            case .authorIsOtherAccount, .keyOverride:
                return .error
            case .authorIsUnmanaged, .authorMissing:
                return .warning
            }
        }
    }

    // MARK: - Pure audit

    static func audit(
        account: Account,
        repoRoot: String,
        identity: CurrentRepoResolver.EffectiveGitIdentity,
        accounts: [Account]
    ) -> IdentityAudit {
        var findings: [Finding] = []

        let accountEmail = normalized(account.gitUserEmail)
        let gitEmail = normalized(identity.userEmail ?? "")

        if gitEmail.isEmpty {
            if !accountEmail.isEmpty {
                findings.append(.authorMissing)
            }
        } else if gitEmail.caseInsensitiveCompare(accountEmail) != .orderedSame {
            let other = accounts.first {
                $0.id != account.id
                    && normalized($0.gitUserEmail).caseInsensitiveCompare(gitEmail) == .orderedSame
            }
            if let other {
                findings.append(.authorIsOtherAccount(
                    email: gitEmail,
                    label: other.label.isEmpty ? String(localized: "(unnamed)") : other.label
                ))
            } else {
                findings.append(.authorIsUnmanaged(email: gitEmail))
            }
        }

        let accountKey = comparableKeyPath(account.keyPath)
        if let commandKey = identityFile(fromSSHCommand: identity.sshCommand),
           !accountKey.isEmpty,
           comparableKeyPath(commandKey) != accountKey {
            findings.append(.keyOverride(keyPath: commandKey))
        }

        return IdentityAudit(account: account, repoRoot: repoRoot, findings: findings)
    }

    // MARK: - sshCommand parsing

    /// Private key pinned by a `core.sshCommand` such as
    /// `ssh -i ~/.ssh/id_work -o IdentitiesOnly=yes`.
    static func identityFile(fromSSHCommand command: String?) -> String? {
        guard let command, !command.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        let tokens = command
            .split(whereSeparator: \.isWhitespace)
            .map { unquote(String($0)) }

        var iterator = tokens.makeIterator()
        while let token = iterator.next() {
            if token == "-i" {
                if let next = iterator.next(), !next.isEmpty { return next }
                return nil
            }
            if token.hasPrefix("-i"), token.count > 2 {
                return String(token.dropFirst(2))
            }
        }
        return nil
    }

    private static func unquote(_ token: String) -> String {
        var value = token
        for quote in ["\"", "'"] where value.hasPrefix(quote) && value.hasSuffix(quote) {
            guard value.count >= 2 else { break }
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func comparableKeyPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return ConfigStore.expand(trimmed)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension IdentityAudit.Finding {
    /// One-line, user-facing explanation. Shown on the match card and inside
    /// the Doctor diagnosis detail.
    var localizedDetail: String {
        switch self {
        case .authorIsOtherAccount(let email, let label):
            return String(localized: "Commits would be authored as \(email) (\(label)).")
        case .authorIsUnmanaged(let email):
            return String(localized: "Commits would be authored as \(email), which no account owns.")
        case .authorMissing:
            return String(localized: "This repository has no git user.email, so commits have no author.")
        case .keyOverride(let keyPath):
            return String(localized: "core.sshCommand pins the key \(keyPath.abbreviatedHomePath()).")
        }
    }
}
