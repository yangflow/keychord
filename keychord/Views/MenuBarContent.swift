import SwiftUI
import AppKit

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: KC.popoverWidth, height: KC.popoverHeight)
        .task { await refresh() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
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

    // MARK: - Load + probe

    private func refresh() async {
        await reload()
        await probeAll()
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

    private func probeAll() async {
        let aliases = appState.accountsStore.accounts
            .map(\.sshAlias)
            .filter { !$0.isEmpty }
        for alias in aliases { probeStates[alias] = .probing }

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

    private func runDoctor() async {
        let accountAliases = Set(appState.accountsStore.accounts.map(\.sshAlias))
        var scoped = model
        scoped.sshHosts = scoped.sshHosts.filter { accountAliases.contains($0.alias) }
        diagnoses = await Doctor.runAgainstCurrentSystem(
            model: scoped,
            probeStates: probeStates
        )
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
        await refresh()
    }
}
