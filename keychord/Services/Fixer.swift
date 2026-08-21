import Foundation

/// Executes a FixID against the live config files. Every write goes
/// through ConfigStore's save paths so any mistaken fix can be
/// recovered from the accounts snapshot restore.
enum Fixer {

    enum FixError: Swift.Error, CustomStringConvertible {
        case sshConfigReadFailed(underlying: Swift.Error)
        case hostNotFound(alias: String)
        case saveFailed(underlying: Swift.Error)

        var description: String {
            switch self {
            case .sshConfigReadFailed(let e):
                return String.loc("Could not read SSH config: \(e.localizedDescription)")
            case .hostNotFound(let a):
                return String.loc("Host `\(a)` is no longer in the SSH config")
            case .saveFailed(let e):
                return String.loc("Failed to save SSH config: \(e.localizedDescription)")
            }
        }
    }

    /// Run a fix. Caller is expected to trigger a UI refresh afterwards
    /// so the Doctor section re-evaluates.
    ///
    /// `accounts` / `managedPaths` are only read by fixes that regenerate the
    /// managed files; SSH-config fixes ignore them.
    static func execute(
        _ fix: FixID,
        sshConfigPath: String,
        gitConfigPath: String,
        accounts: [Account] = [],
        managedPaths: AccountProjector.ManagedPaths = .default
    ) async throws {
        switch fix {
        case .ssh001_removeHost(let alias):
            try mutateSSHConfig(at: sshConfigPath) { doc in
                guard doc.removeHost(alias: alias) else {
                    throw FixError.hostNotFound(alias: alias)
                }
            }

        case .ssh003_addHostKeyAlias(let alias):
            try mutateSSHConfig(at: sshConfigPath) { doc in
                guard doc.setField("HostKeyAlias", to: "github.com", forHost: alias) else {
                    throw FixError.hostNotFound(alias: alias)
                }
            }

        case .git001_reprojectManagedFiles:
            try AccountProjector.regenerate(accounts: accounts, paths: managedPaths)
        }
    }

    // MARK: - SSH config mutation helper

    private static func mutateSSHConfig(
        at path: String,
        _ mutation: (inout SSHConfigDocument) throws -> Void
    ) throws {
        let text: String
        do {
            text = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw FixError.sshConfigReadFailed(underlying: error)
        }
        var doc = SSHConfigDocument.parse(text)
        try mutation(&doc)
        do {
            try ConfigStore.saveSSHConfig(doc, to: path)
        } catch {
            throw FixError.saveFailed(underlying: error)
        }
    }
}
