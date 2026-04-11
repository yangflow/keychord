import SwiftUI

/// The standalone macOS window for managing keychord accounts.
/// NavigationSplitView with a sidebar (account list + add/delete +
/// import) and a detail pane (account form).
struct AccountsWindowView: View {
    @ObservedObject var appState: AppState

    @State private var selection: UUID?
    @State private var draft: Account?
    @State private var isNewDraft = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showingKeygen = false
    @State private var showingRestore = false

    private let backups = BackupService()

    var body: some View {
        NavigationSplitView {
            AccountsSidebar(
                accounts: appState.accountsStore.accounts,
                selection: $selection,
                onAddNew: { beginNew() },
                onDelete: { id in delete(id: id) },
                onImport: { importFromExistingConfig() }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingKeygen = true
                } label: {
                    Label("New Key", systemImage: "key.horizontal")
                }
                .help("Generate a new SSH key")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showingRestore = true
                } label: {
                    Label("Restore", systemImage: "clock.arrow.circlepath")
                }
                .help("Restore from backup")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    importFromExistingConfig()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import from existing SSH + gitconfig")
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
                sourcePaths: sourcePathsForRestore(),
                backups: backups,
                onDismiss: { showingRestore = false }
            )
            .frame(width: 420, height: 400)
        }
        .onChange(of: selection) { _, newSelection in
            loadDraftForSelection(newSelection)
        }
        .onChange(of: appState.pendingAccountSelection) { _, newValue in
            guard let id = newValue else { return }
            selection = id
            appState.pendingAccountSelection = nil
        }
        .onAppear {
            if let pending = appState.pendingAccountSelection {
                selection = pending
                appState.pendingAccountSelection = nil
            } else if selection == nil, let first = appState.accountsStore.accounts.first {
                selection = first.id
            }
        }
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
                    Button {
                        importFromExistingConfig()
                    } label: {
                        Label("Import existing", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        beginNew()
                    } label: {
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

    // MARK: - Helpers

    private func sourcePathsForRestore() -> [String] {
        var paths: [String] = [
            ConfigStore.expand("~/.ssh/config"),
            ConfigStore.expand("~/.gitconfig")
        ]
        // Include any managed includeIf files from the current config
        if let model = try? ConfigStore.loadFromDefaultLocations() {
            for rule in model.includeIfRules {
                let expanded = ConfigStore.expand(rule.path)
                if !paths.contains(expanded) {
                    paths.append(expanded)
                }
            }
        }
        return paths
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
            try appState.accountsStore.replaceAll(records)
            try regenerate()
            if let first = appState.accountsStore.accounts.first {
                selection = first.id
            }
            statusIsError = false
            statusMessage = "Imported \(records.count) account\(records.count == 1 ? "" : "s")"
        } catch {
            statusIsError = true
            statusMessage = "Import failed: \(error)"
        }
    }

    private func regenerate() throws {
        try AccountProjector.regenerate(
            accounts: appState.accountsStore.accounts,
            paths: .default,
            backups: backups
        )
    }
}
