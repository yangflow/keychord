import AppKit

/// Hover state of the status item during a folder drag. Kept as a value type so
/// the transitions are testable without a live drag session.
struct StatusItemDropHighlight: Equatable, Sendable {
    private(set) var isActive = false

    /// Returns true when the visual state changed and a redraw is needed.
    @discardableResult
    mutating func dragUpdated(acceptsDrop: Bool) -> Bool {
        guard isActive != acceptsDrop else { return false }
        isActive = acceptsDrop
        return true
    }

    @discardableResult
    mutating func dragEnded() -> Bool {
        guard isActive else { return false }
        isActive = false
        return true
    }
}

/// Transparent overlay on the menu-bar status-item button that accepts
/// folder drops from Finder while forwarding clicks to the button underneath.
///
/// While a folder hovers, it draws a ring and a soft glow around the existing
/// icon. The symbol itself is never swapped — the menu bar keeps showing the
/// same glyph, just visibly armed.
final class StatusItemFolderDropView: NSView {
    var onFolderURLs: (([URL]) -> Void)?

    private var highlight = StatusItemDropHighlight()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Drag highlight

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard highlight.isActive else { return }

        let ringRect = bounds.insetBy(dx: 1.5, dy: 1.5)
        guard ringRect.width > 2, ringRect.height > 2 else { return }
        let radius = min(6, ringRect.height / 3)
        let ring = NSBezierPath(roundedRect: ringRect, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        // Tint follows the user's accent so the armed state matches the system.
        let accent = NSColor.controlAccentColor
        accent.withAlphaComponent(0.18).setFill()
        ring.fill()

        let shadow = NSShadow()
        shadow.shadowColor = accent.withAlphaComponent(0.75)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = .zero
        shadow.set()

        accent.setStroke()
        ring.lineWidth = 1.5
        ring.setLineDash([3, 2], count: 2, phase: 0)
        ring.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func setHighlighted(_ isHighlighted: Bool) {
        if highlight.dragUpdated(acceptsDrop: isHighlighted) {
            needsDisplay = true
        }
    }

    private func clearHighlight() {
        if highlight.dragEnded() {
            needsDisplay = true
        }
    }

    // MARK: - Click through to NSStatusBarButton

    override func mouseDown(with event: NSEvent) {
        superview?.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        superview?.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        superview?.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        superview?.otherMouseDown(with: event)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepts = !folderURLs(from: sender).isEmpty
        setHighlighted(accepts)
        return accepts ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepts = !folderURLs(from: sender).isEmpty
        setHighlighted(accepts)
        return accepts ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearHighlight()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        clearHighlight()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !folderURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        clearHighlight()
        let folders = folderURLs(from: sender)
        guard !folders.isEmpty else { return false }
        onFolderURLs?(folders)
        return true
    }

    /// Testable filter used by the pasteboard path.
    static func folderURLs(fromFileURLs urls: [URL]) -> [URL] {
        urls.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                && isDir.boolValue
        }
    }

    private func folderURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] else {
            return []
        }
        return Self.folderURLs(fromFileURLs: urls)
    }
}
