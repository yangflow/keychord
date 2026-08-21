import Testing
import Foundation
@testable import keychord

@Suite("AccountOrdering")
struct AccountOrderingTests {

    static func account(
        label: String,
        lastUsed: TimeInterval? = nil,
        created: TimeInterval = 1_700_000_000
    ) -> Account {
        var account = Account.new(
            label: label,
            sshAlias: "github-\(label)",
            keyPath: "~/.ssh/id_\(label)",
            gitUserName: label,
            gitUserEmail: "\(label)@example.com"
        )
        account.createdAt = Date(timeIntervalSince1970: created)
        account.updatedAt = account.createdAt
        account.lastUsedAt = lastUsed.map { Date(timeIntervalSince1970: $0) }
        return account
    }

    // MARK: - Recency

    @Test func mostRecentlyUsedComesFirst() {
        let sorted = AccountOrdering.byLastUsed([
            Self.account(label: "personal", lastUsed: 1_800_000_000),
            Self.account(label: "work", lastUsed: 1_800_000_500),
            Self.account(label: "oss", lastUsed: 1_799_999_000),
        ])
        #expect(sorted.map(\.label) == ["work", "personal", "oss"])
    }

    @Test func neverUsedAccountsSinkBelowUsedOnes() {
        let sorted = AccountOrdering.byLastUsed([
            Self.account(label: "fresh"),
            Self.account(label: "work", lastUsed: 1_800_000_000),
        ])
        #expect(sorted.map(\.label) == ["work", "fresh"])
    }

    @Test func neverUsedAccountsSortByLabel() {
        let sorted = AccountOrdering.byLastUsed([
            Self.account(label: "zeta"),
            Self.account(label: "Alpha"),
            Self.account(label: "middle"),
        ])
        #expect(sorted.map(\.label) == ["Alpha", "middle", "zeta"])
    }

    @Test func unnamedAccountsGoLastWithinTheirGroup() {
        let sorted = AccountOrdering.byLastUsed([
            Self.account(label: ""),
            Self.account(label: "work"),
        ])
        #expect(sorted.map(\.label) == ["work", ""])
    }

    @Test func identicalTimestampsFallBackToLabelThenCreation() {
        let sorted = AccountOrdering.byLastUsed([
            Self.account(label: "beta", lastUsed: 1_800_000_000),
            Self.account(label: "alpha", lastUsed: 1_800_000_000),
        ])
        #expect(sorted.map(\.label) == ["alpha", "beta"])

        let sameLabel = AccountOrdering.byLastUsed([
            Self.account(label: "same", lastUsed: 1_800_000_000, created: 200),
            Self.account(label: "same", lastUsed: 1_800_000_000, created: 100),
        ])
        #expect(sameLabel.map(\.createdAt.timeIntervalSince1970) == [100, 200])
    }

    @Test func orderingIsDeterministicAndTotal() {
        let roster = [
            Self.account(label: "work", lastUsed: 1_800_000_500),
            Self.account(label: "personal", lastUsed: 1_800_000_000),
            Self.account(label: "fresh"),
            Self.account(label: ""),
        ]
        let first = AccountOrdering.byLastUsed(roster).map(\.label)
        let again = AccountOrdering.byLastUsed(roster.reversed()).map(\.label)
        #expect(first == again)
        #expect(first == ["work", "personal", "fresh", ""])
    }

    @Test func emptyAndSingleListsAreHandled() {
        #expect(AccountOrdering.byLastUsed([]).isEmpty)
        #expect(AccountOrdering.byLastUsed([Self.account(label: "solo")]).count == 1)
    }

    // MARK: - Filter still applies after sorting (#35 + #43)

    @Test func filteringASortedListKeepsTheOrder() {
        let sorted = AccountOrdering.byLastUsed([
            Self.account(label: "work-labs", lastUsed: 1_800_000_100),
            Self.account(label: "personal", lastUsed: 1_800_000_500),
            Self.account(label: "work-acme", lastUsed: 1_800_000_300),
        ])
        let filtered = AccountFilter.apply(accounts: sorted, query: "work")
        #expect(filtered.map(\.label) == ["work-acme", "work-labs"])
    }
}

@Suite("AccountScopeText")
struct AccountScopeTextTests {

