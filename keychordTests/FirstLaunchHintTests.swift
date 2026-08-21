import Testing
import CoreGraphics
import Foundation
@testable import keychord

/// #48. The AppKit chrome (glow layer, callout panel) cannot run here; what is
/// covered is the once-only flag and the placement math.
@Suite("FirstLaunchHint")
struct FirstLaunchHintTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "keychord.tests.hint.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func firstLaunchShowsTheHint() {
        let defaults = freshDefaults()
        let shows = FirstLaunchHint.shouldShow(defaults: defaults)
        #expect(shows)
    }

    @Test func markingItShownKeepsEveryLaterLaunchQuiet() {
        let defaults = freshDefaults()
        FirstLaunchHint.markShown(defaults: defaults)

        let shows = FirstLaunchHint.shouldShow(defaults: defaults)
        #expect(!shows)
        // The flag, not a timestamp: reinstalling the same defaults must not
        // let it come back.
        FirstLaunchHint.markShown(defaults: defaults)
        let stillQuiet = FirstLaunchHint.shouldShow(defaults: defaults)
        #expect(!stillQuiet)
    }

    // MARK: - Placement

    private static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private static let size = CGSize(width: 240, height: 52)

    @Test func calloutHangsUnderTheStatusItem() {
        let anchor = CGRect(x: 700, y: 876, width: 24, height: 24)
        let frame = FirstLaunchHint.calloutFrame(
            anchor: anchor,
            size: Self.size,
            screen: Self.screen
        )
        #expect(frame.maxY == anchor.minY - 6)
        #expect(frame.midX == anchor.midX)
        #expect(frame.size == Self.size)
    }

    @Test func statusItemNearTheRightEdgeKeepsTheCalloutOnScreen() {
        let anchor = CGRect(x: 1400, y: 876, width: 24, height: 24)
        let frame = FirstLaunchHint.calloutFrame(
            anchor: anchor,
            size: Self.size,
            screen: Self.screen
        )
        #expect(frame.maxX == Self.screen.maxX - 8)
        #expect(frame.minX < anchor.midX)
    }

    @Test func statusItemNearTheLeftEdgeKeepsTheCalloutOnScreen() {
        let anchor = CGRect(x: 0, y: 876, width: 24, height: 24)
        let frame = FirstLaunchHint.calloutFrame(
            anchor: anchor,
            size: Self.size,
            screen: Self.screen
        )
        #expect(frame.minX == Self.screen.minX + 8)
    }

    @Test func aScreenTooShortForTheCalloutStillPlacesItInside() {
        let screen = CGRect(x: 0, y: 0, width: 400, height: 40)
        let anchor = CGRect(x: 0, y: 20, width: 24, height: 24)
        let frame = FirstLaunchHint.calloutFrame(
            anchor: anchor,
            size: Self.size,
            screen: screen
        )
        #expect(frame.minY == screen.minY + 8)
        #expect(frame.minX == screen.minX + 8)
    }

    @Test func placementRespectsANonZeroScreenOrigin() {
        // Second display to the right of the main one.
        let screen = CGRect(x: 1440, y: 0, width: 1280, height: 800)
        let anchor = CGRect(x: 1445, y: 776, width: 24, height: 24)
        let frame = FirstLaunchHint.calloutFrame(
            anchor: anchor,
            size: Self.size,
            screen: screen
        )
        #expect(frame.minX == screen.minX + 8)
        #expect(frame.maxY == anchor.minY - 6)
    }
}
