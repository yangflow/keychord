import Testing
import Foundation
@testable import keychord

@Suite("ClonePrefixMemory")
@MainActor
struct ClonePrefixMemoryTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "keychord.tests.clonePrefix.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Owner extraction

    @Test func extractsTheOwnerPrefix() {
        #expect(ClonePrefixMemory.ownerPrefix(from: "acme/api") == "acme/")
        #expect(ClonePrefixMemory.ownerPrefix(from: "acme/group/api") == "acme/")
        #expect(ClonePrefixMemory.ownerPrefix(from: "  acme/api  ") == "acme/")
        #expect(ClonePrefixMemory.ownerPrefix(from: "acme/api.git") == "acme/")
    }

    @Test func extractsTheOwnerFromAPastedRemote() {
        #expect(
            ClonePrefixMemory.ownerPrefix(from: "https://github.com/acme/api.git") == "acme/"
        )
        #expect(ClonePrefixMemory.ownerPrefix(from: "git@github.com:acme/api.git") == "acme/")
    }

    @Test func inputWithoutAnOwnerIsIgnored() {
        #expect(ClonePrefixMemory.ownerPrefix(from: "") == nil)
        #expect(ClonePrefixMemory.ownerPrefix(from: "   ") == nil)
        #expect(ClonePrefixMemory.ownerPrefix(from: "api") == nil)
        #expect(ClonePrefixMemory.ownerPrefix(from: "acme/") == nil)
    }

    // MARK: - Per-account memory

    @Test func remembersAndReadsBackPerAccount() {
        let memory = ClonePrefixMemory(defaults: freshDefaults())
        let work = UUID()
        let personal = UUID()

        memory.remember(input: "acme/api", for: work)
        memory.remember(input: "alexdoe/dotfiles", for: personal)

        #expect(memory.prefix(for: work) == "acme/")
        #expect(memory.prefix(for: personal) == "alexdoe/")
    }

    @Test func unknownAccountHasNoPrefix() {
        let memory = ClonePrefixMemory(defaults: freshDefaults())
        #expect(memory.prefix(for: UUID()) == nil)
    }

    @Test func laterCopyReplacesThePrefix() {
        let memory = ClonePrefixMemory(defaults: freshDefaults())
        let id = UUID()
        memory.remember(input: "acme/api", for: id)
        memory.remember(input: "other-org/web", for: id)
        #expect(memory.prefix(for: id) == "other-org/")
    }

    @Test func unusableInputDoesNotEraseAGoodPrefix() {
        let memory = ClonePrefixMemory(defaults: freshDefaults())
        let id = UUID()
        memory.remember(input: "acme/api", for: id)
        memory.remember(input: "api", for: id)
        memory.remember(input: "", for: id)
        #expect(memory.prefix(for: id) == "acme/")
    }

    @Test func forgetClearsOneAccount() {
        let memory = ClonePrefixMemory(defaults: freshDefaults())
        let id = UUID()
        memory.remember(input: "acme/api", for: id)
        memory.forget(accountID: id)
        #expect(memory.prefix(for: id) == nil)
    }

    @Test func prefixIsPersistedInDefaults() {
        let defaults = freshDefaults()
        let id = UUID()
        ClonePrefixMemory(defaults: defaults).remember(input: "acme/api", for: id)

        // A fresh instance over the same defaults still knows the prefix.
        #expect(ClonePrefixMemory(defaults: defaults).prefix(for: id) == "acme/")
        #expect(defaults.string(forKey: ClonePrefixMemory.key(for: id)) == "acme/")
    }
}
