import Testing
import Foundation
@testable import keychord

@Suite("MenuBarStatusItemLocator")
struct MenuBarStatusItemLocatorTests {
    @Test func statusItemClassNameMatchesOSGeneration() {
        let name = MenuBarStatusItemLocator.statusItemClassName
        if #available(macOS 26.0, *) {
            #expect(name == "NSSceneStatusItem")
        } else {
            #expect(name == "NSStatusItem")
        }
    }
}

@Suite("StatusItemFolderDropView")
struct StatusItemFolderDropFilteringTests {
    @Test func acceptsDirectoriesOnly() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("file.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        let folders = StatusItemFolderDropView.folderURLs(fromFileURLs: [tmp, file])
        #expect(folders == [tmp])
    }
}

/// `dragUpdated` / `dragEnded` mutate, and `#expect` rebinds the receiver of a
/// bare call to an immutable `$0`, so every transition is taken on a `var` first
/// and the returned “needs a redraw” flag is asserted afterwards.
@Suite("StatusItemDropHighlight")
struct StatusItemDropHighlightTests {

    @Test func startsIdle() {
        #expect(!StatusItemDropHighlight().isActive)
    }

    @Test func hoveringAFolderArmsTheIcon() {
        var highlight = StatusItemDropHighlight()
        let needsRedraw = highlight.dragUpdated(acceptsDrop: true)
        #expect(needsRedraw)
        #expect(highlight.isActive)
    }

    @Test func hoveringSomethingWeCannotAcceptStaysIdle() {
        var highlight = StatusItemDropHighlight()
        let needsRedraw = highlight.dragUpdated(acceptsDrop: false)
        #expect(!needsRedraw)
        #expect(!highlight.isActive)
    }

    @Test func repeatedUpdatesDoNotAskForARedraw() {
        var highlight = StatusItemDropHighlight()
        let armed = highlight.dragUpdated(acceptsDrop: true)
        // `draggingUpdated` fires continuously while the pointer moves.
        let again = highlight.dragUpdated(acceptsDrop: true)
        #expect(armed)
        #expect(!again)
        #expect(highlight.isActive)
    }

    @Test func leavingTheIconDisarmsIt() {
        var highlight = StatusItemDropHighlight()
        highlight.dragUpdated(acceptsDrop: true)

        let disarmed = highlight.dragEnded()
        // Ending twice (exit + ended) must not request a second redraw.
        let secondEnd = highlight.dragEnded()

        #expect(disarmed)
        #expect(!secondEnd)
        #expect(!highlight.isActive)
    }

    @Test func rejectedHoverAfterAnAcceptedOneDisarms() {
        var highlight = StatusItemDropHighlight()
        highlight.dragUpdated(acceptsDrop: true)
        let needsRedraw = highlight.dragUpdated(acceptsDrop: false)
        #expect(needsRedraw)
        #expect(!highlight.isActive)
    }
}
