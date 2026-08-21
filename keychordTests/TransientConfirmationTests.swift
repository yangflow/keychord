import Testing
import Foundation
@testable import keychord

@Suite("TransientConfirmation")
@MainActor
struct TransientConfirmationTests {

    @Test func startsHidden() {
        #expect(!TransientConfirmation().isShowing)
    }

    @Test func flashShowsImmediately() {
        let confirmation = TransientConfirmation(duration: .seconds(60))
        confirmation.flash()
        #expect(confirmation.isShowing)
    }

    @Test func flashRevertsItselfAfterTheWindow() async throws {
        let confirmation = TransientConfirmation(duration: .milliseconds(40))
        confirmation.flash()
        #expect(confirmation.isShowing)

        try await Task.sleep(for: .milliseconds(300))
        #expect(!confirmation.isShowing)
    }

    @Test func backToBackFlashesRestartTheWindowInsteadOfStacking() async throws {
        let confirmation = TransientConfirmation(duration: .milliseconds(120))
        confirmation.flash()
        try await Task.sleep(for: .milliseconds(60))
        confirmation.flash()

        // The first timer must not clear the second flash early.
        try await Task.sleep(for: .milliseconds(90))
        #expect(confirmation.isShowing)

        try await Task.sleep(for: .milliseconds(250))
        #expect(!confirmation.isShowing)
    }

    @Test func resetHidesItRightAway() {
        let confirmation = TransientConfirmation(duration: .seconds(60))
        confirmation.flash()
        confirmation.reset()
        #expect(!confirmation.isShowing)
    }

    @Test func resetAfterFlashStopsThePendingTimer() async throws {
        let confirmation = TransientConfirmation(duration: .milliseconds(40))
        confirmation.flash()
        confirmation.reset()
        confirmation.flash()

        // The cancelled first timer must not hide the new flash.
        try await Task.sleep(for: .milliseconds(20))
        #expect(confirmation.isShowing)
    }

    @Test func defaultWindowIsAboutASecond() {
        // “~1s” per the issue: long enough to read, short enough to be a flash.
        #expect(TransientConfirmation.defaultDuration >= .milliseconds(800))
        #expect(TransientConfirmation.defaultDuration <= .seconds(2))
    }
}
