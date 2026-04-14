import SwiftUI

/// Sheet that shows detected accounts from existing SSH/git config and
/// lets the user pick which ones to import. Follows the
/// Form + Divider + Footer layout used by KeygenView / RestoreView.
struct ImportPickerView: View {
    let candidates: [Account]
    let existingAliases: Set<String>
    let onImport: ([Account]) -> Void
    let onDismiss: () -> Void

    @State private var selected: Set<UUID>

    init(
        candidates: [Account],
        existingAliases: Set<String>,
        onImport: @escaping ([Account]) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.candidates = candidates
        self.existingAliases = existingAliases
        self.onImport = onImport
        self.onDismiss = onDismiss
        // Pre-select candidates that don't duplicate an existing alias.
        let initial = Set(
            candidates
                .filter { !existingAliases.contains($0.sshAlias) }
                .map(\.id)
        )
        _selected = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Detected Accounts") {
                    if candidates.isEmpty {
                        Text("No accounts found in your existing SSH / gitconfig.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates) { account in
                            candidateRow(account)
                        }
                    }
                }

                if !candidates.isEmpty {
                    Section {
                        Text("Already-existing aliases are unchecked by default. Importing a duplicate alias will be skipped.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import ^[\(selected.count) Account](inflect: true)") {
                    let chosen = candidates.filter { selected.contains($0.id) }
                    onImport(chosen)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
            .padding(.horizontal, KC.space20)
            .padding(.vertical, KC.space12)
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    // MARK: - Subviews

    private func selectionBinding(for account: Account) -> Binding<Bool> {
        Binding(
            get: { selected.contains(account.id) },
            set: { isOn in
                if isOn { selected.insert(account.id) }
                else { selected.remove(account.id) }
            }
        )
    }

    private func candidateRow(_ account: Account) -> some View {
        let isDuplicate = existingAliases.contains(account.sshAlias)

        return Toggle(isOn: selectionBinding(for: account)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.label.isEmpty ? account.sshAlias : account.label)
                        .font(KC.rowTitle)
                        .lineLimit(1)
                    if isDuplicate {
                        Text("exists")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 8) {
                    if !account.sshAlias.isEmpty {
                        Text(account.sshAlias)
                            .font(KC.rowCaptionMono)
                            .foregroundStyle(.secondary)
                    }
                    if !account.gitUserEmail.isEmpty {
                        Text(account.gitUserEmail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}
