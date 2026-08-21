import SwiftUI
import AppKit

/// Paste `org/repo` or an original clone URL, copy `git clone git@<alias>:…`.
/// In the Accounts form this is a quiet Form row; `compact` keeps a bordered
/// field for the menubar popover hero (optionally prefilled from origin).
struct CloneAsIdentityView: View {
    let account: Account
    var compact: Bool = false

    @State private var input: String
    @State private var didCopy = false

    init(account: Account, compact: Bool = false, initialInput: String = "") {
        self.account = account
        self.compact = compact
        self._input = State(initialValue: initialInput)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? KC.space6 : KC.space4) {
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

            if let command = cloneCommand {
                Text(verbatim: command)
                    .font(KC.rowCaptionMono)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !trimmedInput.isEmpty {
                Text("Cannot rewrite")
                    .font(KC.rowCaption)
                    .foregroundStyle(.tertiary)
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

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cloneCommand: String? {
        account.cloneCommand(for: input)
    }

    private func copyCommand() {
        guard let command = cloneCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        didCopy = true
    }
}
