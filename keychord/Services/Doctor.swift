import Foundation

enum Doctor {

    struct Input: Sendable {
        let model: ConfigModel
        let probeStates: [String: HostProbeState]
    }

    // MARK: - Pure entry point

    static func diagnose(_ input: Input) -> [Diagnosis] {
        var out: [Diagnosis] = []
        out += ruleDuplicateHosts(input.model.sshHosts)
        out += rulePort443WrongHost(input.model.sshHosts)
        out += ruleMissingHostKeyAlias(input.model.sshHosts)
        out += ruleProbeFailure(
            hosts: input.model.sshHosts,
            probes: input.probeStates
        )
        return out.sorted { $0.severity > $1.severity }
    }

    // MARK: - Convenience: run against the real system

    static func runAgainstCurrentSystem(
        model: ConfigModel,
        probeStates: [String: HostProbeState]
    ) async -> [Diagnosis] {
        diagnose(Input(
            model: model,
            probeStates: probeStates
        ))
    }

    // MARK: - Rule 1: duplicate Host blocks (SSH001)

    static func ruleDuplicateHosts(_ hosts: [SSHHost]) -> [Diagnosis] {
        struct Signature: Hashable {
            let hostName: String?
            let port: Int?
            let user: String?
            let identityFile: String?
            let identitiesOnly: Bool?
            let hostKeyAlias: String?
        }

        var groups: [Signature: [SSHHost]] = [:]
        for host in hosts {
            let sig = Signature(
                hostName: host.hostName,
                port: host.port,
                user: host.user,
                identityFile: host.identityFile,
                identitiesOnly: host.identitiesOnly,
                hostKeyAlias: host.hostKeyAlias
            )
            groups[sig, default: []].append(host)
        }

        return groups.values.filter { $0.count > 1 }.map { bucket in
            let sortedAliases = bucket.map(\.alias).sorted()
            // Keep the alias that equals the real hostname (e.g. "github.com");
            // otherwise keep the first after sorting and remove the rest.
            let realHost = bucket.first?.hostName ?? ""
            let keep = sortedAliases.first { $0.lowercased() == realHost.lowercased() }
                       ?? sortedAliases.first ?? ""
            let toRemove = sortedAliases.filter { $0 != keep }

            let fixes = toRemove.map { alias in
                FixOption(
                    label: "Remove \(alias)",
                    fixID: .ssh001_removeHost(alias: alias),
                    isDestructive: true
                )
            }

            return Diagnosis(
                severity: .warning,
                code: "SSH001",
                title: "Duplicate Host blocks",
                detail: "Hosts \(sortedAliases.joined(separator: ", ")) share identical HostName / Port / IdentityFile.",
                fixHint: fixes.isEmpty ? "Delete the redundant block or differentiate its IdentityFile/User." : nil,
                affectedFiles: ["~/.ssh/config"],
                fixes: fixes
            )
        }
    }

    // MARK: - Rule 2: Port 443 without ssh.github.com (SSH002)

    static func rulePort443WrongHost(_ hosts: [SSHHost]) -> [Diagnosis] {
        hosts.compactMap { host in
            guard host.port == 443 else { return nil }
            guard host.hostName != "ssh.github.com" else { return nil }
            return Diagnosis(
                severity: .error,
                code: "SSH002",
                title: "Port 443 without ssh.github.com",
                detail: "Host `\(host.alias)` uses Port 443 but HostName is `\(host.hostName ?? "<none>")`. GitHub's 443 fallback only works with HostName ssh.github.com.",
                fixHint: "Set HostName to ssh.github.com or remove Port 443.",
                affectedFiles: ["~/.ssh/config"]
            )
        }
    }

    // MARK: - Rule 3: missing HostKeyAlias with ssh.github.com (SSH003)

    static func ruleMissingHostKeyAlias(_ hosts: [SSHHost]) -> [Diagnosis] {
        hosts.compactMap { host in
            guard host.hostName == "ssh.github.com" else { return nil }
            guard host.hostKeyAlias != "github.com" else { return nil }
            return Diagnosis(
                severity: .warning,
                code: "SSH003",
                title: "Missing HostKeyAlias for 443 fallback",
                detail: "Host `\(host.alias)` uses ssh.github.com without `HostKeyAlias github.com`. known_hosts may flag a host-key mismatch.",
                fixHint: nil,
                affectedFiles: ["~/.ssh/config"],
                fixes: [
                    FixOption(
                        label: "Add HostKeyAlias",
                        fixID: .ssh003_addHostKeyAlias(alias: host.alias),
                        isDestructive: false
                    )
                ]
            )
        }
    }

    // MARK: - Rule 4: SSH probe failed for a host (NET001)

    static func ruleProbeFailure(
        hosts: [SSHHost],
        probes: [String: HostProbeState]
    ) -> [Diagnosis] {
        hosts.compactMap { host in
            guard let state = probes[host.alias],
                  case .failed(let reason) = state else { return nil }
            return Diagnosis(
                severity: .error,
                code: "NET001",
                title: "SSH probe failed",
                detail: "`\(host.alias)` cannot authenticate: \(reason).",
                fixHint: "Run `ssh -vT git@\(host.alias)` to debug.",
                affectedFiles: ["~/.ssh/config"]
            )
        }
    }
}
