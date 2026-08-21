import AppKit
import SwiftUI

/// Presents the shared ``NSColorPanel`` so the account header marker can
/// open a full system color picker (not a custom swatch row).
@MainActor
final class AccountColorPanelController: NSObject {
    static let shared = AccountColorPanelController()

    private var apply: ((Account.AccountColor) -> Void)?

    private override init() {
        super.init()
    }

    func present(
        initial: Account.AccountColor,
        apply: @escaping (Account.AccountColor) -> Void
    ) {
        self.apply = apply
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(initial.color)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        apply?(Account.AccountColor(nsColor: sender.color))
    }
}

extension Account.AccountColor {
    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(sRGBRed: Double(r), green: Double(g), blue: Double(b))
    }
}
