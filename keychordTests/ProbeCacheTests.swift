import Testing
import Foundation
@testable import keychord

@Suite("ProbeCache")
@MainActor
struct ProbeCacheTests {

    private let ttl: TimeInterval = 600

    // MARK: - shouldProbe policy

    @Test func neverProbedShouldProbe() {
        let cache = ProbeCache(ttl: ttl, now: { Date(timeIntervalSince1970: 1_000_000) })
        #expect(cache.shouldProbe("github-work"))
    }

    @Test func successfulProbeSkipsWithinTTL() {
        var current = Date(timeIntervalSince1970: 1_000_000)
        let cache = ProbeCache(ttl: ttl, now: { current })
        cache.record(.ok(username: "yangflow"), for: "github-work")

        #expect(!cache.shouldProbe("github-work"))
        current = current.addingTimeInterval(ttl - 1)
        #expect(!cache.shouldProbe("github-work"))
    }

    @Test func successfulProbeStillSkipsAfterTTLUntilManualRefresh() {
        var current = Date(timeIntervalSince1970: 1_000_000)
        let cache = ProbeCache(ttl: ttl, now: { current })
        cache.record(.ok(username: "yangflow"), for: "github-work")

        current = current.addingTimeInterval(ttl + 1)
        #expect(!cache.shouldProbe("github-work"))
        #expect(cache.shouldProbe("github-work", force: true))
    }

    @Test func failedProbeSkipsWithinTTLThenAutoReprobes() {
        var current = Date(timeIntervalSince1970: 1_000_000)
        let cache = ProbeCache(ttl: ttl, now: { current })
        cache.record(.failed(reason: "permission denied (publickey)"), for: "github-work")

        #expect(!cache.shouldProbe("github-work"))
        current = current.addingTimeInterval(ttl - 1)
        #expect(!cache.shouldProbe("github-work"))
        current = current.addingTimeInterval(2)
        #expect(cache.shouldProbe("github-work"))
    }

    @Test func forceAlwaysProbes() {
        let cache = ProbeCache(ttl: ttl, now: { Date(timeIntervalSince1970: 1_000_000) })
        cache.record(.ok(username: "yangflow"), for: "github-work")
        #expect(cache.shouldProbe("github-work", force: true))
    }

    // MARK: - probeAliases orchestration (popover-open path)

    @Test func secondOpenWithinTTLDoesNotReprobeSuccesses() async {
        let counter = ProbeCounter()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let cache = ProbeCache(ttl: ttl, now: { current })
        let aliases = ["github-work", "github-personal"]

        let first = await cache.probeAliases(aliases, force: false) { alias in
            await counter.increment(alias)
            return .ok(username: "user-\(alias)")
        }
        #expect(first.count == 2)
        #expect(counter.count == 2)

        // Second popover-open path within TTL: successes stay cached.
        current = current.addingTimeInterval(30)
        let second = await cache.probeAliases(aliases, force: false) { alias in
            await counter.increment(alias)
            return .ok(username: "should-not-run")
        }
        #expect(counter.count == 2)
        #expect(second["github-work"] == .ok(username: "user-github-work"))
        #expect(second["github-personal"] == .ok(username: "user-github-personal"))
    }

    @Test func manualRefreshReprobesSuccesses() async {
        let counter = ProbeCounter()
        let current = Date(timeIntervalSince1970: 1_000_000)
        let cache = ProbeCache(ttl: ttl, now: { current })
        let aliases = ["github-work"]

        _ = await cache.probeAliases(aliases, force: false) { alias in
            await counter.increment(alias)
            return .ok(username: "first")
        }
        #expect(counter.count == 1)

        let refreshed = await cache.probeAliases(aliases, force: true) { alias in
            await counter.increment(alias)
            return .ok(username: "second")
        }
        #expect(counter.count == 2)
        #expect(refreshed["github-work"] == .ok(username: "second"))
    }

