import Foundation
import Observation

/// Shared state for the menubar popover and the Accounts window.
/// Both scenes receive the same instance via `.environment()` so
/// changes — account list edits, doctor severity — stay in sync.
@MainActor
@Observable
final class AppState {
    var highestSeverity: Diagnosis.Severity?

    /// Account ID to select when the Accounts window opens.
    /// Set by the popover when the user clicks an account row.
    var pendingAccountSelection: UUID?

    /// When true the Accounts window should immediately begin a new draft.
    var pendingAddNew = false

    let accountsStore: AccountsStore
    let cloudSync: CloudSyncService

    init(accountsStore: AccountsStore? = nil, cloudSync: CloudSyncService? = nil) {
        let store = accountsStore ?? AccountsStore()
        let sync = cloudSync ?? CloudSyncService()
        self.accountsStore = store
        self.cloudSync = sync
        store.cloudSync = sync
        sync.start(store: store)
    }
}
