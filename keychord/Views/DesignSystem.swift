import SwiftUI

// MARK: - String helpers

extension String {
    /// Replace a leading `$HOME/...` with `~/...` for display purposes.
    /// Returns the original string if the path is not under the home dir.
    func abbreviatedHomePath() -> String {
        let home = NSHomeDirectory()
        if hasPrefix(home) {
            return "~" + dropFirst(home.count)
        }
        return self
    }
}

// MARK: - Design tokens

/// Design system for keychord. System semantic colors only — the
/// popover adopts light/dark mode and the user's accent automatically.
/// Visual refinement comes from spacing, grouping and materials.
enum KC {
    // MARK: Layout

    static let popoverWidth: CGFloat       = 340
    static let popoverHeight: CGFloat      = 480

    // MARK: Spacing scale (4-pt grid)

    static let space4: CGFloat  = 4
    static let space6: CGFloat  = 6
    static let space8: CGFloat  = 8
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space14: CGFloat = 14
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24

    /// Standard horizontal padding for rows inside the popover.
    static let rowHPadding: CGFloat  = 14
    /// Standard vertical padding for rows inside the popover.
    static let rowVPadding: CGFloat  = 6

    static let sectionHeaderTop: CGFloat    = 14
    static let sectionHeaderBottom: CGFloat = 4

    // MARK: Card

    static let cardCornerRadius: CGFloat = 10
    static let heroCornerRadius: CGFloat = 12

    // MARK: Typography — semantic fonts

    /// Hero answer line — "signs in as yangflow"  (17pt semibold)
    static let heroTitle = Font.system(size: 17, weight: .semibold)
    /// Hero context line — name · email · alias  (12pt regular)
    static let heroCaption = Font.system(size: 12)
    /// Hero meta line — ~/repo path  (10pt monospaced)
    static let heroMeta = Font.system(size: 10, design: .monospaced)

    /// Popover row title — account label, host alias  (13pt medium)
    static let rowTitle = Font.system(size: 13, weight: .medium)
    /// Popover row subtitle — alias · email  (11pt regular)
    static let rowCaption = Font.system(size: 11)
    /// Popover row subtitle monospaced variant
    static let rowCaptionMono = Font.system(size: 11, design: .monospaced)
    /// Tiny metadata — hint text, rewrite count  (10pt)
    static let meta = Font.system(size: 10)
    /// Tiny metadata monospaced
    static let metaMono = Font.system(size: 10, design: .monospaced)

    /// Section label — "ACCOUNTS · 3"  (10pt semibold)
    static let sectionLabel = Font.system(size: 10, weight: .semibold)

    /// Doctor row title (12pt medium)
    static let diagnosisTitle = Font.system(size: 12, weight: .medium)
    /// Doctor detail / fix hint (10pt)
    static let diagnosisDetail = Font.system(size: 10)

    // MARK: Legacy size constants (used by views not yet migrated)

    static let heroAnswerSize: CGFloat      = 17
    static let heroContextSize: CGFloat     = 12
    static let heroMetaSize: CGFloat        = 10
    static let rowTitleSize: CGFloat        = 13
    static let rowSubtitleSize: CGFloat     = 11
    static let rowMetaSize: CGFloat         = 10
    static let sectionLabelSize: CGFloat    = 10
    static let diagnosisTitleSize: CGFloat  = 12
    static let diagnosisDetailSize: CGFloat = 10
}

// MARK: - Section header

/// Uppercase small caps with wide kerning — recedes below the data
/// rows so it never competes with actual content for attention.
struct KCSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(KC.sectionLabel)
            .kerning(0.8)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, KC.rowHPadding)
            .padding(.top, KC.sectionHeaderTop)
            .padding(.bottom, KC.sectionHeaderBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status dot (system semantic colors)

struct KCStatusDot: View {
    enum Status { case idle, probing, ok, failed }

    let status: Status
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    init(status: Status, size: CGFloat = 6) {
        self.status = status
        self.size = size
    }

    private var color: Color {
        switch status {
        case .idle:    return .secondary
        case .probing: return .orange
        case .ok:      return .green
        case .failed:  return .red
        }
    }

    private var shouldPulse: Bool {
        status == .probing && !reduceMotion
    }

    var body: some View {
        Circle()
            .fill(color)
            .opacity(status == .idle ? 0.35 : 1.0)
            .frame(width: size, height: size)
            .opacity(shouldPulse && pulse ? 0.4 : 1.0)
            .animation(
                shouldPulse
                    ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                    : .default,
                value: pulse
            )
            .onAppear { if shouldPulse { pulse = true } }
    }
}

// MARK: - Row container

struct KCRowContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, KC.rowHPadding)
            .padding(.vertical, KC.rowVPadding)
            .contentShape(Rectangle())
    }
}

// MARK: - Card container

/// Grouped inset container — controlBackgroundColor rounded rect
/// with a subtle stroke and shadow. Use for popover sections.
struct KCCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: KC.cardCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: KC.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// MARK: - Grouped section  (header + card)

/// Section label + KCCard wrapping content rows, with consistent margins.
struct KCGroupedSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KCSectionHeader(title: title)
            KCCard {
                content()
            }
            .padding(.horizontal, KC.space10)
        }
    }
}

// MARK: - Hero container (tinted callout card)

/// Floating rounded-rect card with a tinted fill. Used only for the
/// Current Repo "answer" at the top of the popover. The tint
/// cross-fades to green / red based on the probe state so the color
/// itself carries the "am I about to push as the right person" signal.
struct KCHeroContainer<Content: View>: View {
    let tint: Color
    let content: () -> Content

    init(tint: Color, @ViewBuilder content: @escaping () -> Content) {
        self.tint = tint
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, KC.space14)
            .padding(.vertical, KC.space12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: KC.heroCornerRadius, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: KC.heroCornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: KC.heroCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .padding(.horizontal, KC.space10)
            .padding(.top, KC.space10)
            .animation(.easeOut(duration: 0.18), value: tint)
    }
}
