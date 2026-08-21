import Testing
import Foundation
@testable import keychord

@Suite("AppStateCurrentRepoMatch")
@MainActor
struct AppStateCurrentRepoMatchTests {

    @Test func clearAccountMatchResetsToNil() async {
        let store = AccountsStore(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("keychord-match-\(UUID().uuidString).json"),
            autoLoad: false
        )
        let state = AppState(accountsStore: store)
        state.accountMatch = .notARepo(path: "/tmp/example")
        #expect(state.accountMatch != nil)

        state.clearAccountMatch()
        #expect(state.accountMatch == nil)
    }

    @Test func suppressAccountMatchClearDefaultsFalse() {
        let state = AppState(
            accountsStore: AccountsStore(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("keychord-flag-\(UUID().uuidString).json"),
                autoLoad: false
            )
        )
        #expect(state.suppressAccountMatchClear == false)
    }
}
