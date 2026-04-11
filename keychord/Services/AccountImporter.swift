import Foundation

/// Pure transform from a freshly-loaded ConfigModel (SSH hosts + git
/// identities + url rewrites) into a list of persistent `Account`
/// records ready to drop into AccountsStore. Used once, on first run,
/// when the user clicks "Import existing" in the accounts window.
///
/// The importer folds in the logic that AccountDetector used to do:
///   - group SSH Host blocks that share a key,
///   - link each group to the git identity referenced by sshCommand,
///   - fall back to the global [user] for default-named hosts,
///   - attach url rewrites whose `to` targets the group's alias.
/// It then maps each inferred group into a fresh `Account` with a
/// UUID, round-robin color, and label derived from the git name (or
/// alias when nameless).
enum AccountImporter {

    /// Walk the model and return a persistent `Account` per detected
    /// logical account. Deterministic: same model in → same records
    /// out (modulo UUIDs, which are fresh per call).
    static func importFromExistingConfig(_ model: ConfigModel) -> [Account] {
        let candidates = detectCandidates(from: model)
        return candidates.enumerated().map { index, c in
            makeRecord(from: c, colorIndex: index)
        }
    }

    // MARK: - Candidate detection (folded in from the old AccountDetector)

    /// Intermediate grouping used while walking the model. Never leaves
    /// this file — callers only ever see finished `Account` records.
    private struct Candidate {
        var aliases: [String]
        var keyPath: String?
        var sshPort: Account.SSHPort?
        var userName: String?
        var userEmail: String?
        var scopeCondition: String?
        var urlRewrites: [InsteadOfRule]
    }

    private static func detectCandidates(from model: ConfigModel) -> [Candidate] {
        var candidates: [Candidate] = []
        for host in model.sshHosts {
            let detectedPort: Account.SSHPort? = {
                if host.port == 443 || host.hostName == "ssh.github.com" {
                    return .port443
                } else if host.port == 22 || host.port == nil {
                    return .port22
                }
                return nil
            }()
            var c = Candidate(
                aliases: [host.alias],
                keyPath: host.identityFile.map(Self.expand),
                sshPort: detectedPort,
                userName: nil,
                userEmail: nil,
                scopeCondition: nil,
                urlRewrites: []
            )

            // Strongest signal: an identity whose sshCommand references this key.
            if let linked = linkIdentityBySSHCommand(host: host, identities: model.gitIdentities) {
                c.userName = linked.name
                c.userEmail = linked.email
                c.scopeCondition = linked.includeCondition
            }

            // Default-host fallback: hostname == alias (or the literal
            // "github.com") binds the global [user] identity.
            if c.userName == nil, isDefaultHost(host) {
                if let global = model.gitIdentities.first(where: { $0.includeCondition == nil }) {
                    c.userName = global.name
                    c.userEmail = global.email
                }
            }

            // URL rewrites whose target contains git@<alias>:
            c.urlRewrites = model.insteadOfRules.filter { rule in
                rewriteBelongsTo(rule: rule, alias: host.alias)
            }

            candidates.append(c)
        }
        return merge(candidates)
    }

    // MARK: - Heuristics

    private static func isDefaultHost(_ host: SSHHost) -> Bool {
        let alias = host.alias.lowercased()
        let hostName = host.hostName?.lowercased() ?? ""
        return alias == "github.com" || (hostName.isEmpty ? false : alias == hostName)
    }

    private static func rewriteBelongsTo(rule: InsteadOfRule, alias: String) -> Bool {
        rule.to.contains("@\(alias):") || rule.to.contains("@\(alias)/")
    }

    private static func linkIdentityBySSHCommand(
        host: SSHHost,
        identities: [GitIdentity]
    ) -> GitIdentity? {
        guard let rawKey = host.identityFile else { return nil }
        let expandedKey = Self.expand(rawKey)
        return identities.first { identity in
            guard let cmd = identity.sshCommand else { return false }
            return cmd.contains(rawKey) || cmd.contains(expandedKey)
        }
    }

    // MARK: - Merge duplicates

    /// Collapse candidates sharing the same keyPath + compatible identity
    /// (same name/email, or one side has nil). Handles the common case
    /// where `github.com` and `github-yangflow` both reference the same
    /// key and should end up as one logical account.
    private static func merge(_ cands: [Candidate]) -> [Candidate] {
        var merged: [Candidate] = []
        for c in cands {
            if let idx = merged.firstIndex(where: { canMerge($0, c) }) {
                var e = merged[idx]
                e.aliases.append(contentsOf: c.aliases)
                if e.userName == nil { e.userName = c.userName }
                if e.userEmail == nil { e.userEmail = c.userEmail }
                if e.sshPort == nil { e.sshPort = c.sshPort }
                if e.scopeCondition == nil { e.scopeCondition = c.scopeCondition }
                for r in c.urlRewrites where !e.urlRewrites.contains(r) {
                    e.urlRewrites.append(r)
                }
                merged[idx] = e
            } else {
                merged.append(c)
            }
        }
        return merged
    }

    private static func canMerge(_ a: Candidate, _ b: Candidate) -> Bool {
        guard let aKey = a.keyPath, let bKey = b.keyPath, aKey == bKey else {
            return false
        }
        if a.userName == nil || b.userName == nil { return true }
        return a.userName == b.userName && a.userEmail == b.userEmail
    }

    // MARK: - Candidate → Account mapping

    private static func makeRecord(from c: Candidate, colorIndex: Int) -> Account {
        let now = Date()
        let scope = mapScope(conditionString: c.scopeCondition)
        let rewrites = c.urlRewrites.map { Account.URLRewrite(from: $0.from, to: $0.to) }

        let primaryAlias = c.aliases.first ?? ""
        let label = (c.userName?.isEmpty == false) ? c.userName! : primaryAlias

        let palette = Account.AccountColor.allCases
        let color = palette[colorIndex % palette.count]

        return Account(
            id: UUID(),
            label: label,
            githubUsername: "",
            sshAlias: primaryAlias,
            keyPath: c.keyPath ?? "",
            keyFingerprint: nil,
            sshPort: c.sshPort ?? .port443,
            gitUserName: c.userName ?? "",
            gitUserEmail: c.userEmail ?? "",
            scope: scope,
            urlRewrites: rewrites,
            color: color,
            notes: "",
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil
        )
    }

    private static func mapScope(conditionString: String?) -> Account.Scope {
        guard let cond = conditionString, cond.hasPrefix("gitdir:") else {
            return .global
        }
        return .gitdir(String(cond.dropFirst("gitdir:".count)))
    }

    private static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
