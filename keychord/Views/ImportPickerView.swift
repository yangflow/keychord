import SwiftUI

/// Picker for accounts detected in existing SSH/git config.
/// `embedded` drops sheet chrome (Cancel, section headers) for the Settings window.
struct ImportPickerView: View {
    let candidates: [Account]
    let existingAliases: Set<String>
    let onImport: ([Account]) -> Void
    var onDismiss: (() -> Void)? = nil
    var embedded: Bool = false

    @State private var selected: Set<UUID>

    init(
        candidates: [Account],
        existingAliases: Set<String>,
        onImport: @escaping ([Account]) -> Void,
        onDismiss: (() -> Void)? = nil,
        embedded: Bool = false
    ) {
        self.candidates = candidates
        self.existingAliases = existingAliases
        self.onImport = onImport
        self.onDismiss = onDismiss
        self.embedded = embedded
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
                if embedded {
                    Section {
                        candidateList
                    }
                } else {
                    Section {
                        candidateList
                    } header: {
                        Text("Detected Accounts")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if let onDismiss, !embedded {
                    Button("Cancel", action: onDismiss)
                        .keyboardShortcut(.cancelAction)
                }
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
        // Recreate selection when the candidate set changes (e.g. re-scan).
        .id(candidates.map(\.id.uuidString).joined(separator: ","))
    }

    @ViewBuilder
    private var candidateList: some View {
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
                    Text(verbatim: account.label.isEmpty ? account.sshAlias : account.label)
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
                        Text(verbatim: account.sshAlias)
                            .font(KC.rowCaptionMono)
                            .foregroundStyle(.secondary)
                    }
                    if !account.gitUserEmail.isEmpty {
                        Text(verbatim: account.gitUserEmail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}
