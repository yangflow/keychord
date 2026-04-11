import Foundation

/// Persistent representation of a managed Git account. keychord owns
/// ~/.config/keychord/accounts.json — AccountsStore reads/writes it,
/// and AccountProjector turns the list into SSH config + gitconfig
/// managed files that feed into the user's real configs via Include
/// directives installed by IncludeInstaller.
struct Account: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var label: String
    var githubUsername: String
    var sshAlias: String
    var keyPath: String
    var keyFingerprint: String?
    var sshPort: SSHPort
    var gitUserName: String
    var gitUserEmail: String
    var scope: Scope
    var urlRewrites: [URLRewrite]
    var color: AccountColor
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    enum Scope: Codable, Equatable, Hashable, Sendable {
        case global
        case gitdir(String)

        var isScoped: Bool {
            if case .gitdir = self { return true }
            return false
        }

        var directory: String? {
            if case .gitdir(let path) = self { return path }
            return nil
        }
    }

    struct URLRewrite: Codable, Equatable, Hashable, Sendable {
        var from: String
        var to: String
    }

    enum AccountColor: String, Codable, CaseIterable, Sendable {
        case blue
        case green
        case orange
        case red
        case purple
        case yellow
    }

    enum SSHPort: Int, Codable, CaseIterable, Hashable, Sendable {
        case port22 = 22
        case port443 = 443

        var displayName: String {
            switch self {
            case .port22:  return "22"
            case .port443: return "443"
            }
        }
    }

    // Codable migration: existing accounts.json files that lack the
    // sshPort key will decode with the previous hardcoded default (443).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        label           = try c.decode(String.self, forKey: .label)
        githubUsername  = try c.decode(String.self, forKey: .githubUsername)
        sshAlias        = try c.decode(String.self, forKey: .sshAlias)
        keyPath         = try c.decode(String.self, forKey: .keyPath)
        keyFingerprint  = try c.decodeIfPresent(String.self, forKey: .keyFingerprint)
        sshPort         = try c.decodeIfPresent(SSHPort.self, forKey: .sshPort) ?? .port443
        gitUserName     = try c.decode(String.self, forKey: .gitUserName)
        gitUserEmail    = try c.decode(String.self, forKey: .gitUserEmail)
        scope           = try c.decode(Scope.self, forKey: .scope)
        urlRewrites     = try c.decode([URLRewrite].self, forKey: .urlRewrites)
        color           = try c.decode(AccountColor.self, forKey: .color)
        notes           = try c.decode(String.self, forKey: .notes)
        createdAt       = try c.decode(Date.self, forKey: .createdAt)
        updatedAt       = try c.decode(Date.self, forKey: .updatedAt)
        lastUsedAt      = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }

    init(
        id: UUID,
        label: String,
        githubUsername: String,
        sshAlias: String,
        keyPath: String,
        keyFingerprint: String?,
        sshPort: SSHPort,
        gitUserName: String,
        gitUserEmail: String,
        scope: Scope,
        urlRewrites: [URLRewrite],
        color: AccountColor,
        notes: String,
        createdAt: Date,
        updatedAt: Date,
        lastUsedAt: Date?
    ) {
        self.id = id
        self.label = label
        self.githubUsername = githubUsername
        self.sshAlias = sshAlias
        self.keyPath = keyPath
        self.keyFingerprint = keyFingerprint
        self.sshPort = sshPort
        self.gitUserName = gitUserName
        self.gitUserEmail = gitUserEmail
        self.scope = scope
        self.urlRewrites = urlRewrites
        self.color = color
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }
}

extension Account {
    static func new(
        label: String,
        sshAlias: String,
        keyPath: String,
        sshPort: SSHPort = .port443,
        gitUserName: String,
        gitUserEmail: String,
        scope: Scope = .global,
        color: AccountColor = .blue
    ) -> Account {
        let now = Date()
        return Account(
            id: UUID(),
            label: label,
            githubUsername: "",
            sshAlias: sshAlias,
            keyPath: keyPath,
            keyFingerprint: nil,
            sshPort: sshPort,
            gitUserName: gitUserName,
            gitUserEmail: gitUserEmail,
            scope: scope,
            urlRewrites: [],
            color: color,
            notes: "",
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil
        )
    }
}
