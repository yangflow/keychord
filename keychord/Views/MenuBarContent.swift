import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Menu bar icon (label for MenuBarExtra)

struct MenuBarIconLabel: View {
    let appState: AppState

    var body: some View {
        Image(nsImage: icon)
            // Tooltip is the only place a match shows without opening the
            // popover; the glyph itself stays severity-driven.
            .onChange(of: tooltip, initial: true) { _, text in
                MenuBarTooltip.apply(text)
            }
    }

    private var tooltip: String {
        MenuBarTooltip.text(for: appState.accountMatch)
    }

    private var icon: NSImage {
        let name: String
        switch appState.highestSeverity {
        case .error:   name = "exclamationmark.octagon.fill"
        case .warning: name = "exclamationmark.triangle.fill"
        case .info, .none: name = "key.horizontal.fill"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "keychord")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }
}

// MARK: - Popover root

struct MenuBarPopoverView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    @State private var model = ConfigModel()
    @State private var probeStates: [String: HostProbeState] = [:]
    @State private var diagnoses: [Diagnosis] = []
    @State private var isLoading = true
    @State private var isFixing = false
    @State private var isDoctorExpanded = false
    @State private var expandedAccountID: UUID?
    @State private var reprobingAliases: Set<String> = []
    @State private var isBinding = false
    @State private var bindError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: KC.space8) {
                Text("KeyChord")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Button {
                    openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .accessibilityLabel(Text("Settings"))
            }
            .padding(.horizontal, KC.rowHPadding)
            .padding(.top, KC.space8)
            .padding(.bottom, KC.space6)

            content
            Divider()
            footer
        }
        .frame(width: KC.popoverWidth, height: KC.popoverHeight)
        // Secondary convenience — primary path is drop on the menu bar icon.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .task { await refresh() }
        .onDisappear {
            guard !appState.suppressAccountMatchClear else { return }
            appState.clearAccountMatch()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else if appState.accountsStore.accounts.isEmpty {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    currentRepoSection
                    AccountsEmptyStateCard(
                        onImport: { openSettingsWindow(pane: .importAccounts) },
                        onAddAccount: { openAccounts(addNew: true) }
                    )
                }
                .padding(.bottom, KC.space8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    currentRepoSection
                    accountsSection

                    // Illustration only: drops land on the status-item icon.
                    if appState.accountMatch == nil {
                        DropFolderHintCard()
                    }

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
                                    onFix: { id in Task { await applyFix(id) } }
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, KC.space8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var currentRepoSection: some View {
        switch appState.accountMatch {
        case .matched(let account, let repoRoot, let originURL):
            CurrentRepoMatchedRow(
                account: account,
                repoRoot: repoRoot,
                probe: probeStates[account.sshAlias] ?? .idle,
                originURL: originURL,
                audit: appState.identityAudit,
                onClear: { appState.clearAccountMatch() }
            )
        case .notARepo, .noMatchingGitdir, .conflictingGlobals:
            if let reason = appState.accountMatch?.unresolvedReason {
                CurrentRepoUnresolvedRow(
                    reason: reason,
                    bindPath: appState.accountMatch?.bindableRepoRoot,
                    bindTargets: appState.accountsStore.accounts,
                    isBinding: isBinding,
                    bindError: bindError,
                    onBind: { account in Task { await bind(to: account) } },
                    onClear: { appState.clearAccountMatch() }
                )
            }
        case nil:
            EmptyView()
        }
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading config…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, KC.rowHPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Accounts section

    private var accountsSection: some View {
        let records = appState.accountsStore.accounts
        return VStack(spacing: 0) {
            ForEach(records) { record in
                AccountRow(
                    record: record,
                    probe: probeStates[record.sshAlias] ?? .idle,
                    isExpanded: expandedAccountID == record.id,
                    isReprobing: reprobingAliases.contains(record.sshAlias),
                    onOpenDetail: { openAccounts(selecting: record.id) },
                    onToggleExpanded: {
                        expandedAccountID = expandedAccountID == record.id ? nil : record.id
                    },
                    onReprobe: { Task { await reprobe(record.sshAlias) } }
                )

                Divider().padding(.leading, 32)
            }
            AddAccountRow(onTap: { openAccounts(addNew: true) })
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: KC.space20) {
            Button {
                openAboutWindow()
            } label: {
                Image(systemName: "info.circle")
            }
            .help("About KeyChord")

            Spacer()

            Button {
                Task { await refresh(forceProbe: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .accessibilityLabel(Text("Refresh"))

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

    // MARK: - Window helpers

    private func openAccounts(selecting id: UUID? = nil, addNew: Bool = false) {
        if let id { appState.pendingAccountSelection = id }
        if addNew { appState.pendingAddNew = true }
        let popover = NSApp.keyWindow
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "accounts")
        NSApp.activate(ignoringOtherApps: true)
        popover?.close()
    }

    private func openAboutWindow() {
        let popover = NSApp.keyWindow
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "about")
        NSApp.activate(ignoringOtherApps: true)
        popover?.close()
    }

    private func openSettingsWindow(pane: SettingsPane? = nil) {
        if let pane { appState.pendingSettingsPane = pane }
        let popover = NSApp.keyWindow
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
        popover?.close()
    }

    // MARK: - Bind a dropped folder

    private func bind(to account: Account) async {
        isBinding = true
        bindError = nil
        defer { isBinding = false }
        bindError = await appState.bindCurrentFolder(to: account)
        guard bindError == nil else { return }
        await probeAll()
        await runDoctor()
    }

    // MARK: - Manual per-alias re-probe

    /// Re-probes one alias immediately, ignoring the cache TTL, so returning
    /// from the forge's SSH settings page shows the new state right away.
    private func reprobe(_ alias: String) async {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        reprobingAliases.insert(trimmed)
        probeStates[trimmed] = .probing
        defer { reprobingAliases.remove(trimmed) }

        let state = await appState.probeCache.reprobe(trimmed) { target in
            await Prober.probeAlias(target)
        }
        probeStates[trimmed] = state
        await runDoctor()
    }

    // MARK: - Drop / choose folder / Finder

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let maybeURL = item as? URL {
                url = maybeURL
            } else {
                url = nil
            }
            guard let url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else {
                return
            }
            Task { @MainActor in
                await appState.resolveCurrentRepo(at: url.path)
            }
        }
        return true
    }

    // MARK: - Load + probe

    private func refresh(forceProbe: Bool = false) async {
        // Restore cached dots / severity inputs before the spinner clears so a
        // recreated popover does not flash idle → probing on every open.
        hydrateProbeStatesFromCache()
        await reload()
        await probeAll(force: forceProbe)
        await runDoctor()
    }

    private func reload() async {
        isLoading = true
        do {
            model = try await Task.detached(priority: .userInitiated) {
                try ConfigStore.loadFromDefaultLocations()
            }.value
        } catch {
            // Empty model on failure — the accounts list still works.
            model = ConfigModel()
        }
        isLoading = false
    }

    private func accountAliases() -> [String] {
        appState.accountsStore.accounts
            .map(\.sshAlias)
            .filter { !$0.isEmpty }
    }

    private func hydrateProbeStatesFromCache() {
        for (alias, state) in appState.probeCache.cachedStates(for: accountAliases()) {
            probeStates[alias] = state
        }
    }

    /// Probe only aliases that `ProbeCache.shouldProbe` allows. Cached
    /// successes keep their prior state (no `.probing` flash); the menu-bar
    /// icon keeps the previous `highestSeverity` until Doctor finishes on
    /// the merged map.
    private func probeAll(force: Bool = false) async {
        let aliases = accountAliases()
        let cache = appState.probeCache

        hydrateProbeStatesFromCache()

        let pending = aliases.filter { cache.shouldProbe($0, force: force) }
        for alias in pending {
            probeStates[alias] = .probing
        }

        let probed = await cache.probeAliases(aliases, force: force) { alias in
            await Prober.probeAlias(alias)
        }
        for (alias, state) in probed {
            probeStates[alias] = state
        }
    }

    private func runDoctor() async {
        let accountAliases = Set(appState.accountsStore.accounts.map(\.sshAlias))
        var scoped = model
        scoped.sshHosts = scoped.sshHosts.filter { accountAliases.contains($0.alias) }
        diagnoses = await Doctor.runAgainstCurrentSystem(
            model: scoped,
            probeStates: probeStates,
            identityAudit: appState.identityAudit
        )
        // Doctor runs only after probeAll merges cache + fresh results, so
        // severity updates in one step instead of key → warning mid-probe.
        appState.highestSeverity = diagnoses.map(\.severity).max()
    }

    private func applyFix(_ fixID: FixID) async {
        isFixing = true
        defer { isFixing = false }
        try? await Fixer.execute(
            fixID,
            sshConfigPath: ConfigStore.expand("~/.ssh/config"),
            gitConfigPath: ConfigStore.expand("~/.gitconfig"),
            accounts: appState.accountsStore.accounts
        )
        // Re-resolving first keeps the identity audit in step with a fix that
        // rewrote the managed gitconfig for the matched repository.
        if case .matched(_, let repoRoot, _) = appState.accountMatch {
            await appState.resolveCurrentRepo(at: repoRoot)
        }
        await refresh(forceProbe: true)
    }
}
