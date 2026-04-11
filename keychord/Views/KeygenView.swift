import SwiftUI
import AppKit

struct KeygenView: View {
    let defaultComment: String
    let onDismiss: () -> Void
    let onKeyCreated: () -> Void

    @State private var keyName: String = "id_keychord"
    @State private var comment: String
    @State private var keyType: KeygenService.KeyType = .ed25519
    @State private var isGenerating = false
    @State private var result: KeygenResult?
    @State private var errorMessage: String?

    init(
        defaultComment: String,
        onDismiss: @escaping () -> Void,
        onKeyCreated: @escaping () -> Void
    ) {
        self.defaultComment = defaultComment
        self.onDismiss = onDismiss
        self.onKeyCreated = onKeyCreated
        _comment = State(initialValue: defaultComment)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let result {
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
                            copyToClipboard(result.publicKeyContent)
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
                }

                Section {
                    Text("Paste the public key into GitHub → Settings → SSH and GPG keys → New SSH key. Then reference `\(keyBaseName(result.privateKeyPath))` in a Host block.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button {
                    revealInFinder(result.privateKeyPath)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Done") {
                    onKeyCreated()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, KC.space20)
            .padding(.vertical, KC.space12)
        }
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
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func copyToClipboard(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func keyBaseName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
