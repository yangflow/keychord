import SwiftUI

/// The standalone macOS window for managing keychord accounts.
/// NavigationSplitView with a sidebar list and a detail pane form.
/// Sidebar actions live in the window toolbar so the system split
/// view toggle stays intact.
struct AccountsWindowView: View {
    @Environment(AppState.self) private var appState

    @State private var selection: UUID?
    @State private var draft: Account?
    @State private var isNewDraft = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showingKeygen = false
    @State private var showingRestore = false
    @State private var showingSettings = false
    @State private var importBatch: ImportBatch?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 640, minHeight: 420)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { beginNew() } label: {
                    Label("Add account", systemImage: "plus")
                        .accountsToolbarSymbol()
                }
                .help("Add a new account")

                Button { showingKeygen = true } label: {
                    Label("New SSH key", systemImage: "key.horizontal")
                        .accountsToolbarSymbol()
                }
                .help("Generate a new SSH key")

                Button { importFromExistingConfig() } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .accountsToolbarSymbol()
                }
                .help("Import from existing config")

                Button { showingRestore = true } label: {
                    Label("Restore", systemImage: "clock.arrow.circlepath")
                        .accountsToolbarSymbol()
                }
                .help("Restore from backup")

                Button { showingSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                        .accountsToolbarSymbol()
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showingKeygen) {
            KeygenView(
                defaultComment: draft?.gitUserEmail
                    ?? appState.accountsStore.accounts.first?.gitUserEmail
                    ?? "",
                accounts: appState.accountsStore.accounts,
                onDismiss: { showingKeygen = false },
                onAttached: { account, isNew in
                    attachGeneratedKey(account, isNew: isNew)
                }
            )
            .frame(width: 420, height: 440)
        }
        .sheet(isPresented: $showingRestore) {
            RestoreView(
                accountsStore: appState.accountsStore,
                backups: appState.accountsStore.backups,
                onDismiss: { showingRestore = false }
            )
            .frame(width: 480, height: 440)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(onDismiss: { showingSettings = false })
                .frame(width: 420, height: 360)
        }
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
        .onAppear {
            if appState.pendingAddNew {
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
                ForEach(appState.accountsStore.accounts) { account in
                    AccountsSidebarRow(account: account)
                        .tag(account.id)
                }
            } header: {
                Text("Accounts")
            }
        }
        .listStyle(.sidebar)
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
                onDelete: isNewDraft ? nil : { delete(id: draftID) }
            )
        } else {
            emptyDetail
        }
    }

    @ViewBuilder
    private var emptyDetail: some View {
        if appState.accountsStore.accounts.isEmpty {
            ContentUnavailableView {
                Label("No accounts yet", systemImage: "person.2.circle")
            } description: {
                Text("Import your existing SSH + gitconfig, or add a new account to get started.")
            } actions: {
                Button("Import existing", systemImage: "square.and.arrow.down", action: importFromExistingConfig)
                Button("Add new", systemImage: "plus", action: beginNew)
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

    private func beginNew() {
        draft = Account(
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
        } catch {
            statusIsError = true
            statusMessage = String(localized: "Save failed: \(String(describing: error))")
        }
    }

    private func delete(id: UUID) {
        do {
            try appState.accountsStore.delete(id: id)
            try regenerate()
            if selection == id {
                selection = nil
                draft = nil
            }
            statusIsError = false
            statusMessage = String(localized: "Deleted")
        } catch {
            statusIsError = true
            statusMessage = String(localized: "Delete failed: \(String(describing: error))")
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

    private func attachGeneratedKey(_ account: Account, isNew: Bool) {
        do {
            try KeyAttachment.commit(
                account: account,
                isNew: isNew,
                store: appState.accountsStore,
                regenerate: { accounts in
                    try AccountProjector.regenerate(accounts: accounts, paths: .default)
                }
            )
            selection = account.id
            draft = account
            isNewDraft = false
            statusIsError = false
            if isNew {
                statusMessage = String(localized: "Key attached · new account — fill in alias & identity")
            } else {
                let name = account.label.isEmpty ? account.sshAlias : account.label
                statusMessage = String(localized: "Key attached · \(name)")
            }
        } catch {
            statusIsError = true
            statusMessage = String(localized: "Attach failed: \(String(describing: error))")
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

    var body: some View {
        HStack(spacing: KC.space10) {
            Circle()
                .fill(account.color.color)
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
