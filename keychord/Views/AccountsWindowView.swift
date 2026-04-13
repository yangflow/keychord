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
    @State private var showingCloudSync = false
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
                }
                .help("Add a new account")

                Button { showingKeygen = true } label: {
                    Label("New SSH key", systemImage: "key.horizontal")
                }
                .help("Generate a new SSH key")

                Button { importFromExistingConfig() } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import from existing config")

                Button { showingRestore = true } label: {
                    Label("Restore", systemImage: "clock.arrow.circlepath")
                }
                .help("Restore from backup")

                Button { showingCloudSync = true } label: {
                    Label("iCloud sync", systemImage: "icloud")
                }
                .help("iCloud Sync settings")
            }
        }
        .sheet(isPresented: $showingKeygen) {
            KeygenView(
                defaultComment: draft?.gitUserEmail ?? "",
                onDismiss: { showingKeygen = false },
                onKeyCreated: { }
            )
            .frame(width: 420, height: 400)
        }
        .sheet(isPresented: $showingRestore) {
            RestoreView(
                accountsStore: appState.accountsStore,
                backups: appState.accountsStore.backups,
                onDismiss: { showingRestore = false }
            )
            .frame(width: 420, height: 400)
        }
        .sheet(isPresented: $showingCloudSync) {
            CloudSyncView(
                cloudSync: appState.cloudSync,
                onDismiss: { showingCloudSync = false }
            )
            .frame(width: 420, height: 340)
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
            Section("Accounts") {
                ForEach(appState.accountsStore.accounts) { account in
                    AccountsSidebarRow(account: account)
                        .tag(account.id)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailContent: some View {
        if let draft = draft {
            AccountDetailView(
                draft: Binding(
                    get: { self.draft ?? draft },
                    set: { self.draft = $0 }
                ),
                isNew: isNewDraft,
                statusMessage: statusMessage,
                statusIsError: statusIsError,
                onSave: saveDraft,
                onRevert: revertDraft,
                onDelete: isNewDraft ? nil : { delete(id: draft.id) }
            )
        } else {
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: KC.space16) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No account selected")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            if appState.accountsStore.accounts.isEmpty {
                Text("Import your existing SSH + gitconfig, or add a new account to get started.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                HStack(spacing: KC.space12) {
                    Button { importFromExistingConfig() } label: {
                        Label("Import existing", systemImage: "square.and.arrow.down")
                    }
                    Button { beginNew() } label: {
                        Label("Add new", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Pick an account in the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Draft lifecycle

    private func beginNew() {
        draft = Account(
            id: UUID(),
            label: "",
            githubUsername: "",
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
            statusMessage = "Saved · \(updated.label)"
        } catch {
            statusIsError = true
            statusMessage = "Save failed: \(error)"
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
            statusMessage = "Deleted"
        } catch {
            statusIsError = true
            statusMessage = "Delete failed: \(error)"
        }
    }

    private func importFromExistingConfig() {
        do {
            let current = try ConfigStore.loadFromDefaultLocations()
            let records = AccountImporter.importFromExistingConfig(current)
            if records.isEmpty {
                statusIsError = false
                statusMessage = "No accounts found to import"
                return
            }
            importBatch = ImportBatch(accounts: records)
        } catch {
            statusIsError = true
            statusMessage = "Import failed: \(error)"
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
            statusMessage = "Imported \(added) account\(added == 1 ? "" : "s")"
        } catch {
            statusIsError = true
            statusMessage = "Import failed: \(error)"
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
                .fill(accountColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.label.isEmpty ? "(unnamed)" : account.label)
                    .font(KC.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: KC.space4) {
                    Text(account.sshAlias.isEmpty ? "no alias" : account.sshAlias)
                        .font(KC.rowCaptionMono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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

    private var accountColor: Color {
        switch account.color {
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .purple: return .purple
        case .yellow: return .yellow
        }
    }
}

// MARK: - Import batch wrapper

private struct ImportBatch: Identifiable {
    let id = UUID()
    let accounts: [Account]
}
