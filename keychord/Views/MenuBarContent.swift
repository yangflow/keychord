import SwiftUI
import UniformTypeIdentifiers

struct MenuBarContent: View {
    @ObservedObject var appState: AppState
    var onOpenAccountsWindow: () -> Void = {}
    var onOpenAccount: (UUID) -> Void = { _ in }
    var onAddNewAccount: () -> Void = {}
    var onOpenAbout: () -> Void = {}

    @State private var model = ConfigModel()
    @State private var probeStates: [String: HostProbeState] = [:]
    @State private var diagnoses: [Diagnosis] = []
    @State private var resolvedRepo: ResolvedRepo?
    @State private var repoResolveError: String?
    @State private var isDropTargeted = false
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var isProbing = false
    @State private var isDoctorExpanded = false
    @State private var isFixing = false

    init(
        appState: AppState,
        onOpenAccountsWindow: @escaping () -> Void = {},
        onOpenAccount: @escaping (UUID) -> Void = { _ in },
        onAddNewAccount: @escaping () -> Void = {},
        onOpenAbout: @escaping () -> Void = {}
    ) {
        self.appState = appState
        self.onOpenAccountsWindow = onOpenAccountsWindow
        self.onOpenAccount = onOpenAccount
        self.onAddNewAccount = onAddNewAccount
        self.onOpenAbout = onOpenAbout
    }

    var body: some View {
        mainView
        .frame(width: KC.popoverWidth, height: KC.popoverHeight)
        .task {
            await refresh()
        }
        .onChange(of: appState.droppedPath) { _, newValue in
            guard let newValue else { return }
            Task {
                await resolveRepo(at: newValue)
                appState.droppedPath = nil
            }
        }
    }

    // MARK: - Main view

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Group {
                if isLoading {
                    loadingView
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if let loadError {
                    errorView(loadError)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView(showsIndicators: false) {
                        sections
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .padding(.vertical, KC.space8)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: KC.space8) {
            Image(systemName: "key.horizontal.fill")
                .foregroundStyle(.tint)
                .font(.body)
            Text("KeyChord")
                .font(.title3.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, KC.rowHPadding)
        .padding(.vertical, KC.space8)
    }

    // MARK: - Loading / error

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading config…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, KC.rowHPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Load failed", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, KC.rowHPadding)
        .padding(.vertical, 10)
    }

    // MARK: - Sections

    @ViewBuilder
    private var sections: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appState.accountsStore.accounts.isEmpty {
                // Hero — Current Repo callout
                if let resolved = resolvedRepo {
                    CurrentRepoRow(
                        resolved: resolved,
                        probe: resolved.sshAlias.flatMap { probeStates[$0] } ?? .idle
                    )
                } else if let repoError = repoResolveError {
                    Text(repoError)
                        .font(KC.rowCaption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, KC.rowHPadding)
                        .padding(.top, KC.space10)
                        .padding(.bottom, KC.space4)
                }

                // Doctor summary — expand/collapse
                if !diagnoses.isEmpty {
                    DoctorSummaryRow(
                        diagnoses: diagnoses,
                        isExpanded: isDoctorExpanded,
                        onTap: { isDoctorExpanded.toggle() }
                    )
                    if isDoctorExpanded {
                        ForEach(diagnoses) { d in
                            DiagnosisRow(
                                diagnosis: d,
                                isFixing: isFixing,
                                onFix: { fixID in Task { await applyFix(fixID) } }
                            )
                        }
                    }
                }
            }

            // Accounts list — always shown so "+ Add Account" is reachable
            accountsSection
        }
        .padding(.bottom, KC.space8)
    }

