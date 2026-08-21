import SwiftUI
import AppKit

/// Read-only field: paste `org/repo` or an original clone URL, copy the
/// rewritten `git clone git@<alias>:…` command for this account.
struct CloneAsIdentityView: View {
    let account: Account
    var compact: Bool = false

    @State private var input: String = ""
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? KC.space6 : KC.space8) {
            HStack(spacing: KC.space6) {
                TextField(
                    "",
                    text: $input,
                    prompt: Text("org/repo or paste URL")
                )
                .textFieldStyle(.roundedBorder)
                .font(KC.rowCaptionMono)
                .disableAutocorrection(true)
                .onChange(of: input) { _, _ in
                    didCopy = false
                }

                Button {
                    copyCommand()
                } label: {
                    Label(
                        didCopy ? "Copied" : "Copy",
                        systemImage: didCopy ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.borderless)
                .disabled(cloneCommand == nil)
                .help("Copy rewritten clone command")
                .accessibilityLabel(Text(didCopy ? "Copied" : "Copy rewritten clone command"))
            }

            if let command = cloneCommand {
                Text(verbatim: command)
                    .font(KC.rowCaptionMono)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !trimmedInput.isEmpty {
                Text("Cannot rewrite — check alias or URL")
                    .font(KC.rowCaption)
                    .foregroundStyle(.tertiary)
            } else if !compact {
                Text("Accepts org/repo or a GitHub/GitLab/Gitea clone URL.")
                    .font(KC.rowCaption)
                    .foregroundStyle(.tertiary)
            }
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
