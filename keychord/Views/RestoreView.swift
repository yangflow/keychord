import SwiftUI

struct RestoreView: View {
    let sourcePaths: [String]
    let backups: BackupService
    let onDismiss: () -> Void

    @State private var groups: [String: [BackupRecord]] = [:]
    @State private var loadError: String?
    @State private var statusMessage: String?
    @State private var isBusy = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 400, minHeight: 300)
        .task { await reload() }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, KC.rowHPadding)
                        .padding(.vertical, KC.space8)
                }
                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, KC.rowHPadding)
                        .padding(.vertical, KC.space8)
                }

                if groups.values.allSatisfy(\.isEmpty)
                    && loadError == nil
                    && statusMessage == nil {
                    Text("No backups yet — edits will appear here once you save changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, KC.rowHPadding)
                        .padding(.vertical, KC.space12)
                }

                ForEach(sourcePaths, id: \.self) { path in
                    sourceSection(path: path)
                }
            }
            .padding(.bottom, KC.space6)
        }
    }

    @ViewBuilder
    private func sourceSection(path: String) -> some View {
        let records = groups[path] ?? []
        let display = URL(fileURLWithPath: path).lastPathComponent
        KCSectionHeader(title: display)

        if records.isEmpty {
            Text("no backups")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, KC.rowHPadding)
                .padding(.vertical, 4)
        } else {
            ForEach(records) { record in
                backupRow(record)
            }
        }
    }

    private func backupRow(_ record: BackupRecord) -> some View {
        KCRowContainer {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(Self.formatted(record.timestamp))
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

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isBusy {
                ProgressView().controlSize(.small)
            }
            Text("Restoring auto-backs-up the current file.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, KC.space20)
        .padding(.vertical, KC.space12)
    }

    // MARK: - Actions

    private func reload() async {
        let svc = backups
        let paths = sourcePaths
        loadError = nil
        do {
            let loaded = try await Task.detached {
                var g: [String: [BackupRecord]] = [:]
                for p in paths {
                    g[p] = try svc.list(for: p)
                }
                return g
            }.value
            groups = loaded
        } catch {
            loadError = "Failed to list backups: \(error)"
        }
    }

    private func restore(_ record: BackupRecord) async {
        let svc = backups
        isBusy = true
        defer { isBusy = false }
        do {
            try await Task.detached {
                try svc.safeRestore(record)
            }.value
            let name = URL(fileURLWithPath: record.originalPath).lastPathComponent
            statusMessage = "Restored \(name) → \(Self.formatted(record.timestamp))"
            await reload()
        } catch {
            loadError = "Restore failed: \(error)"
        }
    }

    // MARK: - Formatting

    private static func formatted(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .medium
        return fmt.string(from: date)
    }
}
