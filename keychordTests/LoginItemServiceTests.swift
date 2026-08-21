import Testing
import Foundation
@testable import keychord

/// In-memory stand-in for ``SMAppService.mainApp`` — no real login-item writes.
@MainActor
final class FakeLoginItemService: LoginItemManaging {
    var isEnabled: Bool
    var requiresApproval: Bool
    var setEnabledError: Error?
    /// When set, after a successful `setEnabled(true)` the service reports this
    /// instead of staying enabled — simulates requiresApproval / notFound.
    var statusAfterSuccessfulEnable: PostEnableStatus?
    private(set) var setEnabledCalls: [Bool] = []

    enum PostEnableStatus {
        case requiresApproval
        case notEnabled
    }

    init(isEnabled: Bool = false, requiresApproval: Bool = false) {
        self.isEnabled = isEnabled
        self.requiresApproval = requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)
        if let setEnabledError {
            throw setEnabledError
        }
        if enabled, let statusAfterSuccessfulEnable {
            switch statusAfterSuccessfulEnable {
            case .requiresApproval:
                isEnabled = false
                requiresApproval = true
                throw LoginItemServiceError.requiresApproval
            case .notEnabled:
                isEnabled = false
                requiresApproval = false
                throw LoginItemServiceError.registrationDidNotEnable
            }
        }
        isEnabled = enabled
        if !enabled {
            requiresApproval = false
        }
    }
}

@Suite("LoginItemController")
@MainActor
struct LoginItemControllerTests {

    @Test func refreshReportsServiceStatus() {
        let fake = FakeLoginItemService(isEnabled: true, requiresApproval: false)
        let controller = LoginItemController(service: fake)
        #expect(controller.isEnabled)
        #expect(controller.requiresApproval == false)

        fake.isEnabled = false
        fake.requiresApproval = true
        controller.refresh()
        #expect(controller.isEnabled == false)
        #expect(controller.requiresApproval)
    }

    @Test func setEnabledSuccessClearsErrorAndMatchesService() {
        let fake = FakeLoginItemService(isEnabled: false)
        let controller = LoginItemController(service: fake)
        controller.lastErrorMessage = "stale"

        controller.setEnabled(true)

        #expect(fake.setEnabledCalls == [true])
        #expect(controller.isEnabled)
        #expect(controller.lastErrorMessage == nil)
    }

    @Test func setEnabledAPIFailureSurfacesErrorAndDoesNotLie() {
        let fake = FakeLoginItemService(isEnabled: false)
        fake.setEnabledError = LoginItemServiceError.underlying("register failed")
        let controller = LoginItemController(service: fake)

        controller.setEnabled(true)

        #expect(controller.isEnabled == false)
        #expect(controller.lastErrorMessage == "register failed")
    }

    @Test func requiresApprovalLeavesToggleOffWithMessage() {
        let fake = FakeLoginItemService(isEnabled: false)
        fake.statusAfterSuccessfulEnable = .requiresApproval
        let controller = LoginItemController(service: fake)

        controller.setEnabled(true)

        #expect(controller.isEnabled == false)
        #expect(controller.requiresApproval)
        #expect(
            controller.lastErrorMessage
                == LoginItemServiceError.requiresApproval.errorDescription
        )
    }

    @Test func registrationDidNotEnableLeavesToggleOff() {
        let fake = FakeLoginItemService(isEnabled: false)
        fake.statusAfterSuccessfulEnable = .notEnabled
        let controller = LoginItemController(service: fake)

        controller.setEnabled(true)

        #expect(controller.isEnabled == false)
        #expect(
            controller.lastErrorMessage
                == LoginItemServiceError.registrationDidNotEnable.errorDescription
        )
    }

    @Test func unregisterSuccessTurnsOff() {
        let fake = FakeLoginItemService(isEnabled: true)
        let controller = LoginItemController(service: fake)

        controller.setEnabled(false)

        #expect(fake.setEnabledCalls == [false])
        #expect(controller.isEnabled == false)
        #expect(controller.lastErrorMessage == nil)
    }

    @Test func unregisterFailureKeepsPriorStatusAndShowsError() {
        let fake = FakeLoginItemService(isEnabled: true)
        fake.setEnabledError = LoginItemServiceError.underlying("unregister failed")
        let controller = LoginItemController(service: fake)

        controller.setEnabled(false)

        #expect(controller.isEnabled)
        #expect(controller.lastErrorMessage == "unregister failed")
    }
}

@Suite("LoginItemServiceError")
struct LoginItemServiceErrorTests {

    @Test func localizedDescriptionsAreNonEmpty() {
        #expect(!(LoginItemServiceError.requiresApproval.errorDescription ?? "").isEmpty)
        #expect(!(LoginItemServiceError.registrationDidNotEnable.errorDescription ?? "").isEmpty)
        #expect(LoginItemServiceError.underlying("boom").errorDescription == "boom")
    }
}
