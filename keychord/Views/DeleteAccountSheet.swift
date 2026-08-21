import SwiftUI

/// Delete confirmation that names what survives: the private key file and the
/// directories the account was scoped to. Removing the key is opt-in and off by
/// default; keychord regenerates its managed files either way, but nothing on
/// disk outside `~/.config/keychord` is touched unless the box is checked.
struct DeleteAccountSheet: View {
    let account: Account
    let leftovers: KeyFileRemover.Leftovers
    let onCancel: () -> Void
    let onConfirm: (_ removePrivateKey: Bool) -> Void

    @State private var removePrivateKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: KC.space14) {
            VStack(alignment: .leading, spacing: KC.space6) {
                Text("Delete identity \(displayLabel)?")
                    .font(.headline)
                Text("This removes the identity from KeyChord. These are not deleted for you:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            leftoverList

            VStack(alignment: .leading, spacing: KC.space4) {
                Toggle(isOn: $removePrivateKey) {
                    Text("Also delete the private key")
                }
                .toggleStyle(.checkbox)
                .disabled(!leftovers.canRemoveKey)

                if let blocker = leftovers.keyRemovalBlocker {
                    Text(verbatim: blocker.localizedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Managed SSH and git config are regenerated. Folders on disk stay where they are.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    onConfirm(removePrivateKey && leftovers.canRemoveKey)
                } label: {
                    Text("Delete identity")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(KC.space20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var displayLabel: String {
        account.label.isEmpty ? String(localized: "(unnamed)") : account.label
    }

    @ViewBuilder
    private var leftoverList: some View {
        VStack(alignment: .leading, spacing: KC.space8) {
            leftoverRow(
                title: Text("Private key"),
                value: leftovers.privateKeyPath.isEmpty
                    ? "—"
                    : leftovers.privateKeyPath.abbreviatedHomePath()
            )
            if !leftovers.gitdirPaths.isEmpty {
                Divider()
                leftoverRow(
                    title: Text(verbatim: "gitdir"),
                    value: leftovers.gitdirPaths
                        .map { $0.abbreviatedHomePath() }
                        .joined(separator: " · ")
                )
            }
        }
        .padding(KC.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: KC.cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func leftoverRow(title: Text, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KC.space10) {
            title
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(verbatim: value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