    static func account(scope: Account.Scope) -> Account {
        Account.new(
            label: "work",
            sshAlias: "github-work",
            keyPath: "~/.ssh/id_work",
            gitUserName: "Work",
            gitUserEmail: "work@company.com",
            scope: scope
        )
    }

    @Test func globalScopeReadsAsGlobal() {
        let summary = AccountScopeText.summary(for: Self.account(scope: .global))
        #expect(!summary.isEmpty)
        #expect(!summary.contains("gitdir"))
        #expect(AccountScopeText.paths(of: Account.Scope.global).isEmpty)
    }

    @Test func singlePathIsListed() {
        #expect(
            AccountScopeText.summary(for: Self.account(scope: .gitdir("~/work/")))
                == "gitdir: ~/work/"
        )
    }

    @Test func everyPathIsListedInOrder() {
        let account = Self.account(scope: .gitdir(paths: ["~/work/", "~/src/new-app/"]))
        #expect(
            AccountScopeText.summary(for: account)
                == "gitdir: ~/work/ · ~/src/new-app/"
        )
    }

    @Test func blankEntriesAreSkipped() {
        let account = Self.account(scope: .gitdir(paths: ["", "  ", "~/work/"]))
        #expect(AccountScopeText.summary(for: account) == "gitdir: ~/work/")
    }

    @Test func scopeWithOnlyBlanksFallsBackToGlobalWording() {
        let account = Self.account(scope: .gitdir(paths: ["", " "]))
        #expect(AccountScopeText.summary(for: account) == AccountScopeText.summary(for: Self.account(scope: .global)))
    }

    @Test func homePathsAreAbbreviated() {
        let account = Self.account(scope: .gitdir("\(NSHomeDirectory())/work/"))
        #expect(AccountScopeText.summary(for: account) == "gitdir: ~/work/")
    }

    @Test func scopeLineMentionsEveryPath() {
        let account = Self.account(scope: .gitdir(paths: ["~/work/", "/opt/repos/"]))
        let line = AccountScopeText.scopeLine(for: account)
        #expect(line.contains("~/work/"))
        #expect(line.contains("/opt/repos/"))
    }
}

@Suite("DoctorPresentation")
struct DoctorPresentationTests {

    static func diagnosis(code: String, file: String = "~/.ssh/config") -> Diagnosis {
        Diagnosis(
            severity: .warning,
            code: code,
            title: "Title \(code)",
            detail: "Detail",
            fixHint: nil,
            affectedFiles: [file]
        )
    }

    @Test func healthyRunStaysCollapsed() {
        #expect(
            !DoctorPresentation.shouldExpand(
                diagnoses: [],
                previousSignature: "",
                wasExpanded: true
            )
        )
    }

    @Test func newFindingsExpandThemselves() {
        #expect(
            DoctorPresentation.shouldExpand(
                diagnoses: [Self.diagnosis(code: "SSH001")],
                previousSignature: "",
                wasExpanded: false
            )
        )
    }

    @Test func refreshingTheSameFindingsRespectsAManualCollapse() {
        let diagnoses = [Self.diagnosis(code: "SSH001")]
        let signature = DoctorPresentation.signature(of: diagnoses)
        #expect(
            !DoctorPresentation.shouldExpand(
                diagnoses: diagnoses,
                previousSignature: signature,
                wasExpanded: false
            )
        )
        #expect(
            DoctorPresentation.shouldExpand(
                diagnoses: diagnoses,
                previousSignature: signature,
                wasExpanded: true
            )
        )
    }

    @Test func aDifferentProblemReopensTheSection() {
        let first = [Self.diagnosis(code: "SSH001")]
        let second = [Self.diagnosis(code: "NET001")]
        #expect(
            DoctorPresentation.shouldExpand(
                diagnoses: second,
                previousSignature: DoctorPresentation.signature(of: first),
                wasExpanded: false
            )
        )
    }

    @Test func signatureIgnoresOrder() {
        let a = Self.diagnosis(code: "SSH001")
        let b = Self.diagnosis(code: "NET001", file: "~/.gitconfig")
        #expect(
            DoctorPresentation.signature(of: [a, b])
                == DoctorPresentation.signature(of: [b, a])
        )
        #expect(DoctorPresentation.signature(of: []).isEmpty)
    }
}
