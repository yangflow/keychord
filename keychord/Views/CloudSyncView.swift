import SwiftUI

/// Sheet that lets the user enable/disable iCloud sync and see status.
struct CloudSyncView: View {
    @Bindable var cloudSync: CloudSyncService
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("iCloud Sync") {
                    Toggle("Enable iCloud Sync", isOn: $cloudSync.isEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: cloudSync.isEnabled) { _, enabled in
                            if enabled {
                                cloudSync.activate()
                            } else {
                                cloudSync.deactivate()
                            }
                        }
                }

                Section("Status") {
                    HStack(spacing: KC.space8) {
                        statusDot
                        statusText
                    }
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
                if cloudSync.isEnabled {
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

    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(width: 6, height: 6)
    }

    private var statusDotColor: Color {
        switch cloudSync.state {
        case .idle:    .secondary
        case .syncing: .orange
        case .synced:  .green
        case .failed:  .red
        }
    }

    private var statusText: Text {
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
