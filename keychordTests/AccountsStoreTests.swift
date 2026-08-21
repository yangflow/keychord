import Testing
import Foundation
@testable import keychord

@Suite("AccountsStore")
@MainActor
struct AccountsStoreTests {

    static func withTempURL(_ test: (URL) async throws -> Void) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tmp,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = tmp.appendingPathComponent("accounts.json")
        try await test(url)
    }

    static func makeStore(url: URL) -> AccountsStore {
        let backups = BackupService(
            backupRoot: url.deletingLastPathComponent().appendingPathComponent("backups"),
            retentionCount: 10
        )
        return AccountsStore(storageURL: url, backups: backups)
    }

    static func sample(label: String = "Personal") -> Account {
        Account.new(
            label: label,
            sshAlias: "github.com",
            keyPath: "/Users/u/.ssh/id_ed25519",
            gitUserName: "yangflow",
            gitUserEmail: "ydongy02@gmail.com"
        )
    }

    // MARK: - Empty state

    @Test func emptyStoreHasNoAccounts() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            #expect(store.accounts.isEmpty)
        }
    }

    @Test func emptyStoreDoesNotCreateFile() async throws {
        try await Self.withTempURL { url in
            _ = Self.makeStore(url: url)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    // MARK: - Add / persist / reload

    @Test func addWritesAccountToDisk() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            try store.add(Self.sample())
            #expect(store.accounts.count == 1)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func addSurvivesReload() async throws {
        try await Self.withTempURL { url in
            let store1 = Self.makeStore(url: url)
            let acc = Self.sample(label: "Work")
            try store1.add(acc)

            let store2 = Self.makeStore(url: url)
            #expect(store2.accounts.count == 1)
            #expect(store2.accounts.first?.label == "Work")
            #expect(store2.accounts.first?.id == acc.id)
        }
    }

    @Test func duplicateIDThrows() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            let acc = Self.sample()
            try store.add(acc)
            #expect(throws: AccountsStore.StoreError.self) {
                try store.add(acc)
            }
        }
    }

    // MARK: - Update

    @Test func updateBumpsUpdatedAt() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            let acc = Self.sample()
            try store.add(acc)
            let originalUpdated = store.accounts[0].updatedAt

            // Wait enough to ensure Date() moves forward
            try await Task.sleep(nanoseconds: 10_000_000)

            var edited = acc
            edited.label = "Renamed"
            try store.update(edited)

            #expect(store.accounts.first?.label == "Renamed")
            #expect(store.accounts[0].updatedAt > originalUpdated)
        }
    }

    @Test func updateMissingIDThrows() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            let phantom = Self.sample()
            #expect(throws: AccountsStore.StoreError.self) {
                try store.update(phantom)
            }
        }
    }

    // MARK: - Delete

    @Test func deleteRemovesAccount() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            let a = Self.sample(label: "A")
            let b = Self.sample(label: "B")
            try store.add(a)
            try store.add(b)

            try store.delete(id: a.id)
            #expect(store.accounts.map(\.label) == ["B"])

            // And persisted
            let reloaded = Self.makeStore(url: url)
            #expect(reloaded.accounts.map(\.label) == ["B"])
        }
    }

    @Test func deleteMissingIDThrows() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            #expect(throws: AccountsStore.StoreError.self) {
                try store.delete(id: UUID())
            }
        }
    }

    // MARK: - Replace all (bulk import path)

    @Test func replaceAllOverwritesEntireList() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            try store.add(Self.sample(label: "Old"))

            let fresh = [
                Self.sample(label: "Imported A"),
                Self.sample(label: "Imported B")
            ]
            try store.replaceAll(fresh)
            #expect(store.accounts.count == 2)
            #expect(store.accounts.map(\.label) == ["Imported A", "Imported B"])
        }
    }

    // MARK: - Backup policy

    @Test func addCreatesBackupWhenFileAlreadyExists() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            try store.add(Self.sample(label: "First"))
            let backupRoot = url.deletingLastPathComponent().appendingPathComponent("backups")
            let before = (try? FileManager.default.contentsOfDirectory(atPath: backupRoot.path)) ?? []

            try store.add(Self.sample(label: "Second"))
            let after = try FileManager.default.contentsOfDirectory(atPath: backupRoot.path)
            #expect(after.count == before.count + 1)
        }
    }

    @Test func updateDoesNotCreateBackup() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            let acc = Self.sample()
            try store.add(acc)
            // Second add creates the only expected backup of the first write.
            try store.add(Self.sample(label: "Other"))
            let backupRoot = url.deletingLastPathComponent().appendingPathComponent("backups")
            let before = try FileManager.default.contentsOfDirectory(atPath: backupRoot.path)

            var edited = acc
            edited.label = "Renamed"
            try store.update(edited)

            let after = try FileManager.default.contentsOfDirectory(atPath: backupRoot.path)
            #expect(after.count == before.count)
        }
    }

    @Test func deleteDoesNotCreateBackup() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            let a = Self.sample(label: "A")
            try store.add(a)
            try store.add(Self.sample(label: "B"))
            let backupRoot = url.deletingLastPathComponent().appendingPathComponent("backups")
            let before = try FileManager.default.contentsOfDirectory(atPath: backupRoot.path)

            try store.delete(id: a.id)

            let after = try FileManager.default.contentsOfDirectory(atPath: backupRoot.path)
            #expect(after.count == before.count)
        }
    }

    // MARK: - Last used (popover ordering, #43)

    @Test func touchByAliasRecordsAndPersistsTheTimestamp() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            let account = Self.sample(label: "Work")
            try store.add(account)
            #expect(store.accounts.first?.lastUsedAt == nil)

            let when = Date(timeIntervalSince1970: 1_800_000_000)
            store.touchLastUsed(sshAlias: account.sshAlias, at: when)

            #expect(store.accounts.first?.lastUsedAt == when)
            #expect(Self.makeStore(url: url).accounts.first?.lastUsedAt == when)
        }
    }

    @Test func touchByIDWorksBeforeAnAliasExists() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            var account = Self.sample(label: "Fresh")
            account.sshAlias = ""
            try store.add(account)

            let when = Date(timeIntervalSince1970: 1_800_000_100)
            store.touchLastUsed(id: account.id, at: when)
            #expect(store.accounts.first?.lastUsedAt == when)

            // The alias path cannot help here, and must not touch anyone else.
            store.touchLastUsed(sshAlias: "", at: Date(timeIntervalSince1970: 2_000_000_000))
            #expect(store.accounts.first?.lastUsedAt == when)
        }
    }

    @Test func touchingAnUnknownAccountIsANoOp() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            try store.add(Self.sample(label: "Work"))

            store.touchLastUsed(id: UUID())
            store.touchLastUsed(sshAlias: "github-nope")

            #expect(store.accounts.count == 1)
            #expect(store.accounts.first?.lastUsedAt == nil)
        }
    }

    @Test func touchOnlyMovesTheTargetedAccount() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            var work = Self.sample(label: "Work")
            work.sshAlias = "github-work"
            var personal = Self.sample(label: "Personal")
            personal.sshAlias = "github-personal"
            try store.add(work)
            try store.add(personal)

            let when = Date(timeIntervalSince1970: 1_800_000_200)
            store.touchLastUsed(id: personal.id, at: when)

            #expect(store.accounts.first(where: { $0.id == work.id })?.lastUsedAt == nil)
            #expect(store.accounts.first(where: { $0.id == personal.id })?.lastUsedAt == when)
            // And the popover order follows.
            #expect(AccountOrdering.byLastUsed(store.accounts).first?.id == personal.id)
        }
    }

    // MARK: - Scope Codable round-trip

    @Test func scopeEnumRoundTripsViaJSON() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            var scoped = Self.sample(label: "Scoped")
            scoped.scope = .gitdir("~/work/")
            scoped.urlRewrites = [
                Account.URLRewrite(
                    from: "https://github.com/Acme/",
                    to: "git@github-acme:Acme/"
                )
            ]
            try store.add(scoped)

            let reloaded = Self.makeStore(url: url)
            let record = reloaded.accounts.first
            #expect(record?.scope == .gitdir("~/work/"))
            #expect(record?.scope.directories == ["~/work/"])
            #expect(record?.urlRewrites.count == 1)
            #expect(record?.urlRewrites.first?.to == "git@github-acme:Acme/")
        }
    }

    @Test func multipleGitdirPathsRoundTripViaJSON() async throws {
        try await Self.withTempURL { url in
            let store = Self.makeStore(url: url)
            var scoped = Self.sample(label: "Work")
            scoped.scope = .gitdir(paths: ["~/work/", "~/src/new-app/"])
            try store.add(scoped)

            let reloaded = Self.makeStore(url: url)
            #expect(reloaded.accounts.first?.scope.directories == ["~/work/", "~/src/new-app/"])
            // Single-path accessor keeps reporting the first path for the
            // editors that show one directory at a time.
            #expect(reloaded.accounts.first?.scope.directory == "~/work/")
        }
    }

    @Test func scopeStillDecodesSinglePathJSONFromOlderBuilds() throws {
        let legacy = """
        {"gitdir":{"_0":"~/work/"}}
        """
        let decoded = try JSONDecoder().decode(
            Account.Scope.self,
            from: Data(legacy.utf8)
        )
        #expect(decoded == .gitdir(paths: ["~/work/"]))
    }

    @Test func scopeKeepsWritingTheSinglePathKeyForOlderBuilds() throws {
        let encoded = try JSONEncoder().encode(
            Account.Scope.gitdir(paths: ["~/work/", "~/src/new-app/"])
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let gitdir = try #require(json["gitdir"] as? [String: Any])
        #expect(gitdir["_0"] as? String == "~/work/")
        #expect(gitdir["paths"] as? [String] == ["~/work/", "~/src/new-app/"])
    }

    @Test func globalScopeRoundTrips() throws {
        let encoded = try JSONEncoder().encode(Account.Scope.global)
        let decoded = try JSONDecoder().decode(Account.Scope.self, from: encoded)
        #expect(decoded == .global)
    }
}
