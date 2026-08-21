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
                    Text("No backups yet — a snapshot is taken when you add a new account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(entries) { entry in
                    BackupRestoreRow(entry: entry, isBusy: isBusy) {
                        Task { await restore(entry.record) }
                    }
                }

                if isBusy {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
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

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                disclosureControl
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        entry.timestamp,
                        format: .dateTime.year().month().day().hour().minute().second()
                    )
                    .font(.caption.weight(.medium))
                    .monospacedDigit()

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

            if isExpanded {
                expandedContent
                    .padding(.leading, 22)
            }
        }
        .padding(.vertical, 2)
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
                    .font(.caption.weight(.semibold))
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
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(entry.accounts.enumerated()), id: \.element.id) { index, account in
                    BackupAccountPreviewBlock(account: account)
                    if index < entry.accounts.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 4)
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

// MARK: - Account preview

private struct BackupAccountPreviewBlock: View {
    let account: BackupAccountPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            if !identityLine.isEmpty {
                Text(verbatim: identityLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(verbatim: sshLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !account.keyPath.isEmpty {
                Text(verbatim: account.keyPath.abbreviatedHomePath())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(scopeLine)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(rewriteLine)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var displayLabel: String {
        account.label.isEmpty ? String(localized: "(unnamed)") : account.label
    }

    private var identityLine: String {
        [account.gitUserName, account.gitUserEmail]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var sshLine: String {
        var parts: [String] = []
        let alias = account.sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        if !alias.isEmpty {
            parts.append(alias)
        }
        parts.append(providerLabel)
        parts.append(String(localized: "Port \(account.sshPort.displayName)"))
        return parts.joined(separator: " · ")
    }

    private var providerLabel: String {
        switch account.provider {
        case .github: return String(localized: "GitHub")
        case .gitlab: return String(localized: "GitLab")
        case .gitea: return String(localized: "Gitea")
        case .custom: return String(localized: "Custom")
        }
    }

    private var scopeLine: String {
        switch account.scope {
        case .global:
            return String(localized: "Global")
        case .gitdir(let path):
            let display = path.abbreviatedHomePath()
            return String(localized: "scope: gitdir:\(display)")
        }
    }

    private var rewriteLine: String {
        let rewrites = account.urlRewrites
        if rewrites.isEmpty {
            return String(localized: "No URL rewrites")
        }
        if rewrites.count == 1, let only = rewrites.first {
            return "\(only.from) → \(only.to)"
        }
        if let first = rewrites.first {
            let countText = String(localized: "\(rewrites.count) URL rewrites")
            return "\(countText) · \(first.from) → \(first.to)"
        }
        return String(localized: "\(rewrites.count) URL rewrites")
    }
}
