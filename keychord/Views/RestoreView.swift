import SwiftUI

struct RestoreView: View {
    let accountsStore: AccountsStore
    let backups: BackupService

    @State private var entries: [BackupListEntry] = []
    @State private var loadError: String?
    @State private var statusMessage: String?
    @State private var isBusy = false
    @State private var hasLoaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KC.space10) {
                statusBlock

                if entries.isEmpty
                    && loadError == nil
                    && statusMessage == nil
                    && hasLoaded
                    && !isBusy {
                    Text("No backups yet — a snapshot is taken when you add a new account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                }

                ForEach(entries) { entry in
                    BackupRestoreCard(
                        entry: entry,
                        isBusy: isBusy,
                        onRestore: { Task { await restore(entry.record) } },
                        onDelete: { Task { await delete(entry.record) } }
                    )
                }

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, KC.space4)
                }
            }
            .padding(.horizontal, KC.space16)
            .padding(.vertical, KC.space14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { reload() }
    }

    @ViewBuilder
    private var statusBlock: some View {
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

    private func delete(_ record: BackupRecord) async {
        let svc = backups
        isBusy = true
        defer { isBusy = false }
        do {
            try await Task.detached {
                try svc.delete(record)
            }.value
            statusMessage = nil
            loadError = nil
            reload()
        } catch {
            loadError = String(localized: "Delete failed: \(String(describing: error))")
        }
    }
}

// MARK: - Card row

private struct BackupRestoreCard: View {
    let entry: BackupListEntry
    let isBusy: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false

    private let cardRadius: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: KC.space10) {
                disclosureControl

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        entry.timestamp,
                        format: .dateTime.year().month().day().hour().minute().second()
                    )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()

                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: KC.space8)

                HStack(spacing: KC.space10) {
                    Button("Restore", action: onRestore)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .disabled(isBusy)

                    Button("Delete", role: .destructive, action: onDelete)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .disabled(isBusy)
                }
            }

            if isExpanded {
                Divider()
                    .padding(.vertical, KC.space10)

                expandedContent
            }
        }
        .padding(KC.space14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    @ViewBuilder
    private var disclosureControl: some View {
        if entry.isReadable {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(
                Text(isExpanded ? "Hide backup contents" : "Show backup contents")
            )
        } else {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if entry.accounts.isEmpty {
            Text("No accounts in this snapshot")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: KC.space8) {
                ForEach(entry.accounts) { account in
                    BackupAccountPreviewBlock(account: account)
                }
            }
        }
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

// MARK: - Account preview (compact)

private struct BackupAccountPreviewBlock: View {
    let account: BackupAccountPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if !detailLine.isEmpty {
                Text(verbatim: detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var displayLabel: String {
        account.label.isEmpty ? String(localized: "(unnamed)") : account.label
    }

    /// `alias · email` (skip empty parts).
    private var detailLine: String {
        let alias = account.sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = account.gitUserEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return [alias, email].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
