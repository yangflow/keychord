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

    /// Current-repo match from a folder drop onto the menu bar icon (or the
    /// open popover). It outlives the popover: only the next drop, the card's
    /// clear control, or an unbind that drops the path replaces it. Finder's
    /// front window is never resolved behind the user's back.
    var accountMatch: AccountMatchResult?

    /// Author-vs-key comparison for the matched repository, if it has one.
    /// Recomputed with every resolve; `nil` while there is no match.
    var identityAudit: IdentityAudit?

    /// Set when more than one account's `gitdir:` scope covers the matched
    /// repository, so the card can explain which one git actually uses.
    var gitdirOverlap: GitdirOverlap?

    /// A missing `gitdir:` path that looks like the matched folder's previous
    /// name, offered as a one-tap retarget. `nil` once dismissed or repaired.
    var staleGitdir: StaleGitdirRepair.Candidate?

    /// Settings pane to select when the Settings window opens. Set by the
    /// popover's empty state so Import is reachable without the gear.
    var pendingSettingsPane: SettingsPane?

    /// Unsaved account the Accounts window should open as a new draft, built
    /// from a failed drop. The popover never embeds the full form.
    var pendingNewAccountDraft: Account?

    /// Folder to re-resolve once that draft is saved, so the popover can show
    /// the match the user was after.
    var pendingBindFolder: String?

    /// Id of that draft, so saving some *other* new account cannot trigger the
    /// re-resolve meant for this one (or fire it after the user cancelled).
    var pendingBindDraftID: UUID?

    /// Short-lived undo for the last scope change, shown as a toast on the
    /// match card.
    var scopeUndo: ScopeUndo?

    private var scopeUndoTask: Task<Void, Never>?

    /// A scope change that can still be taken back: the accounts exactly as
    /// they were before the write.
    struct ScopeUndo: Equatable, Sendable, Identifiable {
        let id: UUID
        /// Accounts to write back verbatim, including their original scopes.
        let previousAccounts: [Account]
        /// Label of the account the folder ended up bound to.
        let boundLabel: String
        let repoRoot: String
        let expiresAt: Date

        static let window: TimeInterval = 5

        /// Whole seconds left on the offer, rounded up and floored at zero.
        /// Lives here rather than in the toast so the countdown is testable and
        /// the view only renders it.
        func remainingSeconds(at now: Date) -> Int {
            max(0, Int(expiresAt.timeIntervalSince(now).rounded(.up)))
        }
    }

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
        gitdirOverlap = nil
        staleGitdir = nil
        clearScopeUndo()
    }

    // MARK: - Undo for scope changes

    /// Arm the 5-second undo toast. The snapshot is taken before the write, so
    /// restoring it puts every gitdir list back exactly as it was.
    func recordScopeUndo(
        previousAccounts: [Account],
        boundLabel: String,
        repoRoot: String,
        now: Date = Date()
    ) {
        let undo = ScopeUndo(
            id: UUID(),
            previousAccounts: previousAccounts,
            boundLabel: boundLabel,
            repoRoot: repoRoot,
            expiresAt: now.addingTimeInterval(ScopeUndo.window)
        )
        scopeUndo = undo
        scopeUndoTask?.cancel()
        scopeUndoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ScopeUndo.window))
            guard !Task.isCancelled else { return }
            guard let self, self.scopeUndo?.id == undo.id else { return }
            self.scopeUndo = nil
        }
    }

    func clearScopeUndo() {
        scopeUndoTask?.cancel()
        scopeUndoTask = nil
        scopeUndo = nil
    }

    /// Put the pre-change scopes back, reproject, and re-resolve the folder.
    func undoScopeChange() async -> String? {
        guard let undo = scopeUndo else { return nil }
        clearScopeUndo()
        do {
            for account in undo.previousAccounts {
                try accountsStore.update(account)
            }
            try AccountProjector.regenerate(accounts: accountsStore.accounts)
        } catch {
            return String.loc("Undo failed: \(String(describing: error))")
        }
        await resolveCurrentRepo(at: undo.repoRoot)
        return nil
    }

    /// Label the toast shows for the account a folder was bound to.
    private func displayLabel(of account: Account) -> String {
        account.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String.loc("(unnamed)")
            : account.label
    }

    /// Shared resolve path used by menu-bar icon drops and popover `.onDrop`.
    func resolveCurrentRepo(at path: String) async {
        let accounts = accountsStore.accounts
        let result = await CurrentRepoResolver.matchAccount(path: path, accounts: accounts)
        accountMatch = result
        identityAudit = nil
        gitdirOverlap = nil
        staleGitdir = nil

        switch result {
        case .matched(let account, let repoRoot, _):
            accountsStore.touchLastUsed(id: account.id)
            gitdirOverlap = GitdirOverlap.detect(repoRoot: repoRoot, accounts: accounts)
            let identity = await CurrentRepoResolver.readEffectiveIdentity(at: repoRoot)
            identityAudit = IdentityAudit.audit(
                account: account,
                repoRoot: repoRoot,
                identity: identity,
                accounts: accounts
            )
        case .noMatchingGitdir(let repoRoot), .conflictingGlobals(let repoRoot, _):
            // A repository no scope claims is where a renamed project shows up.
            staleGitdir = StaleGitdirRepair.candidate(
                forDroppedFolder: repoRoot,
                accounts: accounts
            )
        case .notARepo:
            break
        }
    }

    /// One-tap `gitdir:` bind for the folder in the current unresolved match.
    /// Adds a path to `account`, persists, regenerates the managed files, and
    /// re-resolves so the card flips to the matched state. Returns a
    /// user-facing message when the write fails; `nil` on success.
    func bindCurrentFolder(to account: Account) async -> String? {
        guard let path = accountMatch?.bindableRepoRoot else { return nil }
        let result = GitdirBinder.bind(folderPath: path, to: account)
        if result.changedScope {
            let snapshot = [account]
            do {
                try accountsStore.update(result.account)
                try AccountProjector.regenerate(accounts: accountsStore.accounts)
            } catch {
                return String.loc("Bind failed: \(String(describing: error))")
            }
            recordScopeUndo(
                previousAccounts: snapshot,
                boundLabel: displayLabel(of: account),
                repoRoot: path
            )
            accountsStore.touchLastUsed(id: account.id)
        }
        await resolveCurrentRepo(at: path)
        return nil
    }

    /// Build the draft the Accounts window opens for “create an identity and
    /// bind it here”. Returns false when there is no folder to scope.
    func prepareNewAccountDraftForMatch() async -> Bool {
        guard let path = accountMatch?.bindableRepoRoot else { return false }
        let identity = await GitGlobalIdentity.read()
        guard let draft = DroppedFolderAccountDraft.make(
            folderPath: path,
            globalIdentity: identity,
            existingAccounts: accountsStore.accounts
        ) else {
            return false
        }
        pendingNewAccountDraft = draft
        pendingBindFolder = path
        pendingBindDraftID = draft.id
        return true
    }

    /// True when `accountID` is the draft a failed drop asked for.
    func isPendingBindDraft(_ accountID: UUID) -> Bool {
        pendingBindDraftID == accountID
    }

    /// Called by the Accounts window after it saves that draft: re-resolve so
    /// the popover shows the match the user was after.
    func finishPendingBind() async {
        guard let path = pendingBindFolder else { return }
        pendingBindFolder = nil
        pendingBindDraftID = nil
        await resolveCurrentRepo(at: path)
    }

    /// Drop the matched folder's own `gitdir:` entry from the account that owns
    /// it, then re-resolve. A parent scope is left alone, so this only appears
    /// when the folder has an entry of its own.
    func unbindMatchedFolder() async -> String? {
        guard case .matched(let account, let repoRoot, _) = accountMatch else { return nil }
        let result = GitdirBinder.unbind(folderPath: repoRoot, from: account)
        guard result.changedScope else {
            await resolveCurrentRepo(at: repoRoot)
            return nil
        }
        do {
            try accountsStore.update(result.account)
            try AccountProjector.regenerate(accounts: accountsStore.accounts)
        } catch {
            return String.loc("Unbind failed: \(String(describing: error))")
        }
        await resolveCurrentRepo(at: repoRoot)
        return nil
    }

    /// Move the matched folder to another identity: remove its own entry from
    /// the current owner (if it has one) and add it to `account`. One save, one
    /// projection, then re-resolve.
    func rebindMatchedFolder(to account: Account) async -> String? {
        guard case .matched(let current, let repoRoot, _) = accountMatch else { return nil }
        guard current.id != account.id else { return nil }

        let removal = GitdirBinder.unbind(folderPath: repoRoot, from: current)
        let addition = GitdirBinder.bind(folderPath: repoRoot, to: account)
        let snapshot = [current, account]
        do {
            if removal.changedScope {
                try accountsStore.update(removal.account)
            }
            if addition.changedScope {
                try accountsStore.update(addition.account)
            }
            if removal.changedScope || addition.changedScope {
                try AccountProjector.regenerate(accounts: accountsStore.accounts)
            }
        } catch {
            return String.loc("Rebind failed: \(String(describing: error))")
        }
        if removal.changedScope || addition.changedScope {
            recordScopeUndo(
                previousAccounts: snapshot,
                boundLabel: displayLabel(of: account),
                repoRoot: repoRoot
            )
            accountsStore.touchLastUsed(id: account.id)
        }
        await resolveCurrentRepo(at: repoRoot)
        return nil
    }

    /// Point a stale `gitdir:` path at the folder that was just dropped,
    /// keeping the account's other paths. Only the one dead path changes.
    func repairStaleGitdir() async -> String? {
        guard let candidate = staleGitdir else { return nil }
        let updated = StaleGitdirRepair.repair(candidate)
        do {
            try accountsStore.update(updated)
            try AccountProjector.regenerate(accounts: accountsStore.accounts)
        } catch {
            return String.loc("Could not update the gitdir path: \(String(describing: error))")
        }
        await resolveCurrentRepo(at: ConfigStore.expand(candidate.replacementPath))
        return nil
    }

    /// Keep the suggestion out of the way without touching any account.
    func dismissStaleGitdir() {
        staleGitdir = nil
    }

    /// Scope the matched folder to `account` explicitly, so it wins the overlap
    /// on its own most-specific path instead of relying on block order.
    func claimMatchedFolder(for account: Account) async -> String? {
        guard case .matched(_, let repoRoot, _) = accountMatch else { return nil }
        let result = GitdirBinder.bind(folderPath: repoRoot, to: account)
        if result.changedScope {
            let snapshot = [account]
            do {
                try accountsStore.update(result.account)
                try AccountProjector.regenerate(accounts: accountsStore.accounts)
            } catch {
                return String.loc("Bind failed: \(String(describing: error))")
            }
            recordScopeUndo(
                previousAccounts: snapshot,
                boundLabel: displayLabel(of: account),
                repoRoot: repoRoot
            )
            accountsStore.touchLastUsed(id: account.id)
        }
        await resolveCurrentRepo(at: repoRoot)
        return nil
    }

    /// Drop one overlapping `gitdir:` path from the account that loses, e.g.
    /// `personal`'s `~/`, leaving its other scopes alone.
    func releaseGitdirPath(_ path: String, from account: Account) async -> String? {
        let repoRoot: String?
        if case .matched(_, let root, _) = accountMatch { repoRoot = root } else { repoRoot = nil }

        let result = GitdirBinder.removePath(path, from: account)
        if result.changedScope {
            do {
                try accountsStore.update(result.account)
                try AccountProjector.regenerate(accounts: accountsStore.accounts)
            } catch {
                return String.loc("Unbind failed: \(String(describing: error))")
            }
        }
        if let repoRoot {
            await resolveCurrentRepo(at: repoRoot)
        }
        return nil
    }

    /// Add this provider's `insteadOf` presets so an HTTPS remote goes through
    /// the account's SSH alias, then re-resolve any active match.
    func applySSHRewrites(to account: Account) async -> String? {
        var updated = account
        updated.applyInsteadOfPreset()
        guard updated.urlRewrites != account.urlRewrites else { return nil }
        do {
            try accountsStore.update(updated)
            try AccountProjector.regenerate(accounts: accountsStore.accounts)
        } catch {
            return String.loc("Could not add the SSH rewrite: \(String(describing: error))")
        }
        if case .matched(_, let repoRoot, _) = accountMatch {
            await resolveCurrentRepo(at: repoRoot)
        }
        return nil
    }
}
