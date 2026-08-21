import Testing
import Foundation
@testable import keychord

@Suite("Doctor")
struct DoctorTests {

    // MARK: - Input helper

    static func input(
        model: ConfigModel = ConfigModel(),
        probeStates: [String: HostProbeState] = [:],
        identityAudit: IdentityAudit? = nil
    ) -> Doctor.Input {
        Doctor.Input(
            model: model,
            probeStates: probeStates,
            identityAudit: identityAudit
        )
    }

    static func account(
        label: String,
        email: String,
        scope: Account.Scope = .gitdir("~/work/")
    ) -> Account {
        Account.new(
            label: label,
            sshAlias: "github-work",
            keyPath: "~/.ssh/id_work",
            gitUserName: label,
            gitUserEmail: email,
            scope: scope
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

    // MARK: - NET001 offers no buttons (they live under the account row)

    @Test func probeFailureDiagnosisCarriesNoFixButtons() {
        var model = ConfigModel()
        model.sshHosts = [SSHHost(alias: "github.com")]
        let hits = Doctor.diagnose(Self.input(
            model: model,
            probeStates: ["github.com": .failed(reason: "permission denied")]
        )).filter { $0.code == "NET001" }
        #expect(hits.count == 1)
        #expect(hits[0].fixes.isEmpty)
    }

    // MARK: - GIT001 git author vs SSH identity

    @Test func cleanAuditProducesNoIdentityDiagnosis() {
        let work = Self.account(label: "Work", email: "work@company.com")
        let audit = IdentityAudit.audit(
            account: work,
            repoRoot: "/tmp/repo",
            identity: CurrentRepoResolver.EffectiveGitIdentity(
                userName: "Work",
                userEmail: "work@company.com",
                sshCommand: nil
            ),
            accounts: [work]
        )
        #expect(Doctor.ruleIdentityMismatch(audit).isEmpty)
        #expect(Doctor.ruleIdentityMismatch(nil).isEmpty)
    }

    @Test func detectsAuthorPushingAsADifferentAccount() {
        let work = Self.account(label: "Work", email: "work@company.com")
        let personal = Self.account(
            label: "Personal",
            email: "me@example.com",
            scope: .global
        )
        let audit = IdentityAudit.audit(
            account: work,
            repoRoot: "/tmp/repo",
            identity: CurrentRepoResolver.EffectiveGitIdentity(
                userName: "Me",
                userEmail: "me@example.com",
                sshCommand: nil
            ),
            accounts: [work, personal]
        )
        let hits = Doctor.diagnose(Self.input(identityAudit: audit))
            .filter { $0.code == "GIT001" }
        #expect(hits.count == 1)
        #expect(hits[0].severity == .error)
        #expect(hits[0].detail.contains("me@example.com"))
        #expect(hits[0].detail.contains("Work"))
        // The one safe automatic fix: rewrite the managed files.
        #expect(hits[0].fixes.map(\.fixID) == [.git001_reprojectManagedFiles])
        #expect(hits[0].fixes.allSatisfy { !$0.isDestructive })
    }

    @Test func globalAccountMismatchExplainsInsteadOfOfferingAReproject() {
        let global = Self.account(
            label: "Personal",
            email: "me@example.com",
            scope: .global
        )
        let audit = IdentityAudit.audit(
            account: global,
            repoRoot: "/tmp/repo",
            identity: CurrentRepoResolver.EffectiveGitIdentity(
                userName: "Someone",
                userEmail: "stranger@example.com",
                sshCommand: nil
            ),
            accounts: [global]
        )
        let hits = Doctor.ruleIdentityMismatch(audit)
        #expect(hits.count == 1)
        #expect(hits[0].severity == .warning)
        #expect(hits[0].fixes.isEmpty)
        #expect(hits[0].fixHint != nil)
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
