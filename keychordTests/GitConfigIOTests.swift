import Testing
import Foundation
@testable import keychord

@Suite("GitConfigIO")
struct GitConfigIOTests {

    // MARK: - Fixture helper

    static func withFixture(
        _ content: String,
        _ test: (String) throws -> Void
    ) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-test-\(UUID().uuidString).gitconfig")
        try content.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try test(tmp.path)
    }

    // MARK: - listAll

    @Test func listsSimpleKeys() throws {
        try Self.withFixture("""
        [user]
        \tname = yangflow
        \temail = y@example.com
        """) { path in
            let io = GitConfigIO(filePath: path)
            let entries = try io.listAll()
            let map = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })
            #expect(map["user.name"] == "yangflow")
            #expect(map["user.email"] == "y@example.com")
        }
    }

    @Test func listsMultiValueInsteadOf() throws {
        try Self.withFixture("""
        [url "git@github-work:acme-corp/"]
        \tinsteadOf = https://github.com/acme-corp/
        [url "git@github-work:acme-corp/"]
        \tinsteadOf = git@github.com:acme-corp/
        """) { path in
            let io = GitConfigIO(filePath: path)
            let entries = try io.listAll()
            let insteadOfs = entries.filter { $0.key.hasSuffix(".insteadof") }
            #expect(insteadOfs.count == 2)
        }
    }

    @Test func parseListOutputHandlesNullSeparators() {
        let raw = "user.name\nyangflow\u{00}user.email\ny@example.com\u{00}"
        let entries = GitConfigIO.parseListOutput(raw)
        #expect(entries.count == 2)
        #expect(entries[0] == GitConfigIO.Entry(key: "user.name", value: "yangflow"))
        #expect(entries[1] == GitConfigIO.Entry(key: "user.email", value: "y@example.com"))
    }

    // MARK: - extractModel

    @Test func extractsUserIdentity() throws {
        try Self.withFixture("""
        [user]
        \tname = yangflow
        \temail = y@example.com
        """) { path in
            let io = GitConfigIO(filePath: path)
            let ex = try io.extractModel()
            #expect(ex.identity?.name == "yangflow")
            #expect(ex.identity?.email == "y@example.com")
            #expect(ex.identity?.sourceFile == path)
        }
    }

    @Test func extractsCoreSshCommand() throws {
        try Self.withFixture("""
        [user]
        \tname = y
        \temail = y@example.com
        [core]
        \tsshCommand = ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes
        """) { path in
            let io = GitConfigIO(filePath: path)
            let ex = try io.extractModel()
            #expect(ex.identity?.sshCommand == "ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes")
        }
    }

    @Test func extractsInsteadOfRulesWithDirection() throws {
        try Self.withFixture("""
        [user]
        \tname = y
        \temail = y@example.com
        [url "git@github-work:acme-corp/"]
        \tinsteadOf = https://github.com/acme-corp/
        \tinsteadOf = git@github.com:acme-corp/
        [url "git@github.com:"]
        \tinsteadOf = https://github.com/
        [url "git@internal:"]
        \tpushInsteadOf = https://internal/
        """) { path in
            let io = GitConfigIO(filePath: path)
            let ex = try io.extractModel()

            #expect(ex.insteadOf.count == 4)

            let regular = ex.insteadOf.filter { $0.direction == .insteadOf }
            let push = ex.insteadOf.filter { $0.direction == .pushInsteadOf }
            #expect(regular.count == 3)
            #expect(push.count == 1)

            let workRules = regular.filter { $0.to == "git@github-work:acme-corp/" }
            #expect(workRules.count == 2)
            let workFroms = Set(workRules.map(\.from))
            #expect(workFroms.contains("https://github.com/acme-corp/"))
            #expect(workFroms.contains("git@github.com:acme-corp/"))
        }
    }

    @Test func extractsIncludeIfRules() throws {
        try Self.withFixture("""
        [user]
        \tname = y
        \temail = y@example.com
        [includeIf "gitdir:~/work/"]
        \tpath = ~/.gitconfig-work
        """) { path in
            let io = GitConfigIO(filePath: path)
            let ex = try io.extractModel()
            #expect(ex.includeIf.count == 1)
            let rule = ex.includeIf[0]
            #expect(rule.condition == "gitdir:~/work/")
            #expect(rule.path == "~/.gitconfig-work")
        }
    }

    // MARK: - Write

    @Test func setWritesSingleKey() throws {
        try Self.withFixture("") { path in
            let io = GitConfigIO(filePath: path)
            try io.set("user.name", to: "alice")
            try io.set("user.email", to: "alice@example.com")
            let ex = try io.extractModel()
            #expect(ex.identity?.name == "alice")
            #expect(ex.identity?.email == "alice@example.com")
        }
    }

    @Test func addAppendsMultiValue() throws {
        try Self.withFixture("") { path in
            let io = GitConfigIO(filePath: path)
            try io.add("url.git@proxy:.insteadOf", "https://a/")
            try io.add("url.git@proxy:.insteadOf", "https://b/")
            let entries = try io.listAll()
            let both = entries.filter { $0.key == "url.git@proxy:.insteadof" }
            #expect(both.count == 2)
        }
    }

    @Test func unsetAllIsIdempotentForMissingKeys() throws {
        try Self.withFixture("") { path in
            let io = GitConfigIO(filePath: path)
            try io.unsetAll("user.name")
            try io.unsetAll("user.name")
        }
    }

    // MARK: - Smoke test against ~/.gitconfig (skipped if absent)

    @Test func realGitconfigExtractsIdentity() throws {
        let path = ("~/.gitconfig" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        let io = GitConfigIO(filePath: path)
        let ex = try io.extractModel()
        #expect(ex.identity != nil, "Real ~/.gitconfig should define [user]")
    }
}
