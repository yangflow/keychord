import SwiftUI

struct RestoreView: View {
    let accountsStore: AccountsStore
    let backups: BackupService
    let onDismiss: () -> Void

    @State private var records: [BackupRecord] = []
    @State private var loadError: String?
    @State private var statusMessage: String?
    @State private var isBusy = false
    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Backups") {
                    if let statusMessage {
                        Label(statusMessage, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if records.isEmpty
                        && loadError == nil
                        && statusMessage == nil
                        && hasLoaded {
                        Text("No backups yet — edits will appear here once you save changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(records) { record in
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text(record.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                                .font(.caption)
                                .monospaced()
                            Spacer()
                            Button("Restore") {
                                Task { await restore(record) }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .disabled(isBusy)
                        }
                    }
                }

                Section {
                    Text("Restoring rolls back all accounts to that point in time.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Done", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, KC.space20)
            .padding(.vertical, KC.space12)
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear { reload() }
    }

    // MARK: - Actions

    private func reload() {
        let path = accountsStore.storageURL.path
        loadError = nil
        do {
            records = try backups.list(for: path)
        } catch {
            loadError = "Failed to list backups: \(error)"
        }
        hasLoaded = true
    }

    private func restore(_ record: BackupRecord) async {
        let svc = backups
        isBusy = true
        defer { isBusy = false }
        do {
            try await Task.detached {
                try svc.safeRestore(record)
            }.value
            try accountsStore.load()
            try AccountProjector.regenerate(
                accounts: accountsStore.accounts
            )
            let stamp = record.timestamp.formatted(date: .abbreviated, time: .standard)
            statusMessage = "Restored to \(stamp)"
            reload()
        } catch {
            loadError = "Restore failed: \(error)"
        }
    }
}
