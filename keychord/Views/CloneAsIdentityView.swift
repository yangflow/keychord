import SwiftUI
import AppKit

/// Compact popover field: paste `org/repo` or a URL, copy `git clone git@<alias>:…`.
/// Optionally prefilled from a matched repo’s `origin`.
struct CloneAsIdentityView: View {
    let account: Account
    private let initialInput: String

    @State private var input: String
    @State private var didCopy = false

    init(account: Account, initialInput: String = "") {
        self.account = account
        self.initialInput = initialInput
        self._input = State(initialValue: initialInput)
    }

    var body: some View {
        HStack(spacing: KC.space6) {
            TextField("", text: $input, prompt: Text("org/repo"))
                .textFieldStyle(.roundedBorder)
                .font(KC.rowCaptionMono)
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

    private var cloneCommand: String? {
        account.cloneCommand(for: input)
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
