import SwiftUI
import AppKit

// Row components used by the popover and the accounts window.

// MARK: - CurrentRepoUnresolvedRow

/// Card shown after a drop that resolved to no identity. When the folder is a
/// repository we can scope, it also offers a one-tap `gitdir:` bind per
/// account — no confirmation, errors land on the card itself.
struct CurrentRepoUnresolvedRow: View {
    let reason: String
    /// Repository root a bind would scope. `nil` hides the bind block.
    var bindPath: String? = nil
    var bindTargets: [Account] = []
    var isBinding: Bool = false
    var bindError: String? = nil
    var onBind: ((Account) -> Void)? = nil
    var onClear: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: KC.space8) {
            HStack(alignment: .top, spacing: KC.space8) {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    if let bindPath {
                        Text(verbatim: bindPath.abbreviatedHomePath())
                            .font(KC.heroMeta)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(verbatim: reason)
                        .font(KC.rowCaption)
                        .foregroundStyle(showsBindBlock ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let onClear {
                    Button(action: onClear) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Clear current repo")
                    .accessibilityLabel(Text("Clear current repo"))
                }
            }

            if showsBindBlock {
                bindBlock
            }

            if let bindError {
                Label {
                    Text(verbatim: bindError)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(KC.meta)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, KC.space14)
        .padding(.vertical, KC.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: KC.heroCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .padding(.horizontal, KC.space10)
        .padding(.top, KC.space10)
    }

    private var showsBindBlock: Bool {
        bindPath != nil && !bindTargets.isEmpty && onBind != nil
    }

    @ViewBuilder
    private var bindBlock: some View {
        VStack(alignment: .leading, spacing: KC.space6) {
            Text("Bind to")
                .font(KC.sectionLabel)
                .foregroundStyle(.secondary)

            VStack(spacing: KC.space4) {
                ForEach(bindTargets) { account in
                    BindTargetRow(
                        account: account,
                        isBinding: isBinding,
                        onTap: { onBind?(account) }
                    )
                }
            }

            Text("Sets a gitdir scope for this folder")
                .font(KC.meta)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, KC.space4)
    }
}

/// One account the dropped folder can be bound to. Names the path the account
/// already owns so a bind reads as additive, never as a replacement.
private struct BindTargetRow: View {
    let account: Account
    let isBinding: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: KC.space8) {
                Circle()
                    .fill(account.color.color)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Group {
                        if account.label.isEmpty {
                            Text("(unnamed)")
                        } else {
                            Text(verbatim: account.label)
                        }
                    }
                    .font(KC.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                    if let existing = existingPath {
                        Text("Already scoped to \(existing) · adds another path")
                            .font(KC.meta)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, KC.space10)
            .padding(.vertical, KC.space6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: KC.cardCornerRadius, style: .continuous)
                    .fill(isHovered
                          ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.22)
                          : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .disabled(isBinding)
        .onHover { isHovered = $0 }
    }

    private var existingPath: String? {
        account.scope.directories
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .abbreviatedHomePath()
    }
}

// MARK: - CurrentRepoMatchedRow (account answer)

struct CurrentRepoMatchedRow: View {
    let account: Account
    let repoRoot: String
    let probe: HostProbeState
    var originURL: String? = nil
    /// Author-vs-key comparison for this repo; findings render under the meta
    /// lines. The one-click re-project stays in Doctor so it is offered once.
    var audit: IdentityAudit? = nil
    var onClear: (() -> Void)? = nil

    @State private var clonePrefill: String

    init(
        account: Account,
        repoRoot: String,
        probe: HostProbeState,
        originURL: String? = nil,
        audit: IdentityAudit? = nil,
        onClear: (() -> Void)? = nil
    ) {
        self.account = account
        self.repoRoot = repoRoot
        self.probe = probe
        self.originURL = originURL
        self.audit = audit
        self.onClear = onClear
        let seed = originURL.flatMap { url -> String? in
            let preferred = CloneURLRewriter.preferredCloneInput(fromOriginURL: url)
            return preferred.isEmpty ? nil : preferred
        } ?? ""
        self._clonePrefill = State(initialValue: seed)
    }

    var body: some View {
        KCHeroContainer(tint: heroTint) {
            VStack(alignment: .leading, spacing: KC.space4) {
                HStack(alignment: .top, spacing: KC.space6) {
                    Group {
                        if account.label.isEmpty {
                            Text("(unnamed)")
                                .font(KC.heroTitle)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text(verbatim: account.label)
                                .font(KC.heroTitle)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let onClear {
                        Button(action: onClear) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Clear current repo")
                        .accessibilityLabel(Text("Clear current repo"))
                    }
                }

                HStack(spacing: 4) {
                    Group {
                        if account.sshAlias.isEmpty {
                            Text("no alias")
                        } else {
                            Text(verbatim: account.sshAlias)
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Group {
                        if account.gitUserEmail.isEmpty {
                            Text("no email")
                        } else {
                            Text(verbatim: account.gitUserEmail)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .font(KC.heroCaption)
                .lineLimit(1)
                .truncationMode(.middle)

                Text(scopeText)
                    .font(KC.heroMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(verbatim: repoRoot.abbreviatedHomePath())
                    .font(KC.heroMeta)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let audit, !audit.isClean {
                    identityMismatchBlock(audit)
                }

                if !account.sshAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    CloneAsIdentityView(
                        account: account,
                        initialInput: clonePrefill
                    )
                    // Recreate when prefill arrives so @State picks it up.
                    .id("clone-\(account.id.uuidString)-\(clonePrefill)")
                    .padding(.top, KC.space4)
                }
            }
        }
        .task(id: repoRoot) {
            await loadClonePrefill()
        }
    }

    @ViewBuilder
    private func identityMismatchBlock(_ audit: IdentityAudit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text("Commits and pushes use different identities")
            } icon: {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
            }
            .font(.system(size: KC.rowSubtitleSize, weight: .medium))
            .foregroundStyle(auditTint(audit))

            ForEach(audit.findings, id: \.self) { finding in
                Text(verbatim: finding.localizedDetail)
                    .font(KC.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, KC.space8)
        .padding(.vertical, KC.space6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: KC.cardCornerRadius, style: .continuous)
                .fill(auditTint(audit).opacity(0.12))
        )
        .padding(.top, KC.space4)
    }

    private func auditTint(_ audit: IdentityAudit) -> Color {
        (audit.severity ?? .warning).tint
    }

    private func loadClonePrefill() async {
        if let originURL, !originURL.isEmpty {
            clonePrefill = CloneURLRewriter.preferredCloneInput(fromOriginURL: originURL)
            if !clonePrefill.isEmpty { return }
        }
        if let origin = await CurrentRepoResolver.readOriginURL(at: repoRoot) {
            clonePrefill = CloneURLRewriter.preferredCloneInput(fromOriginURL: origin)
        }
    }

    private var scopeText: String {
        let dirs = account.scope.directories
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !dirs.isEmpty else { return String(localized: "scope: global") }
        return String(localized: "scope: gitdir:\(dirs.joined(separator: " + "))")
    }

    private var heroTint: Color {
        switch probe {
        case .ok:      return .green
        case .failed:  return .red
        case .probing: return .orange
        case .idle:    return account.color.color
        }
    }
}

// MARK: - AccountRow (compact 2-line popover row, Mac-style)

/// Popover account row. The row body opens the account in the Accounts window;
/// the trailing disclosure reveals the compact clone field. A failing probe
/// always shows its next actions — no expansion required.
struct AccountRow: View {
    let record: Account
    let probe: HostProbeState
    var isExpanded: Bool = false
    var isReprobing: Bool = false
    var onOpenDetail: () -> Void = {}
    var onToggleExpanded: () -> Void = {}
    var onReprobe: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onOpenDetail) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(record.color.color)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 1) {
                            if record.label.isEmpty {
                                Text("(unnamed)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                Text(verbatim: record.label)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            Text(verbatim: subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let scopeLine {
                                Text(verbatim: scopeLine)
                                    .font(KC.metaMono)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                KCStatusDot(status: probe.statusDot, size: 6)

                Button(action: onToggleExpanded) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isExpanded)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide clone command" : "Show clone command")
                .accessibilityLabel(
                    Text(isExpanded ? "Hide clone command" : "Show clone command")
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isHovered
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
                    : Color.clear
            )
            .onHover { isHovered = $0 }

            if case .failed(let reason) = probe {
                ProbeFailureActions(
                    account: record,
                    reason: reason,
                    isReprobing: isReprobing,
                    onReprobe: onReprobe
                )
                .padding(.horizontal, 14)
                .padding(.bottom, KC.space8)
            }

            if isExpanded, !record.sshAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: KC.space4) {
                    Text("Clone")
                        .font(KC.sectionLabel)
                        .foregroundStyle(.secondary)
                    CloneAsIdentityView(account: record)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, KC.space8)
            }
        }
    }

    private var subtitle: String {
        let alias = record.sshAlias.isEmpty
            ? String(localized: "no alias")
            : record.sshAlias
        if record.gitUserEmail.isEmpty { return alias }
        return "\(alias) · \(record.gitUserEmail)"
    }

    /// Every gitdir path this account owns, so a multi-path scope is visible
    /// without opening the Accounts window.
    private var scopeLine: String? {
        let dirs = record.scope.directories
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { $0.abbreviatedHomePath() }
        guard !dirs.isEmpty else { return nil }
        return "gitdir: " + dirs.joined(separator: " + ")
    }
}

// MARK: - ProbeFailureActions (next steps for a red probe)

/// The only place the two post-failure actions live: copy the public key and
/// open the provider's SSH settings. Doctor states the diagnosis instead of
/// repeating these buttons.
struct ProbeFailureActions: View {
    let account: Account
    let reason: String
    let isReprobing: Bool
    let onReprobe: () -> Void

    @State private var didCopy = false
    @State private var copyError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: KC.space6) {
            Label {
                Text("Authentication failed")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.system(size: KC.rowSubtitleSize, weight: .medium))
            .foregroundStyle(.red)

            Text(verbatim: reason)
                .font(KC.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: KC.space10) {
                Button(action: copyPublicKey) {
                    Label(
                        didCopy ? "Copied" : "Copy public key",
                        systemImage: didCopy ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.borderless)

                if let settingsURL = KeyAttachment.sshSettingsURL(for: account.provider) {
                    Button {
                        NSWorkspace.shared.open(settingsURL)
                    } label: {
                        Label(openSettingsLabel, systemImage: "safari")
                    }
                    .buttonStyle(.borderless)
                }

                Spacer(minLength: 0)

                Button(action: onReprobe) {
                    Label("Probe again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isReprobing)
            }
            .font(.system(size: KC.rowSubtitleSize))
            .labelStyle(.titleAndIcon)

            if let copyError {
                Text(verbatim: copyError)
                    .font(KC.meta)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, KC.space10)
        .padding(.vertical, KC.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: KC.cardCornerRadius, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
    }

    private var openSettingsLabel: LocalizedStringKey {
        switch account.provider {
        case .github: return "Open GitHub SSH settings"
        case .gitlab: return "Open GitLab SSH settings"
        case .gitea:  return "Open Gitea SSH settings"
        case .custom: return "Open SSH settings"
        }
    }

    private func copyPublicKey() {
        guard let key = KeyAttachment.readPublicKey(forPrivateKeyPath: account.keyPath) else {
            didCopy = false
            let path = KeyAttachment.publicKeyPath(forPrivateKeyPath: account.keyPath)
            copyError = path.isEmpty
                ? String(localized: "This account has no private key yet.")
                : String(localized: "No public key at \(path.abbreviatedHomePath())")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        copyError = nil
        didCopy = true
    }
}

// MARK: - AddAccountRow (Mac-style add button)

struct AddAccountRow: View {
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tint)
                    .frame(width: 8, height: 8)
                Text("Add Account")
                    .font(.system(size: 13))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                isHovered
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - DoctorSummaryRow (single-line badge for popover)

struct DoctorSummaryRow: View {
    let diagnoses: [Diagnosis]
    var isExpanded: Bool = false
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: KC.space8) {
                Image(systemName: severityIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(severityColor)
                Text(verbatim: summaryText)
                    .font(KC.rowCaption)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
            }
            .padding(.horizontal, KC.rowHPadding)
            .padding(.vertical, KC.space8)
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .onHover { isHovered = $0 }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, KC.space10)
        .padding(.top, KC.space8)
    }

    private var severityIcon: String {
        if diagnoses.contains(where: { $0.severity == .error }) {
            return "exclamationmark.octagon.fill"
        }
        if diagnoses.contains(where: { $0.severity == .warning }) {
            return "exclamationmark.triangle.fill"
        }
        return "info.circle.fill"
    }

    private var severityColor: Color {
        if diagnoses.contains(where: { $0.severity == .error }) { return .red }
        if diagnoses.contains(where: { $0.severity == .warning }) { return .orange }
        return .secondary
    }

    private var summaryText: String {
        let errors = diagnoses.filter { $0.severity == .error }.count
        let warnings = diagnoses.filter { $0.severity == .warning }.count
        var parts: [String] = []
        if errors == 1 {
            parts.append(String(localized: "1 error"))
        } else if errors > 1 {
            parts.append(String(localized: "\(errors) errors"))
        }
        if warnings == 1 {
            parts.append(String(localized: "1 warning"))
        } else if warnings > 1 {
            parts.append(String(localized: "\(warnings) warnings"))
        }
        if parts.isEmpty {
            let infos = diagnoses.count
            return String(localized: "\(infos) info")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - DiagnosisRow (severity-tinted background + inline fix buttons)

struct DiagnosisRow: View {
    let diagnosis: Diagnosis
    let isFixing: Bool
    let onFix: (FixID) -> Void

    @State private var pendingConfirm: FixID?

    var body: some View {
        VStack(alignment: .leading, spacing: KC.space6) {
            HStack(alignment: .top, spacing: KC.space8) {
                Image(systemName: diagnosis.severity.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(diagnosis.severity.tint)
                    .frame(width: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: diagnosis.title)
                        .font(KC.diagnosisTitle)
                    Text(verbatim: diagnosis.detail)
                        .font(KC.diagnosisDetail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint = diagnosis.fixHint {
                        Text(verbatim: hint)
                            .font(KC.diagnosisDetail)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            if !diagnosis.fixes.isEmpty {
                HStack(spacing: KC.space6) {
                    Spacer(minLength: 0)
                    ForEach(diagnosis.fixes) { fix in
                        fixButton(fix)
                    }
                }
            }
        }
        .padding(.horizontal, KC.space12)
        .padding(.vertical, KC.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: KC.cardCornerRadius, style: .continuous)
                .fill(diagnosis.severity.tintFill)
        )
        .padding(.horizontal, KC.space10)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func fixButton(_ fix: FixOption) -> some View {
        let isPending = pendingConfirm == fix.fixID
        let label = isPending ? String(localized: "Confirm") : fix.label
        let symbol = isPending ? "exclamationmark.triangle.fill"
                               : (fix.isDestructive ? "trash" : "wand.and.stars")
        Button {
            if fix.requiresConfirmation && !isPending {
                pendingConfirm = fix.fixID
            } else {
                pendingConfirm = nil
                onFix(fix.fixID)
            }
        } label: {
            Label {
                Text(verbatim: label)
            } icon: {
                Image(systemName: symbol)
            }
            .font(.system(size: KC.diagnosisDetailSize, weight: .medium))
            .foregroundStyle(isPending ? diagnosis.severity.tint : .primary)
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .disabled(isFixing)
    }
}

// MARK: - Shared helpers

extension HostProbeState {
    var statusDot: KCStatusDot.Status {
        switch self {
        case .idle:    return .idle
        case .probing: return .probing
        case .ok:      return .ok
        case .failed:  return .failed
        }
    }

    var hintText: String? {
        switch self {
        case .idle:                 return nil
        case .probing:              return String(localized: "probing…")
        case .ok(let user):         return String(localized: "signed in as \(user)")
        case .failed(let reason):   return reason
        }
    }

    var hintColor: Color {
        switch self {
        case .ok:     return .green
        case .failed: return .red
        default:      return .secondary
        }
    }
}

extension Diagnosis.Severity {
    var tint: Color {
        switch self {
        case .info:    return .secondary
        case .warning: return .orange
        case .error:   return .red
        }
    }

    var tintFill: Color {
        switch self {
        case .info:    return Color.gray.opacity(0.06)
        case .warning: return Color.orange.opacity(0.09)
        case .error:   return Color.red.opacity(0.11)
        }
    }
}
