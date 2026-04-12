import Foundation
import Combine

/// Shared state between the AppKit-owned status item and the SwiftUI
/// popover contents. The status item observes `highestSeverity` to swap
/// its icon, and writes `droppedPath` when a folder is dropped onto the
/// menubar. MenuBarContent observes `droppedPath` and runs the resolver
/// on the dropped folder.
@MainActor
final class AppState: ObservableObject {
    @Published var highestSeverity: Diagnosis.Severity?
    @Published var droppedPath: String?

    /// Account ID to select when the Accounts window opens.
    /// Set by the popover when the user clicks an account row.
    @Published var pendingAccountSelection: UUID?

    /// When true the Accounts window should immediately begin a new draft.
    @Published var pendingAddNew = false

    /// Shared persistent store for Account records. Instantiated once
    /// on app launch; both the menubar popover and the accounts
    /// manager window observe it via @ObservedObject.
    let accountsStore: AccountsStore

    /// iCloud key-value sync for accounts.json.
    let cloudSync: CloudSyncService

    private var storeCancellable: AnyCancellable?

    init(accountsStore: AccountsStore? = nil, cloudSync: CloudSyncService? = nil) {
        let store = accountsStore ?? AccountsStore()
        let sync = cloudSync ?? CloudSyncService()
        self.accountsStore = store
        self.cloudSync = sync
        store.cloudSync = sync
        // Forward nested ObservableObject changes so SwiftUI views
        // observing AppState also refresh when accounts change.
        storeCancellable = store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
        sync.start(store: store)
    }
}
