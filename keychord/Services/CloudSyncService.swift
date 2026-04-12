import Foundation
import Combine

/// Syncs accounts.json data via iCloud NSUbiquitousKeyValueStore.
///
/// Push: called by AccountsStore after each save.
/// Pull: on launch + whenever iCloud delivers a change notification.
///
/// Merge strategy: union of local and remote accounts keyed by UUID.
/// When an account exists on both sides, the copy with the newer
/// `updatedAt` wins. Accounts deleted locally are tracked in a
/// tombstone set so they don't reappear from a stale remote copy.
@MainActor
final class CloudSyncService: ObservableObject {

    enum SyncState: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    @Published private(set) var state: SyncState = .idle
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    private let kvStore = NSUbiquitousKeyValueStore.default
    private var cancellable: AnyCancellable?
    private weak var accountsStore: AccountsStore?

    private static let dataKey      = "accounts_json"
    private static let tombstoneKey = "deleted_ids"
    private static let enabledKey   = "cloud_sync_enabled"

    // MARK: - Init

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    // MARK: - Lifecycle

    func start(store: AccountsStore) {
        self.accountsStore = store
        guard isEnabled else { return }
        activate()
    }

    func activate() {
        kvStore.synchronize()
        cancellable = NotificationCenter.default
            .publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleRemoteChange(notification)
            }
        pull()
    }

    func deactivate() {
        cancellable = nil
    }

    // MARK: - Push (local → iCloud)

    func push(accounts: [Account]) {
        guard isEnabled else { return }
        state = .syncing
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(accounts)
            kvStore.set(data, forKey: Self.dataKey)
            kvStore.synchronize()
            state = .synced(Date())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Pull (iCloud → local)

    func pull() {
        guard isEnabled, let store = accountsStore else { return }
        guard let data = kvStore.data(forKey: Self.dataKey) else { return }
        state = .syncing
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let remote = try decoder.decode([Account].self, from: data)
            let tombstones = loadTombstones()
            let merged = merge(local: store.accounts, remote: remote, tombstones: tombstones)
            if merged != store.accounts {
                try store.replaceAll(merged)
            }
            state = .synced(Date())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Tombstones

    func recordDeletion(id: UUID) {
        guard isEnabled else { return }
        var tombstones = loadTombstones()
        tombstones.insert(id.uuidString)
        kvStore.set(Array(tombstones), forKey: Self.tombstoneKey)
        kvStore.synchronize()
    }

    private func loadTombstones() -> Set<String> {
        guard let arr = kvStore.array(forKey: Self.tombstoneKey) as? [String] else {
            return []
        }
        return Set(arr)
    }

    // MARK: - Merge

    private func merge(
        local: [Account],
        remote: [Account],
        tombstones: Set<String>
    ) -> [Account] {
        var byID: [UUID: Account] = [:]

        for account in local {
            byID[account.id] = account
        }
        for account in remote {
            guard !tombstones.contains(account.id.uuidString) else { continue }
            if let existing = byID[account.id] {
                if account.updatedAt > existing.updatedAt {
                    byID[account.id] = account
                }
            } else {
                byID[account.id] = account
            }
        }

        // Preserve ordering: local accounts first in their original order,
        // then any new remote accounts appended.
        var result: [Account] = []
        var seen = Set<UUID>()
        for account in local {
            if let merged = byID[account.id] {
                result.append(merged)
                seen.insert(account.id)
            }
        }
        for account in remote where !seen.contains(account.id) {
            if let merged = byID[account.id] {
                result.append(merged)
                seen.insert(account.id)
            }
        }
        return result
    }

    // MARK: - Remote change handler

    private func handleRemoteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reason = info[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            pull()
            return
        }
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            pull()
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            state = .failed("iCloud storage quota exceeded")
        case NSUbiquitousKeyValueStoreAccountChange:
            pull()
        default:
            pull()
        }
    }
}
