import SwiftUI
import AppKit

/// Compact popover field: paste `org/repo` or a URL, copy `git clone git@<alias>:…`.
/// Optionally prefilled from a matched repo’s `origin`, otherwise from the last
/// `org/` this account cloned, so the owner does not have to be retyped.
struct CloneAsIdentityView: View {
    let account: Account
    private let initialInput: String
    private let prefixMemory: ClonePrefixMemory
    /// Called after a successful copy so the caller can mark the identity as
    /// just used (#43).
    private let onCopy: (() -> Void)?

    @State private var input: String
    @State private var copied = TransientConfirmation()
    @State private var rememberedPrefix: String?

    /// `prefixMemory` has no default: a default argument expression is
    /// nonisolated, and the shared instance lives on the main actor.
    init(
        account: Account,
        initialInput: String = "",
        prefixMemory: ClonePrefixMemory,
        onCopy: (() -> Void)? = nil
    ) {
        self.account = account
        self.initialInput = initialInput
        self.prefixMemory = prefixMemory
        self.onCopy = onCopy
        self._input = State(initialValue: initialInput)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: KC.space6) {
                TextField("", text: $input, prompt: Text("org/repo"))
                    .textFieldStyle(.roundedBorder)
                    .font(KC.rowCaptionMono)
                    .disableAutocorrection(true)
                    // Return copies, same as the button, and only while this
                    // field has focus (#46). No-op when nothing rewrites.
                    .onSubmit(copyCommand)
                    .onChange(of: input) { _, _ in
                        copied.reset()
                    }

                Button {
                    copyCommand()
                } label: {
                    Image(systemName: copied.isShowing ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(cloneCommand == nil)
                .help("Copy clone command")
                .accessibilityLabel(Text(copied.isShowing ? "Copied" : "Copy clone command"))
            }

            if copied.isShowing {
                Text("Copied")
                    .font(KC.meta)
                    .foregroundStyle(.green)
            } else if let rememberedPrefix {
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
                copied.reset()
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
        copied.flash()
        prefixMemory.remember(input: input, for: account.id)
        rememberedPrefix = prefixMemory.prefix(for: account.id)
        onCopy?()
    }
}
