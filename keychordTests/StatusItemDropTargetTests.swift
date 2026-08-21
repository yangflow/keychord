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
