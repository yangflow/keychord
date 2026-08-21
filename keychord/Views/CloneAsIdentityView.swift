import SwiftUI
import AppKit

/// Compact popover field: paste `org/repo` or a URL, copy `git clone git@<alias>:…`.
/// Optionally prefilled from a matched repo’s `origin`, otherwise from the last
/// `org/` this account cloned, so the owner does not have to be retyped.
struct CloneAsIdentityView: View {
    let account: Account
    private let initialInput: String
    private let prefixMemory: ClonePrefixMemory

    @State private var input: String
    @State private var didCopy = false
    @State private var rememberedPrefix: String?

    init(
        account: Account,
        initialInput: String = "",
        prefixMemory: ClonePrefixMemory = .shared
    ) {
        self.account = account
        self.initialInput = initialInput
        self.prefixMemory = prefixMemory
        self._input = State(initialValue: initialInput)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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

            if let rememberedPrefix {
                Text("Remembered prefix: \(rememberedPrefix)")
                    .font(KC.meta)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .onAppear {
            rememberedPrefix = prefixMemory.prefix(for: account.id)
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

    /// Prefer the repo we resolved; fall back to the remembered `org/` so the
    /// user only types the repository name.
    private func applyInitialInputIfNeeded() {
        guard input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let seed = initialInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !seed.isEmpty {
            input = seed
        } else if let rememberedPrefix {
            input = rememberedPrefix
        }
    }

    private func copyCommand() {
        guard let command = cloneCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        didCopy = true
        prefixMemory.remember(input: input, for: account.id)
        rememberedPrefix = prefixMemory.prefix(for: account.id)
    }
}