    @ViewBuilder
    private var accountsSection: some View {
        let records = appState.accountsStore.accounts
        VStack(alignment: .leading, spacing: 0) {
            Text(accountsSectionTitle(records).uppercased())
                .font(KC.sectionLabel)
                .kerning(0.8)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, KC.rowHPadding)
                .padding(.top, KC.sectionHeaderTop)
                .padding(.bottom, KC.sectionHeaderBottom)

            KCCard {
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { idx, record in
                        Button {
                            onOpenAccount(record.id)
                        } label: {
                            AccountRow(
                                record: record,
                                probe: probeStates[record.sshAlias] ?? .idle
                            )
                        }
                        .buttonStyle(.plain)
                        Divider()
                            .padding(.leading, KC.rowHPadding + 18)
                    }
                    addAccountRow
                }
            }
            .padding(.horizontal, KC.space10)
        }
    }

    private var addAccountRow: some View {
        Button {
            onAddNewAccount()
        } label: {
            HStack(spacing: KC.space10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tint)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Account")
                        .font(KC.rowTitle)
                        .foregroundStyle(.tint)
                    Text("Create a new Git identity")
                        .font(KC.rowCaption)
                        .foregroundStyle(.tint.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, KC.rowHPadding)
            .padding(.vertical, KC.space8)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.02))
        }
        .buttonStyle(.plain)
    }

    private func accountsSectionTitle(_ records: [Account]) -> String {
        "Accounts · \(records.count)"
    }

    private func applyFix(_ fixID: FixID) async {
        isFixing = true
        defer { isFixing = false }
        do {
            try await Fixer.execute(
                fixID,
                sshConfigPath: ConfigStore.expand("~/.ssh/config"),
                gitConfigPath: ConfigStore.expand("~/.gitconfig")
            )
            await refresh()
        } catch {
            // Refresh anyway to show current state
            await refresh()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: KC.space20) {
            Button {
                onOpenAbout()
            } label: {
                Image(systemName: "info.circle")
            }
            .help("About KeyChord")

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .keyboardShortcut("q")
            .help("Quit KeyChord")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.horizontal, KC.rowHPadding)
        .padding(.vertical, KC.space10)
    }

    // MARK: - Load + probe

    private func refresh() async {
        await reload()
        await probeAll()
        await runDoctor()
    }

    private func resolveRepo(at path: String) async {
        let snapshot = model
        let result = await CurrentRepoResolver.resolve(path: path, model: snapshot)
        switch result {
        case .success(let r):
            resolvedRepo = r
            repoResolveError = nil
            if let alias = r.sshAlias {
                appState.accountsStore.touchLastUsed(sshAlias: alias)
            }
        case .failure(let err):
            resolvedRepo = nil
            switch err {
            case .notARepo:
                repoResolveError = "\(path.abbreviatedHomePath()) is not a git repository"
            default:
                repoResolveError = String(describing: err)
            }
        }
    }

    private func runDoctor() async {
        let accountAliases = Set(appState.accountsStore.accounts.map(\.sshAlias))
        var scoped = model
        scoped.sshHosts = scoped.sshHosts.filter { accountAliases.contains($0.alias) }
        let probes = probeStates
        diagnoses = await Doctor.runAgainstCurrentSystem(
            model: scoped,
            probeStates: probes
        )
        appState.highestSeverity = diagnoses.map(\.severity).max()
    }

    private func reload() async {
        isLoading = true
        loadError = nil
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try ConfigStore.loadFromDefaultLocations()
            }.value
            model = loaded
        } catch {
            loadError = String(describing: error)
        }
        isLoading = false
    }

    private func probeAll() async {
        guard !isProbing else { return }
        isProbing = true
        defer { isProbing = false }

        let accountAliases = Set(appState.accountsStore.accounts.map(\.sshAlias))
        let aliases = accountAliases.filter { !$0.isEmpty }
        for alias in aliases {
            probeStates[alias] = .probing
        }

        await withTaskGroup(of: (String, HostProbeState).self) { group in
            for alias in aliases {
                group.addTask {
                    let result = await Prober.probeAlias(alias)
                    return (alias, result)
                }
            }
            for await (alias, result) in group {
                probeStates[alias] = result
            }
        }
    }
}

#Preview {
    MenuBarContent(appState: AppState())
}
