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
    @State private var detailAccount: BackupAccountPreview?

    private let cardRadius: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: KC.space10) {
                if entry.isReadable {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(alignment: .center, spacing: KC.space10) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .frame(width: 14, height: 14)

                            headerTextColumn

                            Spacer(minLength: KC.space8)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Text(isExpanded ? "Hide backup contents" : "Show backup contents")
                    )
                } else {
                    HStack(alignment: .center, spacing: KC.space10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)

                        headerTextColumn

                        Spacer(minLength: KC.space8)
                    }
                }

                HStack(spacing: KC.space10) {
                    Button(action: onRestore) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Restore")
                    .accessibilityLabel(Text("Restore"))
                    .disabled(isBusy)

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Delete")
                    .accessibilityLabel(Text("Delete"))
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
        .sheet(item: $detailAccount) { account in
            BackupAccountDetailSheet(account: account)
        }
    }

    private var headerTextColumn: some View {
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
                    Button {
                        detailAccount = account
                    } label: {
                        BackupAccountPreviewRow(account: account)
                    }
                    .buttonStyle(.plain)
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

// MARK: - Compact row (tappable)

private struct BackupAccountPreviewRow: View {
    let account: BackupAccountPreview

    var body: some View {
        HStack(alignment: .center, spacing: KC.space8) {
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

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Show snapshot account details"))
    }

    private var displayLabel: String {
        account.label.isEmpty ? String(localized: "(unnamed)") : account.label
    }

    private var detailLine: String {
        let alias = account.sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = account.gitUserEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return [alias, email].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Snapshot detail sheet

private struct BackupAccountDetailSheet: View {
    let account: BackupAccountPreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    detailRow("Label", displayLabel)
                    detailRow("Git name", blankable(account.gitUserName))
                    detailRow("Git email", blankable(account.gitUserEmail))
                } header: {
                    Text("Identity")
                }

                Section {
                    detailRow("Provider", account.provider.localizedLabel)
                    detailRow("Alias", blankable(account.sshAlias))
                    detailRow("Port", account.sshPort.displayName)
                    detailRow("Private key", keyPathDisplay)
                } header: {
                    Text("SSH")
                }

                Section {
                    detailRow("Scope", scopeDisplay)
                } header: {
                    Text("Scope")
                }

                Section {
                    if account.urlRewrites.isEmpty {
                        Text("No URL rewrites")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(account.urlRewrites.enumerated()), id: \.offset) { _, rule in
                            Text(verbatim: "\(rule.from) → \(rule.to)")
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } header: {
                    Text("URL Rewrites")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, KC.space20)
            .padding(.vertical, KC.space12)
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var displayLabel: String {
        account.label.isEmpty ? String(localized: "(unnamed)") : account.label
    }

    private var keyPathDisplay: String {
        let path = account.keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "—" }
        return path.abbreviatedHomePath()
    }

    private var scopeDisplay: String {
        switch account.scope {
        case .global:
            return String(localized: "Global")
        case .gitdir(let path):
            return String(localized: "scope: gitdir:\(path.abbreviatedHomePath())")
        }
    }

    private func blankable(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func detailRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(title) {
            Text(verbatim: value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}

private extension Account.Provider {
    var localizedLabel: String {
        switch self {
        case .github: return String(localized: "GitHub")
        case .gitlab: return String(localized: "GitLab")
        case .gitea: return String(localized: "Gitea")
        case .custom: return String(localized: "Custom")
        }
    }
}
