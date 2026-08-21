import SwiftUI

// Cards for the two ways a gitdir scope can be wrong: several scopes covering
// one repository, and a scope pointing at a folder that no longer exists.

// MARK: - GitdirOverlapCard

/// Two or more accounts scope the same repository. git applies every matching
/// `includeIf` in file order and the last one wins, so this names the winner,
/// says who it overrides, and offers the two ways out.
struct GitdirOverlapCard: View {
    let overlap: GitdirOverlap
    var isBusy: Bool = false
    var errorMessage: String? = nil
    let onClaimWinner: (Account) -> Void
    let onReleaseLoser: (_ path: String, _ account: Account) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KC.space8) {
            HStack(alignment: .top, spacing: KC.space8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: overlap.repoRoot.abbreviatedHomePath())
                        .font(KC.heroMeta)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(overlap.contenders.count) identities match this folder")
                        .font(KC.rowCaption)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: KC.space4) {
                ForEach(overlap.contenders) { contender in
                    contenderRow(contender)
                }
            }

            if let winner = overlap.winner, let loser = overlap.losers.last {
                Text("\(winner.displayLabel) overrides \(loser.displayLabel)")
                    .font(KC.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: KC.space6) {
                    Button {
                        onClaimWinner(winner.account)
                    } label: {
                        Text("Only use \(winner.displayLabel) here")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isBusy)

                    Button {
                        onReleaseLoser(loser.path, loser.account)
                    } label: {
                        Text("Unbind \(loser.displayLabel) from \(loser.path.abbreviatedHomePath())")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBusy)
                }
                .font(.system(size: KC.rowSubtitleSize))
            }

            if let errorMessage {
                Text(verbatim: errorMessage)
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
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: KC.heroCornerRadius, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.22), lineWidth: 0.5)
        )
        .padding(.horizontal, KC.space10)
        .padding(.top, KC.space10)
    }

    @ViewBuilder
    private func contenderRow(_ contender: GitdirOverlap.Contender) -> some View {
        HStack(alignment: .center, spacing: KC.space8) {
            Circle()
                .fill(contender.account.color.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: contender.displayLabel)
                    .font(KC.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: "gitdir: \(contender.path.abbreviatedHomePath())")
                    .font(KC.metaMono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: KC.space6)

            Group {
                if contender.isWinner {
                    Text("git uses this one")
                        .foregroundStyle(.primary)
                } else {
                    Text("read first, then overridden")
                        .foregroundStyle(.secondary)
                }
            }
            .font(KC.meta)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, KC.space10)
        .padding(.vertical, KC.space6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: KC.cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(contender.isWinner ? 0.08 : 0.04))
        )
    }
}

// MARK: - StaleGitdirCard

/// The dropped folder matches nothing, but an account still points at a missing
/// sibling path — the fingerprint of a renamed project. One tap retargets that
/// single path; the secondary button leaves every account alone.
struct StaleGitdirCard: View {
    let candidate: StaleGitdirRepair.Candidate
    var isBusy: Bool = false
    var errorMessage: String? = nil
    let onRetarget: () -> Void
    let onKeepOldPath: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KC.space8) {
            HStack(alignment: .top, spacing: KC.space8) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: candidate.replacementPath.abbreviatedHomePath())
                        .font(KC.heroMeta)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("The old path is gone")
                        .font(KC.rowCaption)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: KC.space8) {
                Circle()
                    .fill(candidate.account.color.color)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(candidate.displayLabel) still points at \(candidate.stalePath.abbreviatedHomePath())")
                        .font(KC.rowCaption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !candidate.account.gitUserEmail.isEmpty {
                        Text(verbatim: candidate.account.gitUserEmail)
                            .font(KC.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, KC.space10)
            .padding(.vertical, KC.space6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: KC.cardCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            HStack(spacing: KC.space6) {
                Button(action: onRetarget) {
                    Text("Point it at this folder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isBusy)

                Button(action: onKeepOldPath) {
                    Text("Keep the old path")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy)
            }
            .font(.system(size: KC.rowSubtitleSize))

            if let errorMessage {
                Text(verbatim: errorMessage)
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
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: KC.heroCornerRadius, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.22), lineWidth: 0.5)
        )
        .padding(.horizontal, KC.space10)
        .padding(.top, KC.space10)
    }
}
