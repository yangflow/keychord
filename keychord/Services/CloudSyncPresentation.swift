import Foundation

/// Pure presentation flags for `CloudSyncView`.
/// Unit-testable without hosting SwiftUI or touching real iCloud APIs.
struct CloudSyncPresentation: Equatable, Sendable {
    let isCapabilityAvailable: Bool
    /// Raw user preference (may be true even when entitlement is missing).
    let preferenceEnabled: Bool
    let syncState: CloudSyncService.SyncState

    /// Toggle visual "on" — never true when the entitlement is unavailable.
    var showsToggleAsOn: Bool {
        isCapabilityAvailable && preferenceEnabled
    }

    var isToggleDisabled: Bool {
        !isCapabilityAvailable
    }

    var showsRequiresSignedBuildMessage: Bool {
        !isCapabilityAvailable
    }

    var showsSyncNow: Bool {
        showsToggleAsOn
    }

    /// Green / "synced" status must not appear when capability is missing.
    var displaysAsSynced: Bool {
        guard isCapabilityAvailable else { return false }
        if case .synced = syncState { return true }
        return false
    }

    static func from(
        availability: ICloudAvailability,
        preferenceEnabled: Bool,
        syncState: CloudSyncService.SyncState
    ) -> CloudSyncPresentation {
        CloudSyncPresentation(
            isCapabilityAvailable: availability.isAvailable,
            preferenceEnabled: preferenceEnabled,
            syncState: syncState
        )
    }
}
