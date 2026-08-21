import CoreGraphics
import Foundation

/// State and geometry for the one-shot callout that points at the status item on
/// first launch. A menubar-only app leaves nothing on screen, so the first run
/// needs to say where it went — once, and never again.
enum FirstLaunchHint {
    static let shownKey = "keychord.firstLaunchHintShown"

    /// Long enough to read two short lines, short enough that an unattended Mac
    /// is not left with a floating callout.
    static let autoDismissAfter: TimeInterval = 6

    /// The status item exists a moment after launch, so the controller polls
    /// before giving up rather than pointing at nothing.
    static let statusItemWaitAttempts = 30
    static let statusItemWaitInterval: TimeInterval = 0.2

    static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: shownKey)
    }

    static func markShown(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: shownKey)
    }

    /// Callout frame in screen coordinates: hanging under the status item,
    /// centred on it, and pulled back inside `screen` — a status item near the
    /// right edge would otherwise put half the callout off-screen.
    static func calloutFrame(
        anchor: CGRect,
        size: CGSize,
        screen: CGRect,
        gap: CGFloat = 6,
        margin: CGFloat = 8
    ) -> CGRect {
        let maxX = max(screen.minX + margin, screen.maxX - margin - size.width)
        let x = min(max(anchor.midX - size.width / 2, screen.minX + margin), maxX)

        let maxY = max(screen.minY + margin, screen.maxY - margin - size.height)
        let y = min(max(anchor.minY - gap - size.height, screen.minY + margin), maxY)

        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
