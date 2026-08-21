import AppKit

/// Soft accent glow drawn around the existing status-bar symbol. Same optics as
/// the drag highlight (#37) — a tinted rounded rect with a halo — but solid
/// instead of dashed, and pulsing, because this one is a one-shot “look here”
/// rather than a drop target.
///
/// The symbol underneath is never replaced, and the view is click-through, so
/// the status item keeps behaving exactly as it does without the hint.
final class StatusItemHintGlowView: NSView {
    private let glow = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let host = CALayer()
        host.masksToBounds = false
        layer = host
        wantsLayer = true

        let accent = NSColor.controlAccentColor
        glow.fillColor = accent.withAlphaComponent(0.16).cgColor
        glow.strokeColor = accent.withAlphaComponent(0.85).cgColor
        glow.lineWidth = 1.5
        glow.shadowColor = accent.cgColor
        glow.shadowOpacity = 0.7
        glow.shadowRadius = 5
        glow.shadowOffset = .zero
        host.addSublayer(glow)
        updateGlowPath()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Clicks and folder drags belong to the button and its drop overlay.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        updateGlowPath()
    }

    /// The status item is a fixed-size button, but it is resized once while
    /// `MenuBarExtra` settles, so the ring is recomputed rather than cached.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateGlowPath()
    }

    private func updateGlowPath() {
        let ring = bounds.insetBy(dx: 1.5, dy: 1.5)
        guard ring.width > 2, ring.height > 2 else {
            glow.path = nil
            return
        }
        let radius = min(6, ring.height / 3)
        glow.frame = bounds
        glow.path = CGPath(
            roundedRect: ring,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }

    /// Breathes the glow so the eye catches it. Reduce Motion gets the same
    /// glow, held steady.
    func startPulsing(reduceMotion: Bool) {
        guard !reduceMotion else {
            glow.opacity = 1
            return
        }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .greatestFiniteMagnitude
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(pulse, forKey: "keychord.hintPulse")
    }

    func stopPulsing() {
        glow.removeAnimation(forKey: "keychord.hintPulse")
    }
}
