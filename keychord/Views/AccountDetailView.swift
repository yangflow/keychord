import SwiftUI

struct AccountDetailView: View {
    @Binding var draft: Account
    let isNew: Bool
    let statusMessage: String?
    let statusIsError: Bool
    let onSave: () -> Void
    let onRevert: () -> Void
    let onDelete: (() -> Void)?

    @State private var scopeDir: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Form {
                Section("Identity") {
                    LabeledTextField(label: "Label", text: $draft.label, placeholder: "Personal")
                    LabeledTextField(label: "GitHub username", text: $draft.githubUsername, placeholder: "octocat")
                    LabeledTextField(label: "Git name", text: $draft.gitUserName, placeholder: "Your Name")
                    LabeledTextField(label: "Git email", text: $draft.gitUserEmail, placeholder: "you@example.com")
                }

                Section("SSH") {
                    LabeledTextField(label: "Alias", text: $draft.sshAlias, placeholder: "github-work")
                    LabeledTextField(label: "Private key", text: $draft.keyPath, placeholder: "~/.ssh/id_ed25519")
                    Picker("Port", selection: $draft.sshPort) {
                        ForEach(Account.SSHPort.allCases, id: \.self) { port in
                            Text(port.displayName).tag(port)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Scope") {
                    Picker("Mode", selection: scopeBinding) {
                        Text("Global").tag(0)
                        Text("gitdir scoped").tag(1)
                    }
                    .pickerStyle(.segmented)
                    if case .gitdir = draft.scope {
                        TextField("Directory", text: $scopeDir, prompt: Text("~/work/"))
                            .onChange(of: scopeDir) { _, newValue in
                                draft.scope = .gitdir(newValue)
                            }
                    }
                }

                Section("URL Rewrites") {
                    ForEach(draft.urlRewrites.indices, id: \.self) { idx in
                        rewriteRow(index: idx)
                    }
                    Button {
                        draft.urlRewrites.append(
                            Account.URLRewrite(from: "", to: "")
                        )
                    } label: {
                        Label("Add rewrite", systemImage: "plus.circle")
                    }
                }

                Section("Appearance") {
                    HStack(spacing: KC.space8) {
                        Text("Color")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ForEach(Account.AccountColor.allCases, id: \.self) { color in
                            Button {
                                draft.color = color
                            } label: {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(.primary.opacity(draft.color == color ? 0.6 : 0), lineWidth: 2)
                                    }
                                    .scaleEffect(draft.color == color ? 1.15 : 1.0)
                                    .animation(.easeInOut(duration: 0.15), value: draft.color)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.rawValue.capitalized)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .font(.system(size: 12))
                        .frame(minHeight: 80, maxHeight: 120)
                }

                Section("Metadata") {
                    MetadataRow(label: "Created", date: draft.createdAt)
                    MetadataRow(label: "Updated", date: draft.updatedAt)
                    MetadataRow(label: "Last used", date: draft.lastUsedAt)
                }
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .onChange(of: draft.scope) { _, newScope in
            if case .gitdir(let dir) = newScope {
                scopeDir = dir
            }
        }
        .onAppear {
            if case .gitdir(let dir) = draft.scope {
                scopeDir = dir
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: KC.space10) {
            Circle()
                .fill(draft.color.color)
                .frame(width: 14, height: 14)
            Text(isNew ? "New account" : (draft.label.isEmpty ? "(unnamed)" : draft.label))
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(draft.scope.isScoped ? "SCOPED" : "GLOBAL")
                .font(KC.sectionLabel)
                .kerning(0.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, KC.space20)
        .padding(.vertical, KC.space14)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let status = statusMessage {
                Label(status, systemImage: statusIsError ? "xmark.circle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(statusIsError ? Color.red : Color.green)
            }
            Spacer()
            if let onDelete = onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button("Revert", action: onRevert)
            Button(isNew ? "Create" : "Save", action: onSave)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, KC.space20)
        .padding(.vertical, KC.space12)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func rewriteRow(index: Int) -> some View {
        HStack(spacing: KC.space6) {
            TextField("from", text: $draft.urlRewrites[index].from)
                .font(KC.rowCaptionMono)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            TextField("to", text: $draft.urlRewrites[index].to)
                .font(KC.rowCaptionMono)
            Button(role: .destructive) {
                draft.urlRewrites.remove(at: index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Scope binding

    private var scopeBinding: Binding<Int> {
        Binding(
            get: {
                if case .gitdir = draft.scope { return 1 }
                return 0
            },
            set: { newValue in
                if newValue == 1 {
                    draft.scope = .gitdir(scopeDir.isEmpty ? "~/" : scopeDir)
                } else {
                    draft.scope = .global
                }
            }
        )
    }

}

// MARK: - Helpers

private struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextField(label, text: $text, prompt: Text(placeholder))
            .disableAutocorrection(true)
    }
}

private struct MetadataRow: View {
    let label: String
    let date: Date?

    var body: some View {
        LabeledContent(label) {
            Group {
                if let date {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                } else {
                    Text("—")
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}
