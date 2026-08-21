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

@Suite("StatusItemDropHighlight")
struct StatusItemDropHighlightTests {

    @Test func startsIdle() {
        #expect(!StatusItemDropHighlight().isActive)
    }

    @Test func hoveringAFolderArmsTheIcon() {
        var highlight = StatusItemDropHighlight()
        #expect(highlight.dragUpdated(acceptsDrop: true))
        #expect(highlight.isActive)
    }

    @Test func hoveringSomethingWeCannotAcceptStaysIdle() {
        var highlight = StatusItemDropHighlight()
        #expect(!highlight.dragUpdated(acceptsDrop: false))
        #expect(!highlight.isActive)
    }

    @Test func repeatedUpdatesDoNotAskForARedraw() {
        var highlight = StatusItemDropHighlight()
        #expect(highlight.dragUpdated(acceptsDrop: true))
        // `draggingUpdated` fires continuously while the pointer moves.
        #expect(!highlight.dragUpdated(acceptsDrop: true))
        #expect(highlight.isActive)
    }

    @Test func leavingTheIconDisarmsIt() {
        var highlight = StatusItemDropHighlight()
        highlight.dragUpdated(acceptsDrop: true)
        #expect(highlight.dragEnded())
        #expect(!highlight.isActive)
        // Ending twice (exit + ended) must not request a second redraw.
        #expect(!highlight.dragEnded())
    }

    @Test func rejectedHoverAfterAnAcceptedOneDisarms() {
        var highlight = StatusItemDropHighlight()
        highlight.dragUpdated(acceptsDrop: true)
        #expect(highlight.dragUpdated(acceptsDrop: false))
        #expect(!highlight.isActive)
    }
}
