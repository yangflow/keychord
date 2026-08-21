import SwiftUI

/// Lightweight settings sheet for maintenance actions that are not
/// account-specific. Today: strip Include markers while keeping
/// accounts.json and keys.
struct SettingsView: View {
    let onDismiss: () -> Void

    @State private var confirmRemoveIncludes = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("Removes keychord’s Include markers from ~/.ssh/config and ~/.gitconfig. Your accounts.json and SSH keys stay in place.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Remove Include (keep accounts.json)", role: .destructive) {
                        confirmRemoveIncludes = true
                    }
                } header: {
                    Text("Includes")
                }

                if let statusMessage {
                    Section {
                        Text(verbatim: statusMessage)
                            .font(.caption)
                            .foregroundStyle(statusIsError ? Color.red : Color.green)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Done") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, KC.space20)
            .padding(.vertical, KC.space12)
        }
        .frame(minWidth: 360, minHeight: 220)
        .confirmationDialog(
            "Remove Include blocks?",
            isPresented: $confirmRemoveIncludes,
            titleVisibility: .visible
        ) {
            Button("Remove Include", role: .destructive) {
                removeIncludes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only strips the # --- keychord managed --- blocks. accounts.json, managed files, and private keys are not deleted.")
        }
    }

    private func removeIncludes() {
        let paths = AccountProjector.ManagedPaths.default
        do {
            try IncludeInstaller.uninstallUserIncludes(
                sshConfigPath: paths.userSSHConfig,
                gitConfigPath: paths.userGitConfig
            )
            statusIsError = false
            statusMessage = String(localized: "Include markers removed")
        } catch {
            statusIsError = true
            statusMessage = String(localized: "Remove failed: \(String(describing: error))")
        }
    }
}
