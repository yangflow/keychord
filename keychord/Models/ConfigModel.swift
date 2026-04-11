import Foundation

// MARK: - SSH

struct SSHHost: Equatable, Identifiable, Hashable, Sendable {
    var alias: String
    var hostName: String?
    var port: Int?
    var user: String?
    var identityFile: String?
    var identitiesOnly: Bool?
    var hostKeyAlias: String?
    var proxyCommand: String?
    var proxyJump: String?
    var extraDirectives: [SSHDirective] = []

    var id: String { alias }
}

struct SSHDirective: Equatable, Hashable, Sendable {
    var key: String
    var value: String
}

struct SSHKey: Equatable, Identifiable, Hashable, Sendable {
    var privateKeyPath: String
    var publicKeyPath: String?
    var keyType: String
    var fingerprint: String?
    var probedGitHubUser: String?
    var fileMode: UInt16?
    var referencedByHosts: [String] = []

    var id: String { privateKeyPath }
}

// MARK: - Git config

struct GitIdentity: Equatable, Identifiable, Hashable, Sendable {
    var name: String
    var email: String
    var sourceFile: String
    var includeCondition: String?
    var sshCommand: String?

    var id: String { "\(sourceFile)::\(email)" }
}

struct InsteadOfRule: Equatable, Identifiable, Hashable, Sendable {
    var from: String
    var to: String
    var sourceFile: String
    var direction: Direction

    var id: String { "\(direction.rawValue)::\(from)→\(to)::\(sourceFile)" }

    enum Direction: String, Hashable, Sendable {
        case insteadOf
        case pushInsteadOf
    }
}

struct IncludeIfRule: Equatable, Identifiable, Hashable, Sendable {
    var condition: String
    var path: String
    var sourceFile: String

    var id: String { "\(sourceFile)::\(condition)→\(path)" }
}

// MARK: - Root model

struct ConfigModel: Equatable, Sendable {
    var sshHosts: [SSHHost] = []
    var sshKeys: [SSHKey] = []
    var gitIdentities: [GitIdentity] = []
    var insteadOfRules: [InsteadOfRule] = []
    var includeIfRules: [IncludeIfRule] = []
}
