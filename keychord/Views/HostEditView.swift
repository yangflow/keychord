import SwiftUI

struct HostEditView: View {
    let host: SSHHost
    let sshConfigPath: String
    let onDismiss: () -> Void
    let onSaved: () -> Void

    @State private var hostName: String
    @State private var portText: String
    @State private var user: String
    @State private var identityFile: String
    @State private var hostKeyAlias: String
    @State private var identitiesOnly: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        host: SSHHost,
        sshConfigPath: String,
        onDismiss: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.host = host
        self.sshConfigPath = sshConfigPath
        self.onDismiss = onDismiss
        self.onSaved = onSaved

        _hostName = State(initialValue: host.hostName ?? "")
        _portText = State(initialValue: host.port.map(String.init) ?? "")
        _user = State(initialValue: host.user ?? "")
        _identityFile = State(initialValue: host.identityFile ?? "")
        _hostKeyAlias = State(initialValue: host.hostKeyAlias ?? "")
        _identitiesOnly = State(initialValue: host.identitiesOnly ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            formContent
            Divider()
            footer
        }
        .frame(minWidth: 380, minHeight: 340)
    }

    // MARK: - Form

    private var formContent: some View {
        Form {
            Section {
                TextField("HostName", text: $hostName, prompt: Text("ssh.github.com"))
                    .disableAutocorrection(true)
                    .disabled(isSaving)

                TextField("Port", text: $portText, prompt: Text("22"))
                    .disableAutocorrection(true)
                    .disabled(isSaving)

                if !isPortValid {
                    Text("Port must be a number (or empty to remove)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                TextField("User", text: $user, prompt: Text("git"))
                    .disableAutocorrection(true)
                    .disabled(isSaving)
            } header: {
                Text(host.alias)
            }

            Section("Key") {
                TextField("IdentityFile", text: $identityFile, prompt: Text("~/.ssh/id_ed25519"))
                    .disableAutocorrection(true)
                    .disabled(isSaving)

                TextField("HostKeyAlias", text: $hostKeyAlias, prompt: Text("github.com"))
                    .disableAutocorrection(true)
                    .disabled(isSaving)

                Toggle("IdentitiesOnly", isOn: $identitiesOnly)
                    .disabled(isSaving)
            }

            Section {
                Text("Only changed fields are written. The previous config is backed up before saving.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if let errorMessage {
                    Label(errorMessage, systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel", action: onDismiss)
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
            Spacer()
            if isSaving {
                ProgressView().controlSize(.small)
            }
            Button("Save") { Task { await save() } }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || !isPortValid)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, KC.space20)
        .padding(.vertical, KC.space12)
    }

    // MARK: - Validation

    private var isPortValid: Bool {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        return Int(trimmed) != nil
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let text = try String(contentsOfFile: sshConfigPath, encoding: .utf8)
            var doc = SSHConfigDocument.parse(text)
            let alias = host.alias

            let newHostName: String? = emptyToNil(hostName)
            let trimmedPort = portText.trimmingCharacters(in: .whitespaces)
            let newPort: Int? = trimmedPort.isEmpty ? nil : Int(trimmedPort)
            let newUser: String? = emptyToNil(user)
            let newIdentityFile: String? = emptyToNil(identityFile)
            let newHostKeyAlias: String? = emptyToNil(hostKeyAlias)

            if newHostName != host.hostName {
                doc.setField("HostName", to: newHostName, forHost: alias)
            }
            if newPort != host.port {
                doc.setField("Port", to: newPort.map(String.init), forHost: alias)
            }
            if newUser != host.user {
                doc.setField("User", to: newUser, forHost: alias)
            }
            if newIdentityFile != host.identityFile {
                doc.setField("IdentityFile", to: newIdentityFile, forHost: alias)
            }
            if newHostKeyAlias != host.hostKeyAlias {
                doc.setField("HostKeyAlias", to: newHostKeyAlias, forHost: alias)
            }
            if identitiesOnly != (host.identitiesOnly ?? false) {
                doc.setField(
                    "IdentitiesOnly",
                    to: identitiesOnly ? "yes" : "no",
                    forHost: alias
                )
            }

            try ConfigStore.saveSSHConfig(doc, to: sshConfigPath)
            onSaved()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func emptyToNil(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
