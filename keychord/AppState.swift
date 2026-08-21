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

    /// Current-repo match from a folder drop / Choose Folder / Finder probe.
    /// Stored here so a status-item drop can resolve while the popover is
    /// closed, then survive popover recreation when it opens.
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

    /// Shared resolve path used by popover drops, Choose Folder, Finder, and
    /// the menu-bar icon drag destination.
    func resolveCurrentRepo(at path: String) async {
        let accounts = accountsStore.accounts
        let result = await CurrentRepoResolver.matchAccount(path: path, accounts: accounts)
        accountMatch = result
        if case .matched(let account, _) = result, !account.sshAlias.isEmpty {
            accountsStore.touchLastUsed(sshAlias: account.sshAlias)
        }
    }
}
