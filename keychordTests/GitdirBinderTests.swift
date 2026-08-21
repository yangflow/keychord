import Testing
import Foundation
@testable import keychord

@Suite("GitdirBinder")
struct GitdirBinderTests {

    static func account(scope: Account.Scope = .global) -> Account {
        Account.new(
            label: "work",
            sshAlias: "github-work",
            keyPath: "~/.ssh/id_work",
            gitUserName: "Work",
            gitUserEmail: "work@example.com",
            scope: scope,
            color: .blue
        )
    }

    // MARK: - Global → scoped

    @Test func bindingGlobalAccountCreatesFirstPath() {
        let home = NSHomeDirectory()
        let result = GitdirBinder.bind(folderPath: "\(home)/src/new-app", to: Self.account())

        #expect(result.outcome == .added(path: "~/src/new-app/"))
        #expect(result.changedScope)
        #expect(result.account.scope.directories == ["~/src/new-app/"])
    }

    @Test func bindingNormalizesTrailingSlashAndHome() {
        let home = NSHomeDirectory()
        let result = GitdirBinder.bind(folderPath: "  \(home)/work  ", to: Self.account())
        #expect(result.account.scope.directories == ["~/work/"])
    }

    @Test func bindingKeepsPathsOutsideHomeAbsolute() {
        let result = GitdirBinder.bind(folderPath: "/opt/repos/app", to: Self.account())
        #expect(result.account.scope.directories == ["/opt/repos/app/"])
    }

    // MARK: - Adding, never replacing

    @Test func bindingAppendsToAnExistingScope() {
        let existing = Self.account(scope: .gitdir("~/work/"))
        let result = GitdirBinder.bind(folderPath: "\(NSHomeDirectory())/src/new-app", to: existing)

        #expect(result.changedScope)
        #expect(result.account.scope.directories == ["~/work/", "~/src/new-app/"])
    }

    @Test func bindingPreservesEveryPreviousPath() {
        let existing = Self.account(scope: .gitdir(paths: ["~/work/", "/opt/repos/"]))
        let result = GitdirBinder.bind(folderPath: "\(NSHomeDirectory())/side", to: existing)
        #expect(result.account.scope.directories.count == 3)
        #expect(result.account.scope.directories.starts(with: ["~/work/", "/opt/repos/"]))
    }

    // MARK: - Already covered

    @Test func bindingChildOfExistingScopeIsANoOp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-bind-\(UUID().uuidString)")
        let child = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let existing = Self.account(scope: .gitdir(root.path + "/"))
        let result = GitdirBinder.bind(folderPath: child.path, to: existing)

        #expect(!result.changedScope)
        #expect(result.account.scope.directories == existing.scope.directories)
        if case .alreadyCovered(let by) = result.outcome {
            #expect(by == root.path + "/")
        } else {
            Issue.record("Expected .alreadyCovered, got \(result.outcome)")
        }
    }

    @Test func coveringPathPrefersTheMostSpecificParent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-cover-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("client/project")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let scope = Account.Scope.gitdir(paths: [
            root.path + "/",
            root.path + "/client/",
        ])
        let covering = GitdirBinder.coveringPath(forFolderPath: nested.path, in: scope)
        #expect(covering == root.path + "/client/")
    }

    @Test func coveringPathIgnoresBlankEntries() {
        let scope = Account.Scope.gitdir(paths: ["", "   "])
        #expect(GitdirBinder.coveringPath(forFolderPath: "/tmp/repo", in: scope) == nil)
    }

    // MARK: - Invalid input

    @Test func blankFolderPathIsRejected() {
        let result = GitdirBinder.bind(folderPath: "   ", to: Self.account())
        #expect(result.outcome == .invalidPath)
        #expect(!result.changedScope)
        #expect(result.account.scope == .global)
    }
}
