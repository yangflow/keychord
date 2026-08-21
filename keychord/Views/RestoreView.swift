import SwiftUI

struct RestoreView: View {
    let accountsStore: AccountsStore
    let backups: BackupService
    let onDismiss: () -> Void

    @State private var entries: [BackupListEntry] = []
    @State private var loadError: String?
    @State private var statusMessage: String?
    @State private var isBusy = false
    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if let statusMessage {
                        Label {
                            Text(verbatim: statusMessage)
                        } icon: {
                            Image(systemName: "checkmark.circle")
                        }
                        .font(.caption)
                        .foregroundStyle(.green)
                    }
                    if let loadError {
                        Label {
                            Text(verbatim: loadError)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }

                    if entries.isEmpty
                        && loadError == nil
                        && statusMessage == nil
                        && hasLoaded {
                        Text("No backups yet — edits will appear here once you save changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(entries) { entry in
                        BackupRestoreRow(entry: entry, isBusy: isBusy) {
                            Task { await restore(entry.record) }
                        }
                    }
                } header: {
                    Text("Backups")
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
        .frame(minWidth: 440, minHeight: 320)
        .onAppear { reload() }
    }

    // MARK: - Actions

    private func reload() {
        let path = accountsStore.storageURL.path
        loadError = nil
        do {
            entries = try backups.listEntries(for: path)
        } catch {
            loadError = String(localized: "Failed to list backups: \(String(describing: error))")
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
            statusMessage = String(localized: "Restored to \(stamp)")
            reload()
        } catch {
            loadError = String(localized: "Restore failed: \(String(describing: error))")
        }
    }
}

// MARK: - Row

private struct BackupRestoreRow: View {
    let entry: BackupListEntry
    let isBusy: Bool
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.timestamp, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                        .font(.caption.weight(.medium))
                    Text(verbatim: "·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(
                        entry.timestamp,
                        format: .dateTime.year().month().day().hour().minute().second()
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }

                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Button("Restore", action: onRestore)
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(isBusy)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var summaryLine: String {
        var parts: [String] = []

        if let count = entry.accountCount {
            if count == 0 {
                parts.append(String(localized: "0 accounts"))
            } else if count == 1 {
                parts.append(String(localized: "1 account"))
            } else {
                parts.append(String(localized: "\(count) accounts"))
            }

            let labelText = entry.labels
                .map { $0.isEmpty ? String(localized: "(unnamed)") : $0 }
                .joined(separator: ", ")
            if !labelText.isEmpty {
                parts.append(labelText)
            }
        } else {
            parts.append(String(localized: "Unreadable snapshot"))
        }

        if let bytes = entry.byteCount {
            parts.append(bytes.formatted(.byteCount(style: .file)))
        }

        return parts.joined(separator: " · ")
    }
}
