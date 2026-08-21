import SwiftUI

/// Sheet that lets the user enable/disable iCloud sync and see status.
///
/// When the iCloud entitlement is unavailable (unsigned / no-iCloud builds),
/// the toggle is disabled and never shown as on or synced.
struct CloudSyncView: View {
    @Bindable var cloudSync: CloudSyncService
    let onDismiss: () -> Void

    private var presentation: CloudSyncPresentation {
        cloudSync.presentation
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Enable iCloud Sync", isOn: enabledBinding)
                        .toggleStyle(.switch)
                        .disabled(presentation.isToggleDisabled)
                        .onChange(of: cloudSync.isEnabled) { _, enabled in
                            guard presentation.isCapabilityAvailable else { return }
                            if enabled {
                                cloudSync.activate()
                            } else {
                                cloudSync.deactivate()
                            }
                        }

                    if presentation.showsRequiresSignedBuildMessage {
                        Text("Requires a signed build with the iCloud entitlement.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("iCloud Sync")
                }

                Section {
                    HStack(spacing: KC.space8) {
                        statusDot
                        statusText
                    }
                } header: {
                    Text("Status")
                }

                Section {
                    Text("Only the account list is synced — SSH keys stay local on each machine.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if presentation.showsSyncNow {
                    Button("Sync Now") {
                        cloudSync.pull()
                    }
                }
                Spacer()
                Button("Done") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, KC.space20)
            .padding(.vertical, KC.space12)
        }
        .frame(minWidth: 360, minHeight: 260)
    }

    /// Binding that never presents an "on" state when capability is missing.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { presentation.showsToggleAsOn },
            set: { newValue in
                guard presentation.isCapabilityAvailable else { return }
                cloudSync.isEnabled = newValue
            }
        )
    }

    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(width: 6, height: 6)
    }

    private var statusDotColor: Color {
        guard presentation.isCapabilityAvailable else { return .secondary }
        switch cloudSync.state {
        case .idle:    .secondary
        case .syncing: .orange
        case .synced:  .green
        case .failed:  .red
        }
    }

    private var statusText: Text {
        if !presentation.isCapabilityAvailable {
            return Text("Unavailable")
        }
        switch cloudSync.state {
        case .idle:
            return Text("Not synced")
        case .syncing:
            return Text("Syncing…")
        case .synced(let date):
            return Text("Last synced \(date, style: .relative) ago")
        case .failed(let msg):
            return Text("Error: \(msg)")
        }
    }
}
