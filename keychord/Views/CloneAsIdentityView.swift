import SwiftUI
import AppKit

/// Paste `org/repo` or an original clone URL, copy `git clone git@<alias>:…`.
/// In the Accounts form this is a quiet Form row; `compact` keeps a bordered
/// field for the menubar popover hero (optionally prefilled from origin).
struct CloneAsIdentityView: View {
    let account: Account
    var compact: Bool = false
    private let initialInput: String

    @State private var input: String
    @State private var didCopy = false

    init(account: Account, compact: Bool = false, initialInput: String = "") {
        self.account = account
        self.compact = compact
        self.initialInput = initialInput
        self._input = State(initialValue: initialInput)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KC.space4) {
            HStack(spacing: KC.space6) {
                field
                    .font(compact ? KC.rowCaptionMono : nil)
                    .disableAutocorrection(true)
                    .onChange(of: input) { _, _ in
                        didCopy = false
                    }

                Button {
                    copyCommand()
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(cloneCommand == nil)
                .help("Copy clone command")
                .accessibilityLabel(Text(didCopy ? "Copied" : "Copy clone command"))
            }

            // Accounts detail always shows a command line (example when empty).
            // Popover compact keeps the field only.
            if !compact, let preview = commandPreview {
                Text(verbatim: preview)
                    .font(KC.rowCaptionMono)
                    .foregroundStyle(cloneCommand == nil ? .tertiary : .secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            applyInitialInputIfNeeded()
        }
        .onChange(of: initialInput) { _, newValue in
            if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                input = newValue
                didCopy = false
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        let prompt = Text("org/repo")
        if compact {
            TextField("", text: $input, prompt: prompt)
                .textFieldStyle(.roundedBorder)
        } else {
            TextField("Repository", text: $input, prompt: prompt)
        }
    }

    private var cloneCommand: String? {
        account.cloneCommand(for: input)
    }

    /// Live rewrite when input is valid; otherwise an example using the alias.
    private var commandPreview: String? {
        if let cloneCommand { return cloneCommand }
        let alias = account.sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { return nil }
        return "git clone git@\(alias):org/repo.git"
    }

    private func applyInitialInputIfNeeded() {
        let seed = initialInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !seed.isEmpty else { return }
        input = seed
    }

    private func copyCommand() {
        guard let command = cloneCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        didCopy = true
    }
}
