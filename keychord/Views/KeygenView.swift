import SwiftUI
import AppKit

struct KeygenView: View {
    let defaultComment: String
    let accounts: [Account]
    let onDismiss: () -> Void
    /// Called after the user attaches the key to an account (existing or new).
    /// Parent is responsible for persistence + projection; this view does not
    /// write on Cancel.
    let onAttached: (Account, Bool) -> Void

    @State private var keyName: String = "id_keychord"
    @State private var comment: String
    @State private var keyType: KeygenService.KeyType = .ed25519
    @State private var isGenerating = false
    @State private var result: KeygenResult?
    @State private var errorMessage: String?
    @State private var showingAttachPicker = false
    @State private var didCopy = false

    init(
        defaultComment: String,
        accounts: [Account],
        onDismiss: @escaping () -> Void,
        onAttached: @escaping (Account, Bool) -> Void
    ) {
        self.defaultComment = defaultComment
        self.accounts = accounts
        self.onDismiss = onDismiss
        self.onAttached = onAttached
        _comment = State(initialValue: defaultComment)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingAttachPicker, let result {
                attachPickerView(result)
            } else if let result {
                resultView(result)
            } else {
                formView
            }
        }
        .frame(minWidth: 400, minHeight: 320)
    }

    // MARK: - Form

    private var formView: some View {
        VStack(spacing: 0) {
            Form {
                Section("Key Type") {
                    Picker("Type", selection: $keyType) {
                        ForEach(KeygenService.KeyType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isGenerating)
                }

                Section("Details") {
                    TextField("File name", text: $keyName, prompt: Text("id_keychord"))
                        .disableAutocorrection(true)
                        .disabled(isGenerating)
                    TextField("Comment", text: $comment, prompt: Text("you@example.com"))
                        .disableAutocorrection(true)
                        .disabled(isGenerating)
                }

                Section {
                    Text("The key will be written to ~/.ssh/\(keyName.trimmingCharacters(in: .whitespaces)). Passphrase will be empty — you can add one later with `ssh-keygen -p`.")
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

            Divider()

            HStack {
                Button("Cancel", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isGenerating)
                Spacer()
                if isGenerating {
                    ProgressView().controlSize(.small)
                }
                Button("Generate") { Task { await generate() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || !canGenerate)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, KC.space20)
            .padding(.vertical, KC.space12)
        }
    }

    // MARK: - Result

    private func resultView(_ result: KeygenResult) -> some View {
        VStack(spacing: 0) {
            Form {
                Section("Public Key") {
                    ZStack(alignment: .topTrailing) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(result.publicKeyContent)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(KC.space8)
                        }
                        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                        Button {
                            copyPublicKey(result.publicKeyContent)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .padding(KC.space6)
                        .help("Copy public key")
                    }
                }

                Section {
                    LabeledContent("Path") {
                        Text(result.privateKeyPath.abbreviatedHomePath())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let fingerprint = result.fingerprint {
                        LabeledContent("Fingerprint") {
                            Text(fingerprint)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Section {
                    Text("Copy the public key and add it under GitHub → Settings → SSH and GPG keys. Then use it with an account so keychord can project the Host block.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)

            Divider()

            VStack(spacing: KC.space10) {
                HStack {
                    Button {
                        copyPublicKey(result.publicKeyContent)
                    } label: {
                        Label(didCopy ? "Copied" : "Copy public key", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        openGitHubSSHSettings()
                    } label: {
                        Label("Open GitHub SSH settings", systemImage: "safari")
                    }
                    .buttonStyle(.borderless)

                    Spacer()
                }

                HStack {
                    Button("Done", action: onDismiss)
                        .keyboardShortcut(.cancelAction)
                    Button {
                        revealInFinder(result.privateKeyPath)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Button("Use with this account") {
                        showingAttachPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, KC.space20)
            .padding(.vertical, KC.space12)
        }
    }

    // MARK: - Attach picker

    private func attachPickerView(_ result: KeygenResult) -> some View {
        VStack(spacing: 0) {
            Form {
                Section("Use with this account") {
                    if accounts.isEmpty {
                        Text("No accounts yet. Create a new one to attach this key.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(accounts) { account in
                            Button {
                                attach(to: account, isNew: false, result: result)
                            } label: {
                                accountRow(account)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button {
                        let fresh = KeyAttachment.makeNewAccount(
                            from: result,
                            suggestedEmail: comment
                        )
                        attach(to: fresh, isNew: true, result: result)
                    } label: {
                        Label("Create new account", systemImage: "plus.circle")
                    }
                }

                Section {
                    Text("Cancel leaves accounts unchanged. The key files stay in ~/.ssh/.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") {
                    // Cancel attach must not write an account.
                    showingAttachPicker = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(.horizontal, KC.space20)
            .padding(.vertical, KC.space12)
        }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: KC.space10) {
            Circle()
                .fill(account.color.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.label.isEmpty ? "(unnamed)" : account.label)
                    .font(KC.rowTitle)
                    .lineLimit(1)
                Text(account.sshAlias.isEmpty ? "no alias" : account.sshAlias)
                    .font(KC.rowCaptionMono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, KC.space4)
    }

    // MARK: - Actions

    private var canGenerate: Bool {
        let trimmed = keyName.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !comment.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func generate() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            let r = try await KeygenService.generate(
                type: keyType,
                name: keyName,
                comment: comment
            )
            result = r
            didCopy = false
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func attach(to account: Account, isNew: Bool, result: KeygenResult) {
        // Re-apply path/fingerprint so both existing and new targets stay consistent.
        let updated = KeyAttachment.apply(result: result, to: account)
        onAttached(updated, isNew)
        showingAttachPicker = false
        onDismiss()
    }

    private func copyPublicKey(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        didCopy = true
    }

    private func openGitHubSSHSettings() {
        guard let url = KeyAttachment.githubSSHSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
