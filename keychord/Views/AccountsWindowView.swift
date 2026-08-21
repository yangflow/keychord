import SwiftUI

/// The standalone macOS window for managing keychord accounts.
/// NavigationSplitView with a sidebar list and a detail pane form.
/// Primary actions are pinned on the *detail* toolbar only so collapsing
/// the sidebar does not reparent them beside the automatic sidebar toggle.
struct AccountsWindowView: View {
    @Environment(AppState.self) private var appState

    @State private var selection: UUID?
    @State private var draft: Account?
    @State private var isNewDraft = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var importBatch: ImportBatch?
    /// Account awaiting delete confirmation. Delete leaves a private key and
    /// gitdir paths behind, so the user sees them first.
    @State private var pendingDelete: Account?
    /// Timestamp of the last successful write, which makes the Save button
    /// flash its acknowledgement (#45).
    @State private var lastSavedAt: Date?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detailContent
                .toolbar {
                    // Keep Add on the detail column (not the split view /
                    // sidebar). Otherwise AppKit injects the sidebar-toggle
                    // chevron into the same primaryAction cluster on collapse
                    // and the action icons hitch/jump.
                    ToolbarItem(placement: .primaryAction) {
                        Button { beginNew() } label: {
                            Label("Add account", systemImage: "plus")
                                .accountsToolbarSymbol()
                        }
                        .help("Add a new account")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 640, minHeight: 420)
        .sheet(item: $importBatch) { batch in
            ImportPickerView(
                candidates: batch.accounts,
                existingAliases: Set(appState.accountsStore.accounts.map(\.sshAlias)),
                onImport: { chosen in
                    importBatch = nil
                    importSelected(chosen)
                },
                onDismiss: { importBatch = nil }
            )
            .frame(width: 460, height: 420)
        }
        .sheet(item: $pendingDelete) { account in
            DeleteAccountSheet(
                account: account,
                leftovers: KeyFileRemover.leftovers(
                    for: account,
                    in: appState.accountsStore.accounts
                ),
                onCancel: { pendingDelete = nil },
                onConfirm: { removeKey in
                    pendingDelete = nil
                    delete(account, removePrivateKey: removeKey)
                }
            )
        }
        .onChange(of: selection) { _, newSelection in
            loadDraftForSelection(newSelection)
        }
        .onChange(of: appState.pendingAccountSelection) { _, newValue in
            guard let id = newValue else { return }
            selection = id
            appState.pendingAccountSelection = nil
        }
        .onChange(of: appState.pendingAddNew) { _, newValue in
            guard newValue else { return }
            appState.pendingAddNew = false
            beginNew()
        }
        .onChange(of: appState.pendingNewAccountDraft) { _, newValue in
            guard let prefilled = newValue else { return }
            appState.pendingNewAccountDraft = nil
            beginNew(prefilled: prefilled)
        }
        .onAppear {
            if let prefilled = appState.pendingNewAccountDraft {
                appState.pendingNewAccountDraft = nil
                beginNew(prefilled: prefilled)
            } else if appState.pendingAddNew {
                appState.pendingAddNew = false
                beginNew()
            } else if let pending = appState.pendingAccountSelection {
                selection = pending
                appState.pendingAccountSelection = nil
            } else if selection == nil, let first = appState.accountsStore.accounts.first {
                selection = first.id
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(AccountOrdering.byLastUsed(appState.accountsStore.accounts)) { account in
                    AccountsSidebarRow(
                        account: account,
                        color: sidebarColor(for: account)
                    )
                    .tag(account.id)
                }
            } header: {
                Text("Accounts")
            }
        }
        .listStyle(.sidebar)
    }

