import SwiftUI

/// Lightweight settings sheet for maintenance actions that are not
/// account-specific: language, Open at Login, and strip Include markers
/// while keeping accounts.json and keys.
struct SettingsView: View {
    let onDismiss: () -> Void

    @Environment(AppLanguageStore.self) private var languageStore
    @State private var loginItem: LoginItemController
    @State private var confirmRemoveIncludes = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    init(
        onDismiss: @escaping () -> Void,
        loginItemService: LoginItemManaging = LoginItemService()
    ) {
        self.onDismiss = onDismiss
        self._loginItem = State(initialValue: LoginItemController(service: loginItemService))
    }

    var body: some View {
        @Bindable var languageStore = languageStore
        return VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Language", selection: $languageStore.preference) {
                        Text("Follow System").tag(AppLanguagePreference.system)
                        Text(verbatim: "English").tag(AppLanguagePreference.english)
                        Text(verbatim: "简体中文").tag(AppLanguagePreference.simplifiedChinese)
                    }

                    Text("Overrides the system language for KeyChord only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if languageStore.pendingRelaunch {
                        Text("Relaunch KeyChord to apply the language everywhere.")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Button("Relaunch") {
                            AppLanguageStore.relaunch()
                        }
                    }
                } header: {
                    Text("Language")
                }

                Section {
                    Toggle(
                        "Open at Login",
                        isOn: Binding(
                            get: { loginItem.isEnabled },
                            set: { loginItem.setEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)

                    if let message = loginItem.lastErrorMessage {
                        Text(verbatim: message)
                            .font(.caption)
                            .foregroundStyle(Color.red)
                    } else if loginItem.requiresApproval {
                        Text("Open at Login needs approval in System Settings → General → Login Items.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Text("Launch keychord in the menu bar when you log in to this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Startup")
                }

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
        .frame(minWidth: 360, minHeight: 360)
        .onAppear {
            loginItem.refresh()
        }
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
