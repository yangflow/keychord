import Foundation

/// Display order for identity lists: most recently used first, so the one or
/// two accounts someone actually works with stay at the top instead of sitting
/// wherever they happened to be added.
enum AccountOrdering {

    /// `lastUsedAt` descending, then label (case-insensitive), then creation
    /// date. Accounts that have never been used sort after every used one
    /// rather than pretending to be the oldest.
    static func byLastUsed(_ accounts: [Account]) -> [Account] {
        accounts.sorted(by: isOrderedBefore)
    }

    static func isOrderedBefore(_ lhs: Account, _ rhs: Account) -> Bool {
        switch (lhs.lastUsedAt, rhs.lastUsedAt) {
        case (let left?, let right?):
            if left != right { return left > right }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        let leftLabel = lhs.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightLabel = rhs.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if leftLabel.caseInsensitiveCompare(rightLabel) != .orderedSame {
            // Unnamed accounts keep their place at the end of an equal group.
            if leftLabel.isEmpty != rightLabel.isEmpty { return !leftLabel.isEmpty }
            return leftLabel.caseInsensitiveCompare(rightLabel) == .orderedAscending
        }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
