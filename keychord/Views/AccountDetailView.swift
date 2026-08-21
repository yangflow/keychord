import SwiftUI
import AppKit

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
                Section {
                    LabeledTextField(label: "Label", text: $draft.label, placeholder: "Personal")
                    Picker("Provider", selection: $draft.provider) {
                        ForEach(Account.Provider.allCases) { provider in
                            Text(provider.localizedLabel).tag(provider)
                        }
                    }
                    LabeledTextField(label: "Username", text: $draft.username, placeholder: "octocat")
                    LabeledTextField(label: "Git name", text: $draft.gitUserName, placeholder: "Your Name")
                    LabeledTextField(label: "Git email", text: $draft.gitUserEmail, placeholder: "you@example.com")
                } header: {
                    Text("Identity")
                }

                Section {
                    LabeledTextField(label: "Alias", text: $draft.sshAlias, placeholder: "github-work")
                    HStack(spacing: KC.space6) {
                        TextField("Private key", text: $draft.keyPath, prompt: Text("~/.ssh/id_ed25519"))
                            .disableAutocorrection(true)
                        Button {
                            pickPrivateKey()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Choose private key…")
                        .accessibilityLabel(Text("Choose private key"))
                    }
                    Picker("Port", selection: $draft.sshPort) {
                        ForEach(Account.SSHPort.allCases, id: \.self) { port in
                            Text(port.displayName).tag(port)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("SSH")
                }

                Section {
                    Picker("Mode", selection: scopeBinding) {
                        Text("Global").tag(0)
                        Text("gitdir scoped").tag(1)
                    }
                    .pickerStyle(.segmented)
                    if case .gitdir = draft.scope {
                        HStack(spacing: KC.space6) {
                            TextField("Directory", text: $scopeDir, prompt: Text("~/work/"))
                                .disableAutocorrection(true)
                                .onChange(of: scopeDir) { _, newValue in
                                    draft.scope = .gitdir(newValue)
                                }
                            Button {
                                pickGitdir()
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("Choose directory…")
                            .accessibilityLabel(Text("Choose gitdir directory"))
                        }
                    }
                } header: {
                    Text("Scope")
                }

                Section {
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
                    if draft.provider != .custom {
                        Button {
                            draft.applyInsteadOfPreset()
                        } label: {
                            Label("Apply rewrite preset", systemImage: "wand.and.stars")
                        }
                        .disabled(draft.sshAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Add insteadOf rules for this provider’s common HTTPS and SSH clone URLs.")
                    }
                } header: {
                    Text("URL Rewrites")
                }

                Section {
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
                            .accessibilityLabel(Text(color.localizedAccessibilityLabel))
                        }
                    }
                } header: {
                    Text("Appearance")
                }

                Section {
                    TextEditor(text: $draft.notes)
                        .font(.system(size: 12))
                        .frame(minHeight: 80, maxHeight: 120)
                } header: {
                    Text("Notes")
                }

                Section {
                    MetadataRow(label: "Created", date: draft.createdAt)
                    MetadataRow(label: "Updated", date: draft.updatedAt)
                    MetadataRow(label: "Last used", date: draft.lastUsedAt)
                } header: {
                    Text("Metadata")
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
            Group {
                if isNew {
                    Text("New account")
                } else if draft.label.isEmpty {
                    Text("(unnamed)")
                } else {
                    Text(verbatim: draft.label)
                }
            }
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
                Label {
                    Text(verbatim: status)
                } icon: {
                    Image(systemName: statusIsError ? "xmark.circle" : "checkmark.circle")
                }
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

    // MARK: - Path pickers

    private func pickGitdir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose the directory this account gitdir scope applies to.")
        if !scopeDir.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: ConfigStore.expand(scopeDir), isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let normalized = CurrentRepoResolver.normalizeGitdir(url.path)
        scopeDir = normalized
        draft.scope = .gitdir(normalized)
    }

    private func pickPrivateKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose an SSH private key file.")
        let sshDir = (NSHomeDirectory() as NSString).appendingPathComponent(".ssh")
        panel.directoryURL = URL(fileURLWithPath: sshDir, isDirectory: true)
        if !draft.keyPath.isEmpty {
            let expanded = ConfigStore.expand(draft.keyPath)
            panel.directoryURL = URL(fileURLWithPath: expanded).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.keyPath = AccountProjector.normalizeKeyPath(url.path)
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
    let label: LocalizedStringKey
    @Binding var text: String
    let placeholder: LocalizedStringKey

    var body: some View {
        TextField(label, text: $text, prompt: Text(placeholder))
            .disableAutocorrection(true)
    }
}

private struct MetadataRow: View {
    let label: LocalizedStringKey
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

private extension Account.AccountColor {
    var localizedAccessibilityLabel: LocalizedStringKey {
        switch self {
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .red: return "Red"
        case .purple: return "Purple"
        case .yellow: return "Yellow"
        }
    }
}

private extension Account.Provider {
    var localizedLabel: LocalizedStringKey {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .gitea:  return "Gitea"
        case .custom: return "Custom"
        }
    }
}
