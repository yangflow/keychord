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

    /// When true, ``MenuBarPopoverView`` must not clear ``accountMatch`` on
    /// disappear — opening the MenuBarExtra after an icon drop can recreate
    /// the hosting view and would otherwise wipe the just-resolved match.
    var suppressAccountMatchClear = false

    /// Current-repo match from a folder drop onto the menu bar icon (or the
    /// open popover). Cleared when the user dismisses the popover (or clears
    /// the match card).
    var accountMatch: AccountMatchResult?

    /// Author-vs-key comparison for the matched repository, if it has one.
    /// Recomputed with every resolve; `nil` while there is no match.
    var identityAudit: IdentityAudit?

    /// Settings pane to select when the Settings window opens. Set by the
    /// popover's empty state so Import is reachable without the gear.
    var pendingSettingsPane: SettingsPane?

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
        identityAudit = nil
    }

    /// Shared resolve path used by menu-bar icon drops and popover `.onDrop`.
    func resolveCurrentRepo(at path: String) async {
        let accounts = accountsStore.accounts
        let result = await CurrentRepoResolver.matchAccount(path: path, accounts: accounts)
        accountMatch = result
        identityAudit = nil
        guard case .matched(let account, let repoRoot, _) = result else { return }
        if !account.sshAlias.isEmpty {
            accountsStore.touchLastUsed(sshAlias: account.sshAlias)
        }
        let identity = await CurrentRepoResolver.readEffectiveIdentity(at: repoRoot)
        identityAudit = IdentityAudit.audit(
            account: account,
            repoRoot: repoRoot,
            identity: identity,
            accounts: accounts
        )
    }

    /// One-tap `gitdir:` bind for the folder in the current unresolved match.
    /// Adds a path to `account`, persists, regenerates the managed files, and
    /// re-resolves so the card flips to the matched state. Returns a
    /// user-facing message when the write fails; `nil` on success.
    func bindCurrentFolder(to account: Account) async -> String? {
        guard let path = accountMatch?.bindableRepoRoot else { return nil }
        let result = GitdirBinder.bind(folderPath: path, to: account)
        if result.changedScope {
            do {
                try accountsStore.update(result.account)
                try AccountProjector.regenerate(accounts: accountsStore.accounts)
            } catch {
                return String(localized: "Bind failed: \(String(describing: error))")
            }
        }
        await resolveCurrentRepo(at: path)
        return nil
    }
}
