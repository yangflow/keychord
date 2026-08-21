import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Menu bar icon (label for MenuBarExtra)

struct MenuBarIconLabel: View {
    let appState: AppState

    var body: some View {
        Image(nsImage: icon)
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

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: KC.popoverWidth, height: KC.popoverHeight)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .task { await refresh() }
        .onDisappear {
            // NSOpenPanel tears down the MenuBarExtra window; keep the match
            // so Choose Folder can reopen with the new result.
            guard !appState.isChoosingFolder else { return }
            appState.clearAccountMatch()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    currentRepoSection

                    if !appState.accountsStore.accounts.isEmpty, !diagnoses.isEmpty {
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
                    accountsSection
                }
                .padding(.bottom, KC.space8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var currentRepoSection: some View {
        switch appState.accountMatch {
        case .matched(let account, let repoRoot):
            CurrentRepoMatchedRow(
                account: account,
                repoRoot: repoRoot,
                probe: probeStates[account.sshAlias] ?? .idle,
                onClear: { appState.clearAccountMatch() }
            )
        case .notARepo, .noMatchingGitdir, .conflictingGlobals:
            if let reason = appState.accountMatch?.unresolvedReason {
                CurrentRepoUnresolvedRow(
                    reason: reason,
                    onChooseFolder: chooseFolder,
                    onClear: { appState.clearAccountMatch() }
                )
            }
        case nil:
            CurrentRepoDropZone(isTargeted: isDropTargeted, onChooseFolder: chooseFolder)
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
        return VStack(alignment: .leading, spacing: 0) {
            Text("Accounts")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(records) { record in
                    Button {
                        openAccounts(selecting: record.id)
                    } label: {
                        AccountRow(
                            record: record,
                            probe: probeStates[record.sshAlias] ?? .idle
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 32)
                }
                AddAccountRow(onTap: { openAccounts(addNew: true) })
            }
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

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose a folder or git working copy to resolve which account applies.")

        appState.isChoosingFolder = true
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            // Panel dismissed the popover; Cancel means no new match to show.
            appState.isChoosingFolder = false
            appState.clearAccountMatch()
            return
        }

        Task {
            await appState.resolveCurrentRepo(at: url.path)
            // NSOpenPanel dismisses the MenuBarExtra window; reopen like icon drop.
            try? await Task.sleep(for: .milliseconds(50))
            StatusItemDropTargetController.shared.openPopoverShowingMatch()
            appState.isChoosingFolder = false
        }
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
            probeStates: probeStates
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
            gitConfigPath: ConfigStore.expand("~/.gitconfig")
        )
        await refresh(forceProbe: true)
    }
}
