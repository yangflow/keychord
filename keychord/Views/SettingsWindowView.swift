import SwiftUI

/// Sidebar destinations for the dedicated Settings window.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case keys
    case importAccounts
    case backups
    case config

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .keys: return String(localized: "Keys")
        case .importAccounts: return String(localized: "Import")
        case .backups: return String(localized: "Backups")
        case .config: return String(localized: "Config")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .keys: return "key.horizontal"
        case .importAccounts: return "square.and.arrow.down"
        case .backups: return "clock.arrow.circlepath"
        case .config: return "doc.text"
        }
    }
}

/// macOS-style Settings window: sidebar + detail, hosting existing
/// language / login / keygen / import / restore / include tools.
struct SettingsWindowView: View {
    @Environment(AppState.self) private var appState

    @State private var selection: SettingsPane? = .general
    @State private var keygenResetID = UUID()
    @State private var importCandidates: [Account] = []
    @State private var importStatus: String?
    @State private var importIsError = false
    @State private var importScanDone = false

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detail
                .navigationTitle(selection?.title ?? "")
                .navigationSplitViewColumnWidth(min: 400, ideal: 520)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 640, minHeight: 420)
        .onAppear {
            if selection == nil {
                selection = .general
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue == .importAccounts, !importScanDone {
                scanForImport()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            SettingsGeneralPane()
        case .keys:
            KeygenView(
                defaultComment: appState.accountsStore.accounts.first?.gitUserEmail ?? "",
                accounts: appState.accountsStore.accounts,
                onDismiss: { keygenResetID = UUID() },
                onAttached: { account, isNew in
                    attachGeneratedKey(account, isNew: isNew)
                }
            )
            .id(keygenResetID)
        case .importAccounts:
            SettingsImportPane(
                candidates: importCandidates,
                scanDone: importScanDone,
                statusMessage: importStatus,
                statusIsError: importIsError,
                existingAliases: Set(appState.accountsStore.accounts.map(\.sshAlias)),
                onImport: importSelected
            )
            .task {
                if !importScanDone {
                    scanForImport()
                }
            }
        case .backups:
            RestoreView(
                accountsStore: appState.accountsStore,
                backups: appState.accountsStore.backups
            )
        case .config:
            SettingsConfigPane()
        }
    }

    // MARK: - Import / keygen persistence

    private func scanForImport() {
        importStatus = nil
        importIsError = false
        do {
            let current = try ConfigStore.loadFromDefaultLocations()
            importCandidates = AccountImporter.importFromExistingConfig(current)
            if importCandidates.isEmpty {
                importStatus = String(localized: "No accounts found to import")
            }
        } catch {
            importCandidates = []
            importIsError = true
            importStatus = String(localized: "Import failed: \(String(describing: error))")
        }
        importScanDone = true
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
            try AccountProjector.regenerate(
                accounts: appState.accountsStore.accounts,
                paths: .default
            )
            if let first = chosen.first(where: { !existing.contains($0.sshAlias) }) {
                appState.pendingAccountSelection = first.id
            }
            importIsError = false
            if added == 0 {
                importStatus = String(localized: "No accounts found to import")
            } else if added == 1 {
                importStatus = String(localized: "Imported 1 account")
            } else {
                importStatus = String(localized: "Imported \(added) accounts")
            }
            // Refresh checkboxes / “exists” tags without wiping the status line.
            let current = try ConfigStore.loadFromDefaultLocations()
            importCandidates = AccountImporter.importFromExistingConfig(current)
            importScanDone = true
        } catch {
            importIsError = true
            importStatus = String(localized: "Import failed: \(String(describing: error))")
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
            appState.pendingAccountSelection = account.id
            keygenResetID = UUID()
        } catch {
            keygenResetID = UUID()
        }
    }
}

// MARK: - General

struct SettingsGeneralPane: View {
    @Environment(AppLanguageStore.self) private var languageStore
    @State private var loginItem: LoginItemController

    init(loginItemService: LoginItemManaging = LoginItemService()) {
        _loginItem = State(initialValue: LoginItemController(service: loginItemService))
    }

    var body: some View {
        @Bindable var languageStore = languageStore
        return Form {
            Section {
                Picker("Language", selection: $languageStore.preference) {
                    Text("Follow System").tag(AppLanguagePreference.system)
                    Text(verbatim: "English").tag(AppLanguagePreference.english)
                    Text(verbatim: "简体中文").tag(AppLanguagePreference.simplifiedChinese)
                }

                Text("Overrides the system language for KeyChord only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if languageStore.pendingRelaunch {
                    Text("Relaunch KeyChord to apply the language everywhere.")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Button("Relaunch") {
                        AppLanguageStore.relaunch()
                    }
                }
            } header: {
                Text("Language")
            }

            Section {
                Toggle(
                    "Open at Login",
                    isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                if let message = loginItem.lastErrorMessage {
                    Text(verbatim: message)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                } else if loginItem.requiresApproval {
                    Text("Open at Login needs approval in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("Launch keychord in the menu bar when you log in to this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }
}

// MARK: - Config (Includes)

struct SettingsConfigPane: View {
    @State private var confirmRemoveIncludes = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section {
                Text("Removes keychord’s Include markers from ~/.ssh/config and ~/.gitconfig. Your accounts.json and SSH keys stay in place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Remove Include (keep accounts.json)", role: .destructive) {
                    confirmRemoveIncludes = true
                }
            } header: {
                Text("Includes")
            }

            if let statusMessage {
                Section {
                    Text(verbatim: statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : Color.green)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Remove Include blocks?",
            isPresented: $confirmRemoveIncludes,
            titleVisibility: .visible
        ) {
            Button("Remove Include", role: .destructive) {
                removeIncludes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only strips the # --- keychord managed --- blocks. accounts.json, managed files, and private keys are not deleted.")
        }
    }

    private func removeIncludes() {
        let paths = AccountProjector.ManagedPaths.default
        do {
            try IncludeInstaller.uninstallUserIncludes(
                sshConfigPath: paths.userSSHConfig,
                gitConfigPath: paths.userGitConfig
            )
            statusIsError = false
            statusMessage = String(localized: "Include markers removed")
        } catch {
            statusIsError = true
            statusMessage = String(localized: "Remove failed: \(String(describing: error))")
        }
    }
}

// MARK: - Import

struct SettingsImportPane: View {
    let candidates: [Account]
    let scanDone: Bool
    let statusMessage: String?
    let statusIsError: Bool
    let existingAliases: Set<String>
    let onImport: ([Account]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let statusMessage {
                Text(verbatim: statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? Color.red : Color.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, KC.space20)
                    .padding(.top, KC.space12)
            }

            if !scanDone {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading config…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ImportPickerView(
                    candidates: candidates,
                    existingAliases: existingAliases,
                    onImport: onImport,
                    embedded: true
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
