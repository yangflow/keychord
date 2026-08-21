import Foundation

/// In-memory cache of SSH host-probe results for the process lifetime.
///
/// Popover opens consult `shouldProbe` so successful aliases are not
/// re-hit with `ssh -T` until the user taps Refresh. Failures and
/// never-probed aliases auto-reprobe after the TTL elapses.
@MainActor
final class ProbeCache {

    /// Default freshness window for auto-reprobe of non-success entries.
    static let defaultTTL: TimeInterval = 10 * 60

    struct Entry: Equatable, Sendable {
        let state: HostProbeState
        let probedAt: Date
    }

    private(set) var entries: [String: Entry] = [:]

    private let ttl: TimeInterval
    private let now: () -> Date

    init(
        ttl: TimeInterval = ProbeCache.defaultTTL,
        now: @escaping () -> Date = { Date() }
    ) {
        self.ttl = ttl
        self.now = now
    }

    /// Whether `alias` should run a real probe on an automatic pass.
    ///
    /// - `force`: always probe (manual Refresh).
    /// - No cache entry: probe (never succeeded).
    /// - `.ok`: never auto-reprobe; stays until manual Refresh.
    /// - `.failed`: auto-reprobe only after TTL.
    /// - `.idle` / `.probing`: treat as not yet succeeded → probe.
    func shouldProbe(_ alias: String, force: Bool = false) -> Bool {
        if force { return true }
        guard let entry = entries[alias] else { return true }
        switch entry.state {
        case .ok:
            return false
        case .failed:
            return now().timeIntervalSince(entry.probedAt) >= ttl
        case .idle, .probing:
            return true
        }
    }

    func state(for alias: String) -> HostProbeState? {
        entries[alias]?.state
    }

    func cachedStates(for aliases: [String]) -> [String: HostProbeState] {
        var result: [String: HostProbeState] = [:]
        for alias in aliases {
            if let state = entries[alias]?.state {
                result[alias] = state
            }
        }
        return result
    }

    /// Persist a terminal probe outcome. Non-terminal states are ignored.
    func record(_ state: HostProbeState, for alias: String) {
        switch state {
        case .ok, .failed:
            entries[alias] = Entry(state: state, probedAt: now())
        case .idle, .probing:
            break
        }
    }

    /// Run probes only for aliases that `shouldProbe` allows.
    /// Returns the merged map of cached + freshly probed states.
    ///
    /// `probe` is injectable so unit tests can count invocations without
    /// spawning `ssh`.
    func probeAliases(
        _ aliases: [String],
        force: Bool = false,
        probe: @escaping @Sendable (String) async -> HostProbeState
    ) async -> [String: HostProbeState] {
        var states = cachedStates(for: aliases)
        let pending = aliases.filter { shouldProbe($0, force: force) }

        await withTaskGroup(of: (String, HostProbeState).self) { group in
            for alias in pending {
                group.addTask {
                    let result = await probe(alias)
                    return (alias, result)
                }
            }
            for await (alias, result) in group {
                record(result, for: alias)
                states[alias] = result
            }
        }
        return states
    }
}