    /// Prefer the in-edit draft color so the sidebar dot tracks the color panel live.
    private func sidebarColor(for account: Account) -> Account.AccountColor {
        if let draft, draft.id == account.id {
            return draft.color
        }
        return account.color
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailContent: some View {
        if let draftBinding = Binding($draft) {
            let draftID = draftBinding.wrappedValue.id
            AccountDetailView(
                draft: draftBinding,
                isNew: isNewDraft,
                statusMessage: statusMessage,
                statusIsError: statusIsError,
                onSave: saveDraft,
                onRevert: revertDraft,
                onDelete: isNewDraft ? nil : { requestDelete(id: draftID) },
                savedAt: lastSavedAt
            )
        } else {
            emptyDetail
        }
    }

    /// Deleting clears the draft, so the outcome — including “the private key
    /// was kept because …” — has to be readable without a selected account.
    @ViewBuilder
    private var emptyDetail: some View {
        VStack(spacing: 0) {
            emptyDetailBody

            if let statusMessage {
                Divider()
                HStack {
                    Label {
                        Text(verbatim: statusMessage)
                    } icon: {
                        Image(systemName: statusIsError ? "xmark.circle" : "checkmark.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(statusIsError ? Color.red : Color.green)
                    Spacer()
                }
                .padding(.horizontal, KC.space20)
                .padding(.vertical, KC.space12)
            }
        }
    }

    @ViewBuilder
    private var emptyDetailBody: some View {
        if appState.accountsStore.accounts.isEmpty {
            ContentUnavailableView {
                Label("No accounts yet", systemImage: "person.2.circle")
            } description: {
                Text("Import your existing SSH + gitconfig, or add a new account to get started.")
            } actions: {
                Button("Import existing", systemImage: "square.and.arrow.down", action: importFromExistingConfig)
                // Not `action: beginNew`: the prefill parameter (#41) makes the
                // bare reference `(Account?) -> Void`.
                Button("Add new", systemImage: "plus") { beginNew() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "No account selected",
                systemImage: "person.2.circle",
                description: Text("Pick an account in the sidebar.")
            )
        }
    }

    // MARK: - Draft lifecycle

    /// `prefilled` comes from a failed drop (#41): already scoped to that
    /// folder, with the global git identity and port 443 filled in.
    private func beginNew(prefilled: Account? = nil) {
        draft = prefilled ?? Account(
            id: UUID(),
            label: "",
            username: "",
            provider: .github,
            sshAlias: "",
            keyPath: "",
            keyFingerprint: nil,
            sshPort: .port443,
            gitUserName: "",
            gitUserEmail: "",
            scope: .global,
            urlRewrites: [],
            color: .blue,
            notes: "",
            createdAt: Date(),
            updatedAt: Date(),
            lastUsedAt: nil
        )
        isNewDraft = true
        selection = nil
        statusMessage = nil
    }

    private func loadDraftForSelection(_ newSelection: UUID?) {
        guard let id = newSelection else {
            if !isNewDraft { draft = nil }
            return
        }
        if let acc = appState.accountsStore.accounts.first(where: { $0.id == id }) {
            draft = acc
            isNewDraft = false
            statusMessage = nil
        }
    }

    private func revertDraft() {
        if let id = selection,
           let acc = appState.accountsStore.accounts.first(where: { $0.id == id }) {
            draft = acc
            isNewDraft = false
        } else {
            draft = nil
            isNewDraft = false
        }
        statusMessage = nil
    }

    // MARK: - Save / Delete / Import

    private func saveDraft() {
        guard var updated = draft else { return }
        updated.updatedAt = Date()
        let wasNew = isNewDraft
        do {
            if isNewDraft {
                try appState.accountsStore.add(updated)
                selection = updated.id
                isNewDraft = false
            } else {
                try appState.accountsStore.update(updated)
            }
            try regenerate()
            draft = updated
            statusIsError = false
            statusMessage = String(localized: "Saved · \(updated.label)")
            lastSavedAt = Date()
        } catch {
            statusIsError = true
            statusMessage = String(localized: "Save failed: \(String(describing: error))")
            return
        }

        // The identity was created to claim a dropped folder (#41): resolve it
        // again and show the popover with the match the user asked for.
        if wasNew, appState.isPendingBindDraft(updated.id) {
            Task {
                await appState.finishPendingBind()
                await StatusItemDropTargetController.shared.openPopoverShowingMatch()
            }
        }
    }

    private func requestDelete(id: UUID) {
        guard let account = appState.accountsStore.accounts.first(where: { $0.id == id }) else {
            return
        }
        pendingDelete = account
    }

    private func delete(_ account: Account, removePrivateKey: Bool) {
        do {
            try appState.accountsStore.delete(id: account.id)
            try regenerate()
            if selection == account.id {
                selection = nil
                draft = nil
            }
            statusIsError = false
            statusMessage = String(localized: "Deleted")
        } catch {
            statusIsError = true
            statusMessage = String(localized: "Delete failed: \(String(describing: error))")
            return
        }

        // The record is gone either way; a key that refuses to go says so
        // without pretending the delete failed.
        guard removePrivateKey else { return }
        do {
            try KeyFileRemover.removePrivateKey(
                of: account,
                in: appState.accountsStore.accounts
            )
            statusMessage = String(localized: "Deleted · private key removed")
        } catch {
            statusIsError = true
            statusMessage = String(localized: "Deleted, but the private key was kept: \(String(describing: error))")
        }
    }

    private func importFromExistingConfig() {
        do {
            let current = try ConfigStore.loadFromDefaultLocations()
            let records = AccountImporter.importFromExistingConfig(current)
            if records.isEmpty {
                statusIsError = false
                statusMessage = String(localized: "No accounts found to import")
                return
            }
            importBatch = ImportBatch(accounts: records)
        } catch {
            statusIsError = true
            statusMessage = String(localized: "Import failed: \(String(describing: error))")
        }
    }

    private func importSelected(_ chosen: [Account]) {
        guard !chosen.isEmpty else { return }
        let existing = Set(appState.accountsStore.accounts.map(\.sshAlias))
        var added = 0
        do {
            for account in chosen {
                if existing.contains(account.sshAlias) { continue }
                try appState.accountsStore.add(account)
                added += 1
            }
            try regenerate()
            if let first = chosen.first(where: { !existing.contains($0.sshAlias) }) {
                selection = first.id
            }
            statusIsError = false
            if added == 1 {
                statusMessage = String(localized: "Imported 1 account")
            } else {
                statusMessage = String(localized: "Imported \(added) accounts")
            }
        } catch {
            statusIsError = true
            statusMessage = String(localized: "Import failed: \(String(describing: error))")
        }
    }

    private func regenerate() throws {
        try AccountProjector.regenerate(
            accounts: appState.accountsStore.accounts,
            paths: .default
        )
    }
}

// MARK: - Sidebar row

private struct AccountsSidebarRow: View {
    let account: Account
    let color: Account.AccountColor

    var body: some View {
        HStack(spacing: KC.space10) {
            Circle()
                .fill(color.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                if account.label.isEmpty {
                    Text("(unnamed)")
                        .font(KC.rowTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(verbatim: account.label)
                        .font(KC.rowTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: KC.space4) {
                    if account.sshAlias.isEmpty {
                        Text("no alias")
                            .font(KC.rowCaptionMono)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(verbatim: account.sshAlias)
                            .font(KC.rowCaptionMono)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if account.scope.isScoped {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, KC.space4)
    }
}

// MARK: - Import batch wrapper

private struct ImportBatch: Identifiable {
    let id = UUID()
    let accounts: [Account]
}

// MARK: - Toolbar symbol optics

private extension Label where Title == Text, Icon == Image {
    /// Keep primary-action SF Symbols optically aligned in the accounts
    /// window toolbar (mixed symbol templates otherwise look uneven).
    func accountsToolbarSymbol() -> some View {
        self
            .labelStyle(.iconOnly)
            .font(.body)
            .imageScale(.large)
            .symbolRenderingMode(.monochrome)
    }
}
