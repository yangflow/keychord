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

    // MARK: - Unbind

    @Test func unbindRemovesOnlyTheFoldersOwnEntry() {
        let home = NSHomeDirectory()
        let account = Self.account(scope: .gitdir(paths: ["~/work/", "~/src/new-app/"]))
        let result = GitdirBinder.unbind(folderPath: "\(home)/src/new-app", from: account)

        #expect(result.outcome == .removed(path: "~/src/new-app/"))
        #expect(result.changedScope)
        #expect(result.account.scope.directories == ["~/work/"])
    }

    @Test func unbindLeavesAParentScopeAlone() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-unbind-\(UUID().uuidString)")
        let child = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let account = Self.account(scope: .gitdir(root.path + "/"))
        let result = GitdirBinder.unbind(folderPath: child.path, from: account)

        #expect(result.outcome == .notBoundExactly)
        #expect(!result.changedScope)
        #expect(result.account.scope.directories == [root.path + "/"])
    }

    @Test func unbindingTheLastPathKeepsTheAccountScopedNotGlobal() {
        let home = NSHomeDirectory()
        let account = Self.account(scope: .gitdir("~/work/"))
        let result = GitdirBinder.unbind(folderPath: "\(home)/work", from: account)

        #expect(result.changedScope)
        #expect(result.account.scope.directories.isEmpty)
        // Going global here would silently claim every other repository.
        #expect(result.account.scope != .global)
        #expect(result.account.scope.isScoped)
    }

    @Test func exactPathIgnoresParentsAndBlanks() {
        let scope = Account.Scope.gitdir(paths: ["", "~/work/", "~/src/new-app/"])
        #expect(
            GitdirBinder.exactPath(
                forFolderPath: "\(NSHomeDirectory())/src/new-app",
                in: scope
            ) == "~/src/new-app/"
        )
        #expect(
            GitdirBinder.exactPath(
                forFolderPath: "\(NSHomeDirectory())/work/api",
                in: scope
            ) == nil
        )
        #expect(GitdirBinder.exactPath(forFolderPath: "  ", in: scope) == nil)
        #expect(GitdirBinder.exactPath(forFolderPath: "~/work/", in: .global) == nil)
    }

    @Test func unbindThenBindMovesAFolderBetweenAccounts() {
        let home = NSHomeDirectory()
        let from = Self.account(scope: .gitdir(paths: ["~/work/", "~/src/new-app/"]))
        var to = Self.account(scope: .global)
        to.label = "personal"

        let removal = GitdirBinder.unbind(folderPath: "\(home)/src/new-app", from: from)
        let addition = GitdirBinder.bind(folderPath: "\(home)/src/new-app", to: to)

        #expect(removal.account.scope.directories == ["~/work/"])
        #expect(addition.account.scope.directories == ["~/src/new-app/"])
    }

    // MARK: - Invalid input

    @Test func blankFolderPathIsRejected() {
        let result = GitdirBinder.bind(folderPath: "   ", to: Self.account())
        #expect(result.outcome == .invalidPath)
        #expect(!result.changedScope)
        #expect(result.account.scope == .global)
    }
}
