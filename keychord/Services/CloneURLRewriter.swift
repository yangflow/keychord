import Foundation

/// Pure helper that turns `org/repo` or a pasted clone URL into a
/// `git clone git@<alias>:…` command for one Account.
///
/// Uses the account's SSH alias, provider host defaults, and any
/// configured `urlRewrites`. Read-only — never writes config or
/// accounts.json.
enum CloneURLRewriter {

    /// Full clipboard-ready command, e.g. `git clone git@github-work:org/repo.git`.
    /// `nil` when the alias is blank or the input cannot be interpreted.
    static func cloneCommand(for account: Account, input: String) -> String? {
        guard let url = rewriteURL(for: account, input: input) else { return nil }
        return "git clone \(url)"
    }

    /// Rewritten SSH URL only (no `git clone` prefix).
    static func rewriteURL(for account: Account, input: String) -> String? {
        let alias = account.sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { return nil }

        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        // Allow pasting a full command; we only need the URL operand.
        if let stripped = stripGitClonePrefix(raw) {
            raw = stripped
        }

        if let path = parseOwnerRepoPath(raw) {
            return "git@\(alias):\(ensureGitSuffix(path))"
        }

        let targetPrefix = "git@\(alias):"
        if raw.hasPrefix(targetPrefix) {
            return raw
        }

        let rules = effectiveRewriteRules(for: account, alias: alias)
        if let match = longestMatchingRule(rules: rules, url: raw) {
            let remainder = String(raw.dropFirst(match.from.count))
            return match.to + remainder
        }

        // Last resort: peel owner/repo out of any git@ / https remote so a
        // dropped repo's origin still yields a clone command for this alias.
        if let path = ownerRepoPath(fromRemoteURL: raw) {
            return "git@\(alias):\(ensureGitSuffix(path))"
        }
        return nil
    }

    /// One-liner that repoints an existing HTTPS remote at the account's SSH
    /// alias: `git remote set-url origin git@<alias>:owner/repo.git`.
    ///
    /// Host and transport change; the path (subgroups included) is carried over
    /// and ends in `.git`, the same canonical form the clone helper produces.
    /// `nil` when the remote is already SSH (nothing to fix) or cannot be
    /// rewritten for this account — the card must not offer a command that
    /// would point `origin` somewhere wrong.
    static func remoteSetURLCommand(
        for account: Account,
        originURL: String,
        remoteName: String = "origin"
    ) -> String? {
        let origin = originURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = origin.lowercased()
        guard lower.hasPrefix("https://") || lower.hasPrefix("http://") else { return nil }
        guard let rewritten = rewriteURL(for: account, input: origin) else { return nil }
        var url = rewritten
        while url.hasSuffix("/") { url = String(url.dropLast()) }
        guard !url.isEmpty else { return nil }
        return "git remote set-url \(remoteName) \(ensureGitSuffix(url))"
    }

    /// Best field value for the popover after a folder drop/choose: prefer
    /// `owner/repo` (always rewriteable from alias alone), else the raw URL.
    static func preferredCloneInput(fromOriginURL origin: String) -> String {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return ownerRepoPath(fromRemoteURL: trimmed) ?? trimmed
    }

    /// `owner/repo` (no `.git`) extracted from common remote URL shapes.
    static func ownerRepoPath(fromRemoteURL input: String) -> String? {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if let stripped = stripGitClonePrefix(raw) {
            raw = stripped
        }

        // git@host:owner/repo(.git)
        let sshPattern = #"^[^@\s]+@[^:\s]+:(.+)$"#
        if let regex = try? NSRegularExpression(pattern: sshPattern) {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            if let match = regex.firstMatch(in: raw, range: range),
               match.numberOfRanges >= 2,
               let pathRange = Range(match.range(at: 1), in: raw) {
                return normalizeOwnerRepoPath(String(raw[pathRange]))
            }
        }

        // https://host/owner/repo.git  or  ssh://git@host/owner/repo.git
        if let url = URL(string: raw), url.scheme != nil {
            var path = url.path
            while path.hasPrefix("/") { path = String(path.dropFirst()) }
            return normalizeOwnerRepoPath(path)
        }

        return nil
    }

    private static func normalizeOwnerRepoPath(_ path: String) -> String? {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed = String(trimmed.dropLast())
        }
        if trimmed.hasSuffix(".git") {
            trimmed = String(trimmed.dropLast(4))
        }
        return parseOwnerRepoPath(trimmed)
    }

    // MARK: - Rules

    /// Account `urlRewrites` plus provider-host defaults onto `git@alias:`.
    /// Longer `from` prefixes win when several match (git insteadOf style).
    static func effectiveRewriteRules(for account: Account, alias: String) -> [Account.URLRewrite] {
        var rules = account.urlRewrites.filter {
            !$0.from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let host = account.provider.host {
            let defaults: [Account.URLRewrite] = [
                Account.URLRewrite(from: "https://\(host)/", to: "git@\(alias):"),
                Account.URLRewrite(from: "http://\(host)/", to: "git@\(alias):"),
                Account.URLRewrite(from: "git@\(host):", to: "git@\(alias):"),
                Account.URLRewrite(from: "ssh://git@\(host)/", to: "git@\(alias):"),
            ]
            for preset in defaults {
                if !rules.contains(where: { $0.from == preset.from }) {
                    rules.append(preset)
                }
            }
        }
        return rules
    }

    static func longestMatchingRule(
        rules: [Account.URLRewrite],
        url: String
    ) -> Account.URLRewrite? {
        rules
            .filter { url.hasPrefix($0.from) }
            .max(by: { $0.from.count < $1.from.count })
    }

    // MARK: - Parsing

    /// `owner/repo` or `owner/group/repo` (+ optional `.git`), no scheme / `@`.
    static func parseOwnerRepoPath(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") || trimmed.contains("@") { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") { return nil }

        let pattern = #"^[^/\s]+(?:/[^/\s]+)+$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard regex.firstMatch(in: trimmed, range: range) != nil else { return nil }
        return trimmed
    }

    static func ensureGitSuffix(_ path: String) -> String {
        if path.hasSuffix(".git") { return path }
        return path + ".git"
    }

    /// Strips a leading `git clone` (and optional flags before the URL).
    /// Returns the last whitespace-separated token when the line starts
    /// with `git clone`; otherwise `nil`.
    static func stripGitClonePrefix(_ input: String) -> String? {
        let lower = input.lowercased()
        guard lower.hasPrefix("git clone") else { return nil }
        let parts = input.split(whereSeparator: \.isWhitespace).map(String.init)
        // Need at least: git, clone, <url>
        guard parts.count >= 3 else { return nil }
        return parts.last
    }
}

extension Account {
    /// Convenience: `git clone …` for this account, or `nil`.
    func cloneCommand(for input: String) -> String? {
        CloneURLRewriter.cloneCommand(for: self, input: input)
    }
}
