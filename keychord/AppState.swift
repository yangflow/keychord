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

    /// When true, `MenuBarPopoverView` must not clear ``accountMatch`` on
    /// disappear — `NSOpenPanel` (Choose Folder) steals focus and tears down
    /// the MenuBarExtra window without the user dismissing a result.
    var isChoosingFolder = false

    /// Current-repo match from a folder drop / Choose Folder.
    /// Stored here so a status-item drop can resolve while the popover is
    /// closed, then survive popover recreation when it opens. Cleared when
    /// the user dismisses the popover (or clears the match card).
    var accountMatch: AccountMatchResult?

    let accountsStore: AccountsStore
    let probeCache: ProbeCache

    init(
        accountsStore: AccountsStore? = nil,
        probeCache: ProbeCache? = nil
    ) {
        self.accountsStore = accountsStore ?? AccountsStore()
        self.probeCache = probeCache ?? ProbeCache()
    }

    func clearAccountMatch() {
        accountMatch = nil
    }

    /// Shared resolve path used by popover drops, Choose Folder, and the
    /// menu-bar icon drag destination.
    func resolveCurrentRepo(at path: String) async {
        let accounts = accountsStore.accounts
        let result = await CurrentRepoResolver.matchAccount(path: path, accounts: accounts)
        accountMatch = result
        if case .matched(let account, _, _) = result, !account.sshAlias.isEmpty {
            accountsStore.touchLastUsed(sshAlias: account.sshAlias)
        }
    }
}
