import Testing
import Foundation
@testable import keychord

@Suite("StaleGitdirRepair")
struct StaleGitdirRepairTests {

    static func account(label: String, paths: [String]) -> Account {
        Account.new(
            label: label,
            sshAlias: "github-\(label)",
            keyPath: "~/.ssh/id_\(label)",
            gitUserName: label,
            gitUserEmail: "\(label)@example.com",
            scope: .gitdir(paths: paths)
        )
    }

    /// Everything is missing except the paths listed as present.
    static func exists(_ present: [String]) -> (String) -> Bool {
        let expanded = Set(present.map { ConfigStore.expand($0) })
        return { path in expanded.contains(path) }
    }

    // MARK: - Candidate

    @Test func renamedSiblingFolderIsOffered() throws {
        let work = Self.account(label: "work", paths: ["~/src/old-app/"])
        let candidate = try #require(
            StaleGitdirRepair.candidate(
                forDroppedFolder: "\(NSHomeDirectory())/src/renamed-app",
                accounts: [work],
                directoryExists: Self.exists([])
            )
        )
        #expect(candidate.account.id == work.id)
        #expect(candidate.stalePath == "~/src/old-app/")
        #expect(candidate.replacementPath == "~/src/renamed-app/")
        #expect(candidate.displayLabel == "work")
    }

    @Test func pathThatStillExistsIsNeverStale() {
        let work = Self.account(label: "work", paths: ["~/src/old-app/"])
        #expect(
            StaleGitdirRepair.candidate(
                forDroppedFolder: "\(NSHomeDirectory())/src/renamed-app",
                accounts: [work],
                directoryExists: Self.exists(["~/src/old-app/"])
            ) == nil
        )
    }

    @Test func missingPathInAnotherParentIsNotOffered() {
        let work = Self.account(label: "work", paths: ["~/elsewhere/old-app/"])
        #expect(
            StaleGitdirRepair.candidate(
                forDroppedFolder: "\(NSHomeDirectory())/src/renamed-app",
                accounts: [work],
                directoryExists: Self.exists([])
            ) == nil
        )
    }

    @Test func pathAlreadyPointingAtTheDroppedFolderIsNotStale() {
        let work = Self.account(label: "work", paths: ["~/src/renamed-app/"])
        #expect(
            StaleGitdirRepair.candidate(
                forDroppedFolder: "\(NSHomeDirectory())/src/renamed-app",
                accounts: [work],
                directoryExists: Self.exists([])
            ) == nil
        )
    }

    @Test func suggestionIsDeterministicAcrossAccounts() throws {
        let first = Self.account(label: "first", paths: ["~/src/a-app/"])
        let second = Self.account(label: "second", paths: ["~/src/b-app/"])
        for _ in 0..<3 {
            let candidate = try #require(
                StaleGitdirRepair.candidate(
                    forDroppedFolder: "\(NSHomeDirectory())/src/renamed-app",
                    accounts: [first, second],
                    directoryExists: Self.exists([])
                )
            )
            #expect(candidate.account.id == first.id)
            #expect(candidate.stalePath == "~/src/a-app/")
        }
    }

    @Test func homeRootScopeIsNeverTreatedAsStale() {
        let personal = Self.account(label: "personal", paths: ["~/"])
        #expect(
            StaleGitdirRepair.candidate(
                forDroppedFolder: "\(NSHomeDirectory())/src/renamed-app",
                accounts: [personal],
                directoryExists: Self.exists([])
            ) == nil
        )
    }

    // MARK: - Repair

    @Test func repairReplacesOnlyTheStalePath() throws {
        let work = Self.account(
            label: "work",
            paths: ["~/work/", "~/src/old-app/", "/opt/repos/"]
        )
        let candidate = try #require(
            StaleGitdirRepair.candidate(
                forDroppedFolder: "\(NSHomeDirectory())/src/renamed-app",
                accounts: [work],
                directoryExists: Self.exists(["~/work/", "/opt/repos/"])
            )
        )
        let repaired = StaleGitdirRepair.repair(candidate)
        #expect(repaired.scope.directories == ["~/work/", "~/src/renamed-app/", "/opt/repos/"])
        #expect(repaired.id == work.id)
    }

    @Test func repairDropsTheDeadPathWhenTheNewOneIsAlreadyScoped() {
        let work = Self.account(
            label: "work",
            paths: ["~/src/old-app/", "~/src/renamed-app/"]
        )
        let candidate = StaleGitdirRepair.Candidate(
            account: work,
            stalePath: "~/src/old-app/",
            replacementPath: "~/src/renamed-app/"
        )
        let repaired = StaleGitdirRepair.repair(candidate)
        #expect(repaired.scope.directories == ["~/src/renamed-app/"])
    }

    @Test func repairIsANoOpWhenTheStalePathIsAlreadyGone() {
        let work = Self.account(label: "work", paths: ["~/work/"])
        let candidate = StaleGitdirRepair.Candidate(
            account: work,
            stalePath: "~/src/old-app/",
            replacementPath: "~/src/renamed-app/"
        )
        #expect(StaleGitdirRepair.repair(candidate).scope.directories == ["~/work/"])
    }

    // MARK: - Parent helper

    @Test func parentDirectoryOfAGitdirPath() {
        #expect(StaleGitdirRepair.parentDirectory(ofGitdirPath: "~/src/old-app/") == "~/src/")
        #expect(StaleGitdirRepair.parentDirectory(ofGitdirPath: "~/src/old-app") == "~/src/")
        #expect(StaleGitdirRepair.parentDirectory(ofGitdirPath: "/opt/repos/app/") == "/opt/repos/")
        #expect(StaleGitdirRepair.parentDirectory(ofGitdirPath: "~/") == "")
        #expect(StaleGitdirRepair.parentDirectory(ofGitdirPath: "") == "")
    }
}
