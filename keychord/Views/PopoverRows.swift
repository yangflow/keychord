import SwiftUI

// Row components used by the popover and the accounts window.

// MARK: - AccountRow (compact 2-line popover row, Mac-style)

struct AccountRow: View {
    let record: Account
    let probe: HostProbeState

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(record.color.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(record.label.isEmpty ? "(unnamed)" : record.label)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            KCStatusDot(status: probe.statusDot, size: 6)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            isHovered
                ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
                : Color.clear
        )
        .onHover { isHovered = $0 }
    }

    private var subtitle: String {
        let alias = record.sshAlias.isEmpty ? "no alias" : record.sshAlias
        if record.gitUserEmail.isEmpty { return alias }
        return "\(alias) · \(record.gitUserEmail)"
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
                Text(summaryText)
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
        if errors > 0 { parts.append("\(errors) error\(errors == 1 ? "" : "s")") }
        if warnings > 0 { parts.append("\(warnings) warning\(warnings == 1 ? "" : "s")") }
        if parts.isEmpty {
            let infos = diagnoses.count
            return "\(infos) info"
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
                    Text(diagnosis.title)
                        .font(KC.diagnosisTitle)
                    Text(diagnosis.detail)
                        .font(KC.diagnosisDetail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint = diagnosis.fixHint {
                        Text(hint)
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
        let label = isPending ? "Confirm" : fix.label
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
            Label(label, systemImage: symbol)
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
        case .probing:              return "probing…"
        case .ok(let user):         return "signed in as \(user)"
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
