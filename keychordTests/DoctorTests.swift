import Testing
import Foundation
@testable import keychord

@Suite("Doctor")
struct DoctorTests {

    // MARK: - Input helper

    static func input(
        model: ConfigModel = ConfigModel(),
        probeStates: [String: HostProbeState] = [:]
    ) -> Doctor.Input {
        Doctor.Input(
            model: model,
            probeStates: probeStates
        )
    }

    // MARK: - Clean baseline

    @Test func cleanConfigReturnsNoDiagnoses() {
        var model = ConfigModel()
        model.sshHosts = [
            SSHHost(
                alias: "github.com",
                hostName: "ssh.github.com",
                port: 443,
                user: "git",
                identityFile: "~/.ssh/id_ed25519",
                identitiesOnly: true,
                hostKeyAlias: "github.com"
            )
        ]
        #expect(Doctor.diagnose(Self.input(model: model)).isEmpty)
    }

    // MARK: - SSH001 duplicate hosts

    @Test func detectsDuplicateHostBlocks() {
        var model = ConfigModel()
        model.sshHosts = [
            SSHHost(
                alias: "github.com",
                hostName: "ssh.github.com",
                port: 443,
                user: "git",
                identityFile: "~/.ssh/id_ed25519",
                identitiesOnly: true,
                hostKeyAlias: "github.com"
            ),
            SSHHost(
                alias: "github-yangflow",
                hostName: "ssh.github.com",
                port: 443,
                user: "git",
                identityFile: "~/.ssh/id_ed25519",
                identitiesOnly: true,
                hostKeyAlias: "github.com"
            ),
            SSHHost(
                alias: "github-work",
                hostName: "ssh.github.com",
                port: 443,
                user: "git",
                identityFile: "~/.ssh/id_rsa",
                identitiesOnly: true,
                hostKeyAlias: "github.com"
            )
        ]
        let hits = Doctor.diagnose(Self.input(model: model)).filter { $0.code == "SSH001" }
        #expect(hits.count == 1)
        #expect(hits[0].detail.contains("github.com"))
        #expect(hits[0].detail.contains("github-yangflow"))
        #expect(!hits[0].detail.contains("github-work"))
    }

    // MARK: - SSH002 Port 443 without ssh.github.com

    @Test func detectsPort443WithWrongHostName() {
        var model = ConfigModel()
        model.sshHosts = [
            SSHHost(alias: "weird", hostName: "github.com", port: 443)
        ]
        let hits = Doctor.diagnose(Self.input(model: model)).filter { $0.code == "SSH002" }
        #expect(hits.count == 1)
        #expect(hits[0].severity == .error)
    }

    // MARK: - SSH003 missing HostKeyAlias

    @Test func detectsMissingHostKeyAlias() {
        var model = ConfigModel()
        model.sshHosts = [
            SSHHost(alias: "gh", hostName: "ssh.github.com", port: 443, hostKeyAlias: nil)
        ]
        let hits = Doctor.diagnose(Self.input(model: model)).filter { $0.code == "SSH003" }
        #expect(hits.count == 1)
    }

    // MARK: - NET001 probe failure

    @Test func detectsProbeFailure() {
        var model = ConfigModel()
        model.sshHosts = [SSHHost(alias: "github.com")]
        let probes: [String: HostProbeState] = [
            "github.com": .failed(reason: "permission denied")
        ]
        let hits = Doctor.diagnose(Self.input(
            model: model,
            probeStates: probes
        )).filter { $0.code == "NET001" }
        #expect(hits.count == 1)
        #expect(hits[0].severity == .error)
    }

    @Test func probeSuccessProducesNoDiagnosis() {
        var model = ConfigModel()
        model.sshHosts = [SSHHost(alias: "github.com")]
        let probes: [String: HostProbeState] = [
            "github.com": .ok(username: "yangflow")
        ]
        let hits = Doctor.diagnose(Self.input(
            model: model,
            probeStates: probes
        )).filter { $0.code == "NET001" }
        #expect(hits.isEmpty)
    }

    // MARK: - Severity ordering

    @Test func diagnosesAreSortedBySeverityDescending() {
        var model = ConfigModel()
        model.sshHosts = [
            SSHHost(alias: "weird", hostName: "github.com", port: 443),  // SSH002 error
            SSHHost(alias: "gh", hostName: "ssh.github.com", port: 443)  // SSH003 warning
        ]
        let probes: [String: HostProbeState] = [
            "weird": .failed(reason: "connection refused")               // NET001 error
        ]
        let all = Doctor.diagnose(Self.input(model: model, probeStates: probes))
        #expect(all.count >= 2)
        let severities = all.map(\.severity)
        #expect(severities == severities.sorted(by: >))
    }
}
