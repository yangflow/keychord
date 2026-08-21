import Foundation

/// Persistent representation of a managed Git account. keychord owns
/// ~/.config/keychord/accounts.json — AccountsStore reads/writes it,
/// and AccountProjector turns the list into SSH config + gitconfig
/// managed files that feed into the user's real configs via Include
/// directives installed by IncludeInstaller.
struct Account: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var label: String
    /// Git forge username (provider-agnostic). Older JSON used `githubUsername`.
    var username: String
    var provider: Provider
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

    /// Git forge / host family for this account. Drives SSH-settings
    /// deep links and one-click `insteadOf` presets. Missing in older
    /// accounts.json → decode as `.github`.
    enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
        case github
        case gitlab
        case gitea
        case custom

        var id: String { rawValue }

        /// Forge name for filter chips. Brand names stay untranslated.
        var displayName: String {
            switch self {
            case .github: return "GitHub"
            case .gitlab: return "GitLab"
            case .gitea:  return "Gitea"
            case .custom: return String(localized: "Custom")
            }
        }

        /// Canonical public hostname used by rewrite presets (nil for custom).
        var host: String? {
            switch self {
            case .github: return "github.com"
            case .gitlab: return "gitlab.com"
            case .gitea:  return "gitea.com"
            case .custom: return nil
            }
        }

        /// User-facing page for adding SSH public keys, when the forge
        /// has a known settings URL. Custom has none — callers must
        /// not invent a GitHub URL.
        var sshSettingsURL: URL? {
            switch self {
            case .github:
                return URL(string: "https://github.com/settings/keys")
            case .gitlab:
                return URL(string: "https://gitlab.com/-/user_settings/ssh_keys")
            case .gitea:
                return URL(string: "https://gitea.com/user/settings/keys")
            case .custom:
                return nil
            }
        }

        /// One-click `insteadOf` pairs for this provider's common HTTPS
        /// and SSH clone URLs, rewriting onto `git@<sshAlias>:`.
        /// Empty when the alias is blank, or for `.custom`.
        func insteadOfPresets(sshAlias: String) -> [URLRewrite] {
            let alias = sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alias.isEmpty, let host else { return [] }
            let target = "git@\(alias):"
            return [
                URLRewrite(from: "https://\(host)/", to: target),
                URLRewrite(from: "git@\(host):", to: target),
            ]
        }
    }

    enum Scope: Equatable, Hashable, Sendable {
        case global
        /// One or more `gitdir:` prefixes. The projector writes one
        /// `includeIf` per path, so an account can own `~/work/` and
        /// `~/src/new-app/` at the same time.
        case gitdir(paths: [String])

        /// Single-directory convenience for call sites that own exactly one
        /// path (folder pickers, importer, fixtures).
        static func gitdir(_ path: String) -> Scope {
            .gitdir(paths: [path])
        }

        var isScoped: Bool {
            if case .gitdir = self { return true }
            return false
        }

        /// Every `gitdir:` path, in declaration order. Empty for `.global`.
        var directories: [String] {
            if case .gitdir(let paths) = self { return paths }
            return []
        }

        /// First `gitdir:` path — the one the single-directory editors show.
        var directory: String? {
            directories.first
        }
    }

    struct URLRewrite: Codable, Equatable, Hashable, Sendable {
        var from: String
        var to: String
    }

    /// Account accent color. Stored as a string in accounts.json:
    /// legacy named presets (`blue`, `green`, …) or `#RRGGBB` / `#RRGGBBAA`.
    struct AccountColor: Codable, Equatable, Hashable, Sendable, RawRepresentable {
        var rawValue: String

        static let blue = AccountColor(rawValue: "blue")
        static let green = AccountColor(rawValue: "green")
        static let orange = AccountColor(rawValue: "orange")
        static let red = AccountColor(rawValue: "red")
        static let purple = AccountColor(rawValue: "purple")
        static let yellow = AccountColor(rawValue: "yellow")

        /// Named presets used when assigning colors to imported accounts.
        static let presets: [AccountColor] = [
            .blue, .green, .orange, .red, .purple, .yellow,
        ]

        /// Alias for ``presets`` — keeps importer / tests that cycle colors working.
        static var allCases: [AccountColor] { presets }

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// Persist an opaque sRGB color as `#RRGGBB`.
        init(sRGBRed red: Double, green: Double, blue: Double) {
            let r = Self.byte(red)
            let g = Self.byte(green)
            let b = Self.byte(blue)
            self.rawValue = String(format: "#%02X%02X%02X", r, g, b)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            rawValue = try container.decode(String.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        /// sRGB 0…1 components when `rawValue` is a hex color; `nil` for named presets.
        var sRGBComponents: (red: Double, green: Double, blue: Double, alpha: Double)? {
            Self.parseHex(rawValue)
        }

        private static func byte(_ unit: Double) -> Int {
            Int((min(max(unit, 0), 1) * 255.0).rounded())
        }

        private static func parseHex(_ raw: String) -> (Double, Double, Double, Double)? {
            var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if hex.hasPrefix("#") { hex.removeFirst() }
            guard hex.count == 6 || hex.count == 8,
                  let value = UInt32(hex, radix: 16) else {
                return nil
            }
            if hex.count == 6 {
                let r = Double((value >> 16) & 0xFF) / 255
                let g = Double((value >> 8) & 0xFF) / 255
                let b = Double(value & 0xFF) / 255
                return (r, g, b, 1)
            }
            let r = Double((value >> 24) & 0xFF) / 255
            let g = Double((value >> 16) & 0xFF) / 255
            let b = Double((value >> 8) & 0xFF) / 255
            let a = Double(value & 0xFF) / 255
            return (r, g, b, a)
        }
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

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case username
        case githubUsername
        case provider
        case sshAlias
        case keyPath
        case keyFingerprint
        case sshPort
        case gitUserName
        case gitUserEmail
        case scope
        case urlRewrites
        case color
        case notes
        case createdAt
        case updatedAt
        case lastUsedAt
    }

    // Codable migration:
    // - missing `provider` → `.github`
    // - missing `sshPort` → `.port443`
    // - `username` preferred; fall back to legacy `githubUsername`
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        label           = try c.decode(String.self, forKey: .label)
        if let modern = try c.decodeIfPresent(String.self, forKey: .username) {
            username = modern
        } else {
            username = try c.decodeIfPresent(String.self, forKey: .githubUsername) ?? ""
        }
        provider        = try c.decodeIfPresent(Provider.self, forKey: .provider) ?? .github
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

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encode(username, forKey: .username)
        try c.encode(provider, forKey: .provider)
        try c.encode(sshAlias, forKey: .sshAlias)
        try c.encode(keyPath, forKey: .keyPath)
        try c.encodeIfPresent(keyFingerprint, forKey: .keyFingerprint)
        try c.encode(sshPort, forKey: .sshPort)
        try c.encode(gitUserName, forKey: .gitUserName)
        try c.encode(gitUserEmail, forKey: .gitUserEmail)
        try c.encode(scope, forKey: .scope)
        try c.encode(urlRewrites, forKey: .urlRewrites)
        try c.encode(color, forKey: .color)
        try c.encode(notes, forKey: .notes)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
    }

    init(
        id: UUID,
        label: String,
        username: String,
        provider: Provider = .github,
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
        self.username = username
        self.provider = provider
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

    /// Merge this provider's rewrite presets into `urlRewrites` without
    /// duplicating identical from/to pairs. No-op for custom / empty alias.
    mutating func applyInsteadOfPreset() {
        let presets = provider.insteadOfPresets(sshAlias: sshAlias)
        for preset in presets {
            if !urlRewrites.contains(where: { $0.from == preset.from && $0.to == preset.to }) {
                urlRewrites.append(preset)
            }
        }
    }
}

/// Hand-rolled so a multi-path scope still loads on a build that only knew
/// `gitdir(String)`: the synthesized `_0` key keeps carrying the first path
/// while `paths` carries the whole list.
extension Account.Scope: Codable {
    private enum CaseKey: String, CodingKey {
        case global
        case gitdir
    }

    private enum GitdirKey: String, CodingKey {
        case singlePath = "_0"
        case paths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CaseKey.self)
        if container.contains(.gitdir) {
            let nested = try container.nestedContainer(
                keyedBy: GitdirKey.self,
                forKey: .gitdir
            )
            if let paths = try nested.decodeIfPresent([String].self, forKey: .paths) {
                self = .gitdir(paths: paths)
            } else if let single = try? nested.decode(String.self, forKey: .singlePath) {
                self = .gitdir(paths: [single])
            } else {
                self = .gitdir(paths: try nested.decode([String].self, forKey: .singlePath))
            }
            return
        }
        guard container.contains(.global) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unrecognized Account.Scope payload"
                )
            )
        }
        self = .global
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CaseKey.self)
        switch self {
        case .global:
            _ = container.nestedContainer(keyedBy: GitdirKey.self, forKey: .global)
        case .gitdir(let paths):
            var nested = container.nestedContainer(
                keyedBy: GitdirKey.self,
                forKey: .gitdir
            )
            try nested.encode(paths.first ?? "", forKey: .singlePath)
            try nested.encode(paths, forKey: .paths)
        }
    }
}

extension Account {
    static func new(
        label: String,
        sshAlias: String,
        keyPath: String,
        sshPort: SSHPort = .port443,
        provider: Provider = .github,
        gitUserName: String,
        gitUserEmail: String,
        scope: Scope = .global,
        color: AccountColor = .blue
    ) -> Account {
        let now = Date()
        return Account(
            id: UUID(),
            label: label,
            username: "",
            provider: provider,
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
