import Foundation

/// The one thing worth fixing about an account right now, with enough detail
/// to pick the button that actually helps. A red probe is not always “add your
/// key to GitHub”: a locked agent and an HTTPS remote need other next steps.
enum AccountIssue: Equatable, Hashable, Sendable {
    /// The key is passphrase-protected and `ssh-agent` does not hold it.
    case keyLocked(keyPath: String)
    /// The forge rejected the key (or has never seen it).
    case authRejected(reason: String)
    /// The configured private key is not on disk.
    case keyFileMissing(path: String)
    /// Network / host-key trouble: nothing to copy, just retry once fixed.
    case unreachable(reason: String)
    /// Auth is fine, but this repository's remote is HTTPS with no `insteadOf`
    /// rule, so clone and push do not go through the account's SSH alias.
    case httpsRemote(origin: String)

    var severity: Diagnosis.Severity {
        switch self {
        case .keyLocked, .authRejected, .keyFileMissing:
            return .error
        case .unreachable, .httpsRemote:
            return .warning
        }
    }

    /// Headline shown on the strip under the account row.
    var localizedTitle: String {
        switch self {
        case .keyLocked:
            return String(localized: "Key is locked")
        case .authRejected:
            return String(localized: "Authentication failed")
        case .keyFileMissing:
            return String(localized: "Private key is missing")
        case .unreachable:
            return String(localized: "Could not reach the host")
        case .httpsRemote:
            return String(localized: "Remote is HTTPS, so clone and push take different paths")
        }
    }

    /// Second line: the raw probe reason or the path that is at fault.
    var localizedDetail: String {
        switch self {
        case .keyLocked(let keyPath):
            return String(localized: "ssh-agent does not hold \(keyPath.abbreviatedHomePath()).")
        case .authRejected(let reason):
            return reason
        case .keyFileMissing(let path):
            return String(localized: "Nothing at \(path.abbreviatedHomePath()).")
        case .unreachable(let reason):
            return reason
        case .httpsRemote(let origin):
            return origin
        }
    }
}

/// Pure mapping from a probe result + key material + the matched repository's
/// remote onto a single ``AccountIssue``. Everything impure (running `ssh-add`,
/// reading the key file, resolving the repo) happens before this is called.
enum AccountIssueClassifier {

    static func classify(
        account: Account,
        probe: HostProbeState,
        keyState: SSHKeyState?,
        matchedOriginURL: String? = nil
    ) -> AccountIssue? {
        if case .failed(let reason) = probe {
            return classifyFailure(account: account, reason: reason, keyState: keyState)
        }
        // Healthy rows stay silent unless the repository we just resolved would
        // bypass the alias entirely. No “all good” banner.
        guard let origin = matchedOriginURL else { return nil }
        return httpsRemoteIssue(account: account, originURL: origin)
    }

    private static func classifyFailure(
        account: Account,
        reason: String,
        keyState: SSHKeyState?
    ) -> AccountIssue {
        let keyPath = account.keyPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if let keyState, keyState.hasKeyPath, !keyState.privateKeyExists {
            return .keyFileMissing(path: keyPath)
        }
        if reason.lowercased().contains("key file missing"), !keyPath.isEmpty {
            return .keyFileMissing(path: keyPath)
        }
        // Only claim “locked” when the agent answered: with no agent running we
        // cannot tell a forgotten key from a rejected one.
        if let keyState,
           keyState.agentReachable,
           keyState.isEncrypted,
           !keyState.isLoadedInAgent,
           !keyPath.isEmpty {
            return .keyLocked(keyPath: keyPath)
        }
        if isReachabilityReason(reason) {
            return .unreachable(reason: reason)
        }
        return .authRejected(reason: reason)
    }

    /// Failures that no key action can fix.
    static func isReachabilityReason(_ reason: String) -> Bool {
        let lower = reason.lowercased()
        return lower.contains("host unreachable")
            || lower.contains("connection refused")
            || lower.contains("timed out")
            || lower.contains("host key")
            || lower.contains("could not resolve")
    }

    /// `.httpsRemote` when the remote is plain HTTP(S), the account has an SSH
    /// alias, and none of its configured `insteadOf` rules rewrite that URL.
    /// Nil for providers we have no preset host for — there would be no button.
    static func httpsRemoteIssue(account: Account, originURL: String) -> AccountIssue? {
        let origin = originURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isHTTPRemote(origin) else { return nil }
        guard !account.sshAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard !account.provider.insteadOfPresets(sshAlias: account.sshAlias).isEmpty else {
            return nil
        }
        guard !hasConfiguredRewrite(for: origin, account: account) else { return nil }
        return .httpsRemote(origin: origin)
    }

    static func isHTTPRemote(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://")
    }

    /// Only the rules keychord actually projects into gitconfig count here —
    /// the clone helper's built-in host defaults are not something git honors.
    static func hasConfiguredRewrite(for url: String, account: Account) -> Bool {
        let rules = account.urlRewrites.filter {
            !$0.from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return CloneURLRewriter.longestMatchingRule(rules: rules, url: url) != nil
    }
}
