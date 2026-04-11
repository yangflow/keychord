import Foundation
import AppKit
#if canImport(Sparkle)
import Sparkle
#endif

/// Wrapper around Sparkle's auto-update controller. Apps that haven't yet
/// added the Sparkle Swift Package Manager dependency get a stub that
/// surfaces a clear "not configured" alert. Apps that have added Sparkle
/// (File → Add Package Dependencies → https://github.com/sparkle-project/Sparkle)
/// get the real updater with zero code changes elsewhere in the project.
///
/// Setup steps for the fully-wired updater:
///   1. Add the Sparkle package to the keychord app target via Xcode.
///   2. Generate an Ed25519 keypair for appcast signing:
///        ./path/to/Sparkle/bin/generate_keys
///      Store the private key in your login keychain; keep the public
///      half to paste into `SUPublicEDKey`.
///   3. Set `INFOPLIST_KEY_SUFeedURL` to the public URL of your
///      `appcast.xml` (e.g. https://ydongy.github.io/keychord/appcast.xml).
///   4. Set `INFOPLIST_KEY_SUPublicEDKey` to the base64 public key from
///      step 2.
///   5. At release time, `scripts/release.sh` signs the new archive with
///      the private key and updates the appcast entry.

#if canImport(Sparkle)

@MainActor
final class UpdaterService: NSObject {
    static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController

    override private init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var canCheck: Bool {
        controller.updater.canCheckForUpdates
    }
}

#else

@MainActor
final class UpdaterService {
    static let shared = UpdaterService()

    private init() {}

    func checkForUpdates() {
        let alert = NSAlert()
        alert.messageText = "Updates not configured"
        alert.informativeText = """
            keychord was built without the Sparkle auto-update framework.

            To enable in-app updates:
              1. Xcode → File → Add Package Dependencies
              2. Paste https://github.com/sparkle-project/Sparkle
              3. Add the `Sparkle` library to the keychord app target
              4. Set SUFeedURL and SUPublicEDKey in Info.plist
              5. Rebuild

            See UpdaterService.swift for the full runbook.
            """
        alert.alertStyle = .informational
        alert.runModal()
    }

    var canCheck: Bool { false }
}

#endif
