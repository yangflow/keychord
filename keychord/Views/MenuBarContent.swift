import SwiftUI
import UniformTypeIdentifiers

struct MenuBarContent: View {
    @ObservedObject var appState: AppState
    var onOpenAccountsWindow: () -> Void = {}
    var onOpenAccount: (UUID) -> Void = { _ in }
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
        onOpenAbout: @escaping () -> Void = {}
    ) {
        self.appState = appState
        self.onOpenAccountsWindow = onOpenAccountsWindow
        self.onOpenAccount = onOpenAccount
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
        if model.sshHosts.isEmpty
            && model.gitIdentities.isEmpty
            && model.insteadOfRules.isEmpty
            && model.includeIfRules.isEmpty
            && appState.accountsStore.accounts.isEmpty {
            Text("No config found.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, KC.rowHPadding)
                .padding(.vertical, KC.space12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
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

                // Accounts list
                accountsSection
            }
            .padding(.bottom, KC.space8)
        }
    }

    @ViewBuilder
    private var accountsSection: some View {
        let records = appState.accountsStore.accounts
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(accountsSectionTitle(records).uppercased())
                    .font(KC.sectionLabel)
                    .kerning(0.8)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    onOpenAccountsWindow()
                } label: {
                    Text("Manage")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, KC.rowHPadding)
            .padding(.top, KC.sectionHeaderTop)
            .padding(.bottom, KC.sectionHeaderBottom)

            KCCard {
                if records.isEmpty {
                    Text("No accounts yet. Click Manage to import or add one.")
                        .font(KC.rowCaption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, KC.rowHPadding)
                        .padding(.vertical, KC.space8)
                } else {
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
                            if idx < records.count - 1 {
                                Divider()
                                    .padding(.leading, KC.rowHPadding + 18)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, KC.space10)
        }
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
        await detectCurrentRepo()
    }

    private func detectCurrentRepo() async {
        if let path = await FinderContext.frontmostDirectory() {
            await resolveRepo(at: path)
        } else {
            resolvedRepo = nil
            repoResolveError = nil
        }
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
        let snapshot = model
        let probes = probeStates
        diagnoses = await Doctor.runAgainstCurrentSystem(
            model: snapshot,
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

        let hosts = model.sshHosts
        for host in hosts {
            probeStates[host.alias] = .probing
        }

        await withTaskGroup(of: (String, HostProbeState).self) { group in
            for host in hosts {
                let alias = host.alias
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
