import Testing
import Foundation
@testable import keychord

@Suite("SSHConfigParser")
struct SSHConfigParserTests {

    // MARK: - Fixtures

    static let single = """
    Host github.com
      HostName ssh.github.com
      Port 443
      User git
      IdentityFile ~/.ssh/id_ed25519
      IdentitiesOnly yes
      HostKeyAlias github.com
    """

    static let multi = """
    # Personal
    Host github.com
      HostName ssh.github.com
      Port 443
      User git
      IdentityFile ~/.ssh/id_ed25519
      IdentitiesOnly yes
      HostKeyAlias github.com

    Host github-work
      HostName ssh.github.com
      Port 443
      User git
      IdentityFile ~/.ssh/id_rsa
      IdentitiesOnly yes
      HostKeyAlias github.com

    Include ~/.orbstack/ssh/config
    """

    // MARK: - Round-trip

    @Test func roundTripSingleHostIsByteIdentical() {
        let doc = SSHConfigDocument.parse(Self.single)
        #expect(doc.serialize() == Self.single)
    }

    @Test func roundTripMultiHostPreservesCommentsAndBlanks() {
        let doc = SSHConfigDocument.parse(Self.multi)
        #expect(doc.serialize() == Self.multi)
    }

    @Test func roundTripTrailingNewline() {
        let input = "Host foo\n  HostName bar\n"
        let doc = SSHConfigDocument.parse(input)
        #expect(doc.serialize() == input)
    }

    @Test func roundTripEmptyInput() {
        let doc = SSHConfigDocument.parse("")
        #expect(doc.serialize() == "")
    }

    // MARK: - Host extraction

    @Test func extractsSingleHost() {
        let doc = SSHConfigDocument.parse(Self.single)
        let hosts = doc.extractHosts()
        #expect(hosts.count == 1)
        let h = hosts[0]
        #expect(h.alias == "github.com")
        #expect(h.hostName == "ssh.github.com")
        #expect(h.port == 443)
        #expect(h.user == "git")
        #expect(h.identityFile == "~/.ssh/id_ed25519")
        #expect(h.identitiesOnly == true)
        #expect(h.hostKeyAlias == "github.com")
    }

    @Test func extractsMultipleHosts() {
        let doc = SSHConfigDocument.parse(Self.multi)
        let hosts = doc.extractHosts()
        #expect(hosts.count == 2)
        #expect(hosts[0].alias == "github.com")
        #expect(hosts[1].alias == "github-work")
        #expect(hosts[0].identityFile == "~/.ssh/id_ed25519")
        #expect(hosts[1].identityFile == "~/.ssh/id_rsa")
    }

    // MARK: - Case insensitivity

    @Test func directiveNamesAreCaseInsensitive() {
        let input = """
        Host foo
          hostname BAR
          PORT 22
          user git
        """
        let hosts = SSHConfigDocument.parse(input).extractHosts()
        #expect(hosts.count == 1)
        #expect(hosts[0].hostName == "BAR")
        #expect(hosts[0].port == 22)
        #expect(hosts[0].user == "git")
    }

    // MARK: - Separators

    @Test func acceptsTabAndEqualsSeparators() {
        let input = "Host foo\n\tHostName=ssh.github.com\n\tPort\t443\n"
        let hosts = SSHConfigDocument.parse(input).extractHosts()
        #expect(hosts.count == 1)
        #expect(hosts[0].hostName == "ssh.github.com")
        #expect(hosts[0].port == 443)
    }

    // MARK: - Extra directives

    @Test func unknownDirectiveGoesToExtraDirectives() {
        let input = """
        Host foo
          HostName bar
          ServerAliveInterval 60
        """
        let hosts = SSHConfigDocument.parse(input).extractHosts()
        #expect(hosts[0].extraDirectives.count == 1)
        #expect(hosts[0].extraDirectives.first?.key == "ServerAliveInterval")
        #expect(hosts[0].extraDirectives.first?.value == "60")
    }

    // MARK: - Quoted values

    @Test func stripsQuotesFromQuotedValues() {
        let input = "Host foo\n  IdentityFile \"~/path with space\"\n"
        let hosts = SSHConfigDocument.parse(input).extractHosts()
        #expect(hosts[0].identityFile == "~/path with space")
    }

    // MARK: - setField mutation

    @Test func setFieldUpdatesExistingFieldInPlace() {
        var doc = SSHConfigDocument.parse(Self.single)
        let ok = doc.setField("Port", to: "22", forHost: "github.com")
        #expect(ok == true)

        let hosts = doc.extractHosts()
        #expect(hosts[0].port == 22)

        let expected = Self.single.replacingOccurrences(of: "Port 443", with: "Port 22")
        #expect(doc.serialize() == expected)
    }

    @Test func setFieldAppendsWhenMissing() {
        var doc = SSHConfigDocument.parse("Host foo\n  HostName bar\n")
        let ok = doc.setField("Port", to: "443", forHost: "foo")
        #expect(ok == true)

        let hosts = doc.extractHosts()
        #expect(hosts[0].port == 443)
        #expect(doc.serialize().contains("Port 443"))
    }

    @Test func setFieldRemovesLineWhenValueIsNil() {
        var doc = SSHConfigDocument.parse(Self.single)
        let ok = doc.setField("Port", to: nil, forHost: "github.com")
        #expect(ok == true)

        let hosts = doc.extractHosts()
        #expect(hosts[0].port == nil)
        #expect(!doc.serialize().contains("Port 443"))
    }

    @Test func setFieldReturnsFalseForUnknownHost() {
        var doc = SSHConfigDocument.parse(Self.single)
        let ok = doc.setField("Port", to: "22", forHost: "nonexistent")
        #expect(ok == false)
    }

    // MARK: - removeHost

    @Test func removeHostDeletesEntireBlock() {
        let input = """
        # Personal
        Host github.com
          HostName ssh.github.com
          Port 443
          IdentityFile ~/.ssh/id_ed25519

        Host github-work
          HostName ssh.github.com
          Port 443
          IdentityFile ~/.ssh/id_rsa
        """
        var doc = SSHConfigDocument.parse(input)
        let removed = doc.removeHost(alias: "github-work")
        #expect(removed == true)

        let text = doc.serialize()
        #expect(!text.contains("Host github-work"))
        #expect(!text.contains("id_rsa"))
        #expect(text.contains("# Personal"))
        #expect(text.contains("Host github.com"))
        #expect(text.contains("id_ed25519"))
    }

    @Test func removeHostPreservesSurroundingBlocks() {
        let input = """
        Host a
          HostName a.com

        Host b
          HostName b.com

        Host c
          HostName c.com
        """
        var doc = SSHConfigDocument.parse(input)
        #expect(doc.removeHost(alias: "b") == true)
        let hosts = doc.extractHosts().map(\.alias)
        #expect(hosts == ["a", "c"])
    }

    @Test func removeHostReturnsFalseForUnknown() {
        var doc = SSHConfigDocument.parse("Host foo\n  HostName bar\n")
        #expect(doc.removeHost(alias: "nope") == false)
        #expect(doc.extractHosts().count == 1)
    }

    // MARK: - Smoke test against the real ~/.ssh/config (skipped if not present)

    @Test func realSSHConfigRoundTripsIdentically() throws {
        let path = ("~/.ssh/config" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let doc = SSHConfigDocument.parse(text)
        #expect(doc.serialize() == text, "Round-trip of ~/.ssh/config must be byte-identical")
        // Host blocks may live in Include'd files, so the main config
        // can legitimately contain zero inline hosts.
    }
}