    @Test func secondOpenReprobesFailureAfterTTLOnly() async {
        let counter = ProbeCounter()
        var current = Date(timeIntervalSince1970: 1_000_000)
        let cache = ProbeCache(ttl: ttl, now: { current })
        let aliases = ["github-work"]

        _ = await cache.probeAliases(aliases, force: false) { alias in
            await counter.increment(alias)
            return .failed(reason: "timed out")
        }
        #expect(counter.count == 1)

        current = current.addingTimeInterval(60)
        _ = await cache.probeAliases(aliases, force: false) { alias in
            await counter.increment(alias)
            return .failed(reason: "timed out")
        }
        #expect(counter.count == 1)

        current = current.addingTimeInterval(ttl)
        _ = await cache.probeAliases(aliases, force: false) { alias in
            await counter.increment(alias)
            return .ok(username: "recovered")
        }
        #expect(counter.count == 2)
        #expect(cache.state(for: "github-work") == .ok(username: "recovered"))
    }

    // MARK: - Manual per-alias retry (cache must not block it)

    @Test func reprobeIgnoresACachedFailureInsideTTL() async {
        let counter = ProbeCounter()
        let current = Date(timeIntervalSince1970: 1_000_000)
        let cache = ProbeCache(ttl: ttl, now: { current })
        cache.record(.failed(reason: "permission denied (publickey)"), for: "github-work")
        #expect(!cache.shouldProbe("github-work"))

        let state = await cache.reprobe("github-work") { alias in
            await counter.increment(alias)
            return .ok(username: "yangflow")
        }

        #expect(await counter.count == 1)
        #expect(state == .ok(username: "yangflow"))
        #expect(cache.state(for: "github-work") == .ok(username: "yangflow"))
    }

    @Test func reprobeIgnoresACachedSuccess() async {
        let counter = ProbeCounter()
        let current = Date(timeIntervalSince1970: 1_000_000)
        let cache = ProbeCache(ttl: ttl, now: { current })
        cache.record(.ok(username: "old"), for: "github-work")

        let state = await cache.reprobe("github-work") { alias in
            await counter.increment(alias)
            return .failed(reason: "permission denied (publickey)")
        }

        #expect(await counter.count == 1)
        #expect(state == .failed(reason: "permission denied (publickey)"))
    }

    @Test func reprobeOnlyTouchesTheRequestedAlias() async {
        let current = Date(timeIntervalSince1970: 1_000_000)
        let cache = ProbeCache(ttl: ttl, now: { current })
        cache.record(.ok(username: "kept"), for: "github-personal")
        cache.record(.failed(reason: "timed out"), for: "github-work")

        _ = await cache.reprobe("github-work") { _ in .ok(username: "fresh") }

        #expect(cache.state(for: "github-personal") == .ok(username: "kept"))
        #expect(cache.state(for: "github-work") == .ok(username: "fresh"))
    }

    @Test func invalidateForcesTheNextAutomaticPassToProbe() {
        let current = Date(timeIntervalSince1970: 1_000_000)
        let cache = ProbeCache(ttl: ttl, now: { current })
        cache.record(.ok(username: "yangflow"), for: "github-work")
        #expect(!cache.shouldProbe("github-work"))

        cache.invalidate("github-work")
        #expect(cache.state(for: "github-work") == nil)
        #expect(cache.shouldProbe("github-work"))
    }

    @Test func recordIgnoresNonTerminalStates() {
        let cache = ProbeCache(ttl: ttl, now: { Date(timeIntervalSince1970: 1_000_000) })
        cache.record(.probing, for: "github-work")
        cache.record(.idle, for: "github-work")
        #expect(cache.state(for: "github-work") == nil)
        #expect(cache.shouldProbe("github-work"))
    }
}

/// Actor so async probe closures can safely bump a shared counter from
/// concurrent task-group workers.
private actor ProbeCounter {
    private(set) var count = 0
    private(set) var aliases: [String] = []

    func increment(_ alias: String) {
        count += 1
        aliases.append(alias)
    }
}
