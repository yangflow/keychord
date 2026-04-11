import Foundation

struct ConfigStore {

    enum LoadError: Swift.Error, CustomStringConvertible {
        case sshConfigReadFailed(path: String, underlying: Swift.Error)
        case gitConfigReadFailed(path: String, underlying: Swift.Error)

        var description: String {
            switch self {
            case .sshConfigReadFailed(let p, let e):
                return "Failed to read \(p): \(e.localizedDescription)"
            case .gitConfigReadFailed(let p, let e):
                return "Failed to read \(p): \(e.localizedDescription)"
            }
        }
    }

    enum SaveError: Swift.Error, CustomStringConvertible {
        case roundTripVerificationFailed(path: String)
        case writeFailed(path: String, underlying: Swift.Error)

        var description: String {
            switch self {
            case .roundTripVerificationFailed(let p):
                return "After writing \(p), re-parsed content did not match the source document"
            case .writeFailed(let p, let e):
                return "Failed to write \(p): \(e.localizedDescription)"
            }
        }
    }

    static func loadFromDefaultLocations() throws -> ConfigModel {
        var model = ConfigModel()

        // 1. SSH config (follow Include directives one level deep)
        let sshPath = Self.expand("~/.ssh/config")
        if FileManager.default.fileExists(atPath: sshPath) {
            do {
                let text = try String(contentsOfFile: sshPath, encoding: .utf8)
                let doc = SSHConfigDocument.parse(text)
                model.sshHosts = doc.extractHosts()

                for line in doc.lines {
                    if case .include(let path) = line.kind {
                        let resolved = Self.expand(path)
                        guard FileManager.default.fileExists(atPath: resolved) else { continue }
                        let subText = try String(contentsOfFile: resolved, encoding: .utf8)
                        let subDoc = SSHConfigDocument.parse(subText)
                        model.sshHosts.append(contentsOf: subDoc.extractHosts())
                    }
                }
            } catch {
                throw LoadError.sshConfigReadFailed(path: sshPath, underlying: error)
            }
        }

        // 2. Main gitconfig + follow includeIf
        let gitPath = Self.expand("~/.gitconfig")
        if FileManager.default.fileExists(atPath: gitPath) {
            do {
                let io = GitConfigIO(filePath: gitPath)
                let ex = try io.extractModel()
                if let id = ex.identity {
                    model.gitIdentities.append(id)
                }
                model.insteadOfRules.append(contentsOf: ex.insteadOf)
                model.includeIfRules.append(contentsOf: ex.includeIf)

                for rule in ex.includeIf {
                    let includePath = Self.expand(rule.path)
                    guard FileManager.default.fileExists(atPath: includePath) else {
                        continue
                    }
                    let subIO = GitConfigIO(filePath: includePath)
                    let subEx = try subIO.extractModel(includeCondition: rule.condition)
                    if let id = subEx.identity {
                        model.gitIdentities.append(id)
                    }
                    model.insteadOfRules.append(contentsOf: subEx.insteadOf)
                }
            } catch {
                throw LoadError.gitConfigReadFailed(path: gitPath, underlying: error)
            }
        }

        return model
    }

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    // MARK: - Writes

    /// Back up the existing SSH config (if any), then atomically write the
    /// serialized document. Re-reads the file and verifies that the parsed
    /// content matches the source document.
    static func saveSSHConfig(
        _ doc: SSHConfigDocument,
        to path: String,
        backups: BackupService = BackupService()
    ) throws {
        if FileManager.default.fileExists(atPath: path) {
            _ = try backups.backup(originalPath: path)
        }

        let text = doc.serialize()
        do {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            throw SaveError.writeFailed(path: path, underlying: error)
        }

        let reread = try String(contentsOfFile: path, encoding: .utf8)
        let reparsed = SSHConfigDocument.parse(reread)
        guard reparsed == doc else {
            throw SaveError.roundTripVerificationFailed(path: path)
        }
    }

    /// Back up the given gitconfig (if it exists), then pass a GitConfigIO
    /// into the mutation closure so the caller can run set/add/unsetAll.
    /// `git config --file` writes are themselves atomic.
    static func modifyGitConfig(
        at path: String,
        backups: BackupService = BackupService(),
        _ mutation: (GitConfigIO) throws -> Void
    ) throws {
        if FileManager.default.fileExists(atPath: path) {
            _ = try backups.backup(originalPath: path)
        }
        let io = GitConfigIO(filePath: path)
        try mutation(io)
    }
}
