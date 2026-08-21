import Testing
import Foundation
@testable import keychord

@Suite("ICloudAvailability")
struct ICloudAvailabilityTests {

    @Test func missingEntitlementsIsUnavailable() {
        #expect(ICloudAvailability.detect(entitlements: nil) == false)
        #expect(ICloudAvailability.detect(entitlements: [:]) == false)
    }

    @Test func kvStoreEntitlementIsAvailableWithoutContainer() {
        let entitlements: [String: Any] = [
            "com.apple.developer.ubiquity-kvstore-identifier":
                "$(TeamIdentifierPrefix)com.example.keychord"
        ]
        #expect(ICloudAvailability.detect(entitlements: entitlements))
        #expect(ICloudAvailability.hasICloudEntitlement(entitlements))
    }

    @Test func containerEntitlementNeedsContainerOrIdentity() {
        let entitlements: [String: Any] = [
            "com.apple.developer.ubiquity-container-identifiers":
                ["iCloud.com.example.keychord"]
        ]
        #expect(ICloudAvailability.hasICloudEntitlement(entitlements))
        #expect(
            ICloudAvailability.detect(
                entitlements: entitlements,
                ubiquityContainerURL: nil,
                hasUbiquityIdentity: false
            ) == false
        )
        #expect(
            ICloudAvailability.detect(
                entitlements: entitlements,
                ubiquityContainerURL: URL(fileURLWithPath: "/tmp/ubiquity"),
                hasUbiquityIdentity: false
            )
        )
        #expect(
            ICloudAvailability.detect(
                entitlements: entitlements,
                ubiquityContainerURL: nil,
                hasUbiquityIdentity: true
            )
        )
    }

    @Test func fixedUnavailableFlag() {
        #expect(ICloudAvailability.fixed(false).isAvailable == false)
        #expect(ICloudAvailability.fixed(true).isAvailable)
    }
}

@Suite("CloudSyncPresentation")
@MainActor
struct CloudSyncPresentationTests {

    @Test func unavailableCannotShowEnabledOnOrSynced() {
        let presentation = CloudSyncPresentation.from(
            availability: .fixed(false),
            preferenceEnabled: true,
            syncState: .synced(Date())
        )

        #expect(presentation.isCapabilityAvailable == false)
        #expect(presentation.showsToggleAsOn == false)
        #expect(presentation.isToggleDisabled)
        #expect(presentation.showsRequiresSignedBuildMessage)
        #expect(presentation.showsSyncNow == false)
        #expect(presentation.displaysAsSynced == false)
    }

    @Test func availablePreferenceOffIsOffNotSynced() {
        let presentation = CloudSyncPresentation.from(
            availability: .fixed(true),
            preferenceEnabled: false,
            syncState: .idle
        )

        #expect(presentation.showsToggleAsOn == false)
        #expect(presentation.isToggleDisabled == false)
        #expect(presentation.showsRequiresSignedBuildMessage == false)
        #expect(presentation.displaysAsSynced == false)
    }

    @Test func availablePreferenceOnCanShowSynced() {
        let presentation = CloudSyncPresentation.from(
            availability: .fixed(true),
            preferenceEnabled: true,
            syncState: .synced(Date())
        )

        #expect(presentation.showsToggleAsOn)
        #expect(presentation.showsSyncNow)
        #expect(presentation.displaysAsSynced)
        #expect(presentation.showsRequiresSignedBuildMessage == false)
    }
}

@Suite("CloudSyncService availability")
@MainActor
struct CloudSyncServiceAvailabilityTests {

    @Test func unavailableForcesIsEnabledOffEvenWithStoredPreference() {
        let sync = CloudSyncService(
            availability: .fixed(false),
            enabledPreference: true
        )

        #expect(sync.storedIsEnabled)
        #expect(sync.isEnabled == false)
        #expect(sync.state == .idle)
        #expect(sync.presentation.showsToggleAsOn == false)
        #expect(sync.presentation.displaysAsSynced == false)
    }

    @Test func unavailableIgnoresEnableAttempts() {
        let sync = CloudSyncService(
            availability: .fixed(false),
            enabledPreference: false
        )
        sync.isEnabled = true
        #expect(sync.storedIsEnabled == false)
        #expect(sync.isEnabled == false)
    }

    @Test func unavailableActivateDoesNotLeaveSyncedState() {
        let sync = CloudSyncService(
            availability: .fixed(false),
            enabledPreference: true
        )
        sync.activate()
        #expect(sync.state == .idle)
        #expect(sync.presentation.displaysAsSynced == false)
    }

    @Test func availableRespectsPreference() {
        let sync = CloudSyncService(
            availability: .fixed(true),
            enabledPreference: true
        )
        #expect(sync.isEnabled)
        #expect(sync.presentation.showsToggleAsOn)
    }
}
