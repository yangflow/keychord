import SwiftUI

// Quiet blocks that explain the drop gesture and the first-launch path.

// MARK: - DropFolderHintCard

/// Explains the only way to match a repository: drop a folder on the menu-bar
/// icon. The dashed card is an illustration — drops land on the status item,
/// never inside the popover, so this view registers no drop destination.
struct DropFolderHintCard: View {
    var body: some View {
        VStack(spacing: KC.space6) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)

            Text("Drag a project folder onto the menu bar icon above")
                .font(KC.rowCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("See which identity would push from that folder")
                .font(KC.meta)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, KC.space14)
        .padding(.vertical, KC.space14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: KC.heroCornerRadius, style: .continuous)
                .strokeBorder(
                    Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .padding(.horizontal, KC.space10)
        .padding(.top, KC.space10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - AccountsEmptyStateCard

/// First-launch state: no accounts at all. Import lives under the gear, which
/// nobody opens on day one, so the primary action is offered right here.
struct AccountsEmptyStateCard: View {
    let onImport: () -> Void
    let onAddAccount: () -> Void

    var body: some View {
        VStack(spacing: KC.space10) {
            IdentityCardsIllustration()
                .padding(.bottom, KC.space4)

            Text("No identities yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Import from your existing SSH / git config, or add one by hand")
                .font(KC.rowCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: KC.space6) {
                Button(action: onImport) {
                    Text("Import from existing config")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onAddAccount) {
                    Text("Add identity")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, KC.space4)

            Text("You can also drag a folder onto the menu bar icon")
                .font(KC.meta)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, KC.space4)
        }
        .padding(.horizontal, KC.space20)
        .padding(.vertical, KC.space24)
        .frame(maxWidth: .infinity)
    }
}

/// Two stacked identity cards, drawn from system shapes so it stays native at
/// any appearance / accent.
private struct IdentityCardsIllustration: View {
    var body: some View {
        ZStack {
            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(8))
                .offset(x: 12, y: -4)

            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tint)
                .opacity(0.75)
                .offset(x: -6, y: 2)
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }
}
