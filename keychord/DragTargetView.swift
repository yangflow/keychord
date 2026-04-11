import AppKit

/// Invisible NSView subview installed over NSStatusItem.button so the
/// menubar icon can both fire on click and accept a dropped file URL.
/// NSStatusItem.button is fixed — we cannot subclass it — but we can
/// place this view on top and intercept events at the responder level.
final class DragTargetView: NSView {
    var onDrop: ((URL) -> Void)?
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }

    // MARK: - Drag destination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        containsFileURL(in: sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        containsFileURL(in: sender) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: nil
              ) as? [URL],
              let url = urls.first else {
            return false
        }
        onDrop?(url)
        return true
    }

    private func containsFileURL(in info: any NSDraggingInfo) -> Bool {
        info.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: nil
        )
    }
}
