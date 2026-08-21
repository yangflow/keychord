import Foundation

/// Whether the popover's Doctor section shows its details, and when that
/// decision may be revisited.
///
/// A healthy machine gets one collapsed “everything checks out” row. A new set
/// of diagnoses opens itself, because a warning nobody expands is a warning
/// nobody reads — but once the user collapses a set, refreshing the same set
/// must not fight them.
enum DoctorPresentation {

    /// Identity of a diagnosis set, stable across refreshes that find the same
    /// problems.
    static func signature(of diagnoses: [Diagnosis]) -> String {
        diagnoses.map(\.id).sorted().joined(separator: "|")
    }

    /// Expansion state after a Doctor run.
    ///
    /// - `previousSignature`: signature the last run produced.
    /// - `wasExpanded`: what the section shows right now.
    static func shouldExpand(
        diagnoses: [Diagnosis],
        previousSignature: String,
        wasExpanded: Bool
    ) -> Bool {
        guard !diagnoses.isEmpty else { return false }
        let current = signature(of: diagnoses)
        // Same findings as before: respect whatever the user last chose.
        guard current != previousSignature else { return wasExpanded }
        return true
    }
}
