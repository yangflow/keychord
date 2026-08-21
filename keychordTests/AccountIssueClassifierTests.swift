import Testing
import Foundation
@testable import keychord

@Suite("AccountIssueClassifier")
struct AccountIssueClassifierTests {

    static func account(
        provider: Account.Provider = .github,
        alias: String = "github-work",
        keyPath: String = "~/.ssh/id_work",
        rewrites: [Account.URLRewrite] = []
    ) -> Account {
        var account = Account.new(
            label: "work",
            sshAlias: alias,
            keyPath: keyPath,
            provider: provider,
            gitUserName: "Work",
            gitUserEmail: "work@company.com"
        )
        account.urlRewrites = rewrites
        return account
    }

    static func keyState(
        exists: Bool = true,
        encrypted: Bool = false,
        loaded: Bool = false,
        agentReachable: Bool = true
    ) -> SSHKeyState {
        SSHKeyState(
            hasKeyPath: true,
            privateKeyExists: exists,
            isEncrypted: encrypted,
            isLoadedInAgent: loaded,
            agentReachable: agentReachable
        )
    }

    // MARK: - Locked key

    @Test func encryptedKeyMissingFromTheAgentIsLocked() {
        let issue = AccountIssueClassifier.classify(
            account: Self.account(),
            probe: .failed(reason: "permission denied (publickey)"),
            keyState: Self.keyState(encrypted: true, loaded: false)
        )
        #expect(issue == .keyLocked(keyPath: "~/.ssh/id_work"))
        #expect(issue?.severity == .error)
    }

    @Test func encryptedKeyAlreadyLoadedIsAnAuthRejection() {
        let issue = AccountIssueClassifier.classify(
            account: Self.account(),
            probe: .failed(reason: "permission denied (publickey)"),
            keyState: Self.keyState(encrypted: true, loaded: true)
        )
        #expect(issue == .authRejected(reason: "permission denied (publickey)"))
    }

    @Test func withoutAnAgentWeDoNotClaimTheKeyIsLocked() {
        let issue = AccountIssueClassifier.classify(
            account: Self.account(),
            probe: .failed(reason: "permission denied (publickey)"),
            keyState: Self.keyState(encrypted: true, loaded: false, agentReachable: false)
        )
        #expect(issue == .authRejected(reason: "permission denied (publickey)"))
    }

    @Test func unprotectedKeyIsAnAuthRejection() {
        let issue = AccountIssueClassifier.classify(
            account: Self.account(),
            probe: .failed(reason: "permission denied (publickey)"),
            keyState: Self.keyState(encrypted: false, loaded: false)
        )
        #expect(issue == .authRejected(reason: "permission denied (publickey)"))
    }

    // MARK: - Missing key file

    @Test func missingKeyFileWinsOverEverythingElse() {
        let issue = AccountIssueClassifier.classify(
            account: Self.account(),
            probe: .failed(reason: "permission denied (publickey)"),
            keyState: Self.keyState(exists: false, encrypted: true)
        )
        #expect(issue == .keyFileMissing(path: "~/.ssh/id_work"))
    }

    @Test func probeReasonAloneCanReportAMissingKey() {
        let issue = AccountIssueClassifier.classify(
            account: Self.account(),
            probe: .failed(reason: "key file missing"),
            keyState: nil
        )
        #expect(issue == .keyFileMissing(path: "~/.ssh/id_work"))
    }

    // MARK: - Unreachable

    @Test func networkFailuresAreNotKeyProblems() {
        let reasons = ["timed out", "connection refused", "host unreachable", "host key mismatch"]
        for reason in reasons {
            let issue = AccountIssueClassifier.classify(
                account: Self.account(),
                probe: .failed(reason: reason),
                keyState: Self.keyState(encrypted: true, loaded: false)
            )
            // A locked key still wins — it is the concrete thing to fix.
            #expect(issue == .keyLocked(keyPath: "~/.ssh/id_work"), "reason: \(reason)")

            let plain = AccountIssueClassifier.classify(
                account: Self.account(),
                probe: .failed(reason: reason),
                keyState: Self.keyState()
            )
            #expect(plain == .unreachable(reason: reason), "reason: \(reason)")
            #expect(plain?.severity == .warning)
        }
    }

    // MARK: - Healthy rows

    @Test func healthyRowWithNoMatchedRepoStaysSilent() {
        #expect(
            AccountIssueClassifier.classify(
                account: Self.account(),
                probe: .ok(username: "alex"),
                keyState: nil
            ) == nil
        )
        #expect(
            AccountIssueClassifier.classify(
                account: Self.account(),
                probe: .idle,
                keyState: nil
            ) == nil
        )
    }

    @Test func sshRemoteOnAHealthyAccountStaysSilent() {
        #expect(
            AccountIssueClassifier.classify(
                account: Self.account(),
                probe: .ok(username: "alex"),
                keyState: nil,
                matchedOriginURL: "git@github-work:acme/api.git"
            ) == nil
        )
    }

    // MARK: - HTTPS remote

    @Test func httpsRemoteWithoutARewriteIsFlagged() {
        let issue = AccountIssueClassifier.classify(
            account: Self.account(),
            probe: .ok(username: "alex"),
            keyState: nil,
            matchedOriginURL: "https://github.com/acme/api.git"
        )
        #expect(issue == .httpsRemote(origin: "https://github.com/acme/api.git"))
        #expect(issue?.severity == .warning)
    }

    @Test func configuredRewriteSilencesTheHTTPSWarning() {
        let account = Self.account(rewrites: [
            Account.URLRewrite(from: "https://github.com/", to: "git@github-work:")
        ])
        #expect(
            AccountIssueClassifier.classify(
                account: account,
                probe: .ok(username: "alex"),
                keyState: nil,
                matchedOriginURL: "https://github.com/acme/api.git"
            ) == nil
        )
    }

    @Test func customProviderHasNoPresetSoNoHTTPSWarning() {
        let account = Self.account(provider: .custom)
        #expect(
            AccountIssueClassifier.classify(
                account: account,
                probe: .ok(username: "alex"),
                keyState: nil,
                matchedOriginURL: "https://git.internal/acme/api.git"
            ) == nil
        )
    }

    @Test func accountWithoutAnAliasHasNoHTTPSWarning() {
        let account = Self.account(alias: "")
        #expect(
            AccountIssueClassifier.httpsRemoteIssue(
                account: account,
                originURL: "https://github.com/acme/api.git"
            ) == nil
        )
    }

    @Test func failureClassificationBeatsTheHTTPSWarning() {
        let issue = AccountIssueClassifier.classify(
            account: Self.account(),
            probe: .failed(reason: "permission denied (publickey)"),
            keyState: Self.keyState(),
            matchedOriginURL: "https://github.com/acme/api.git"
        )
        #expect(issue == .authRejected(reason: "permission denied (publickey)"))
    }

    // MARK: - Helpers

    @Test func detectsHTTPRemotes() {
        #expect(AccountIssueClassifier.isHTTPRemote("https://github.com/a/b.git"))
        #expect(AccountIssueClassifier.isHTTPRemote("HTTP://github.com/a/b.git"))
        #expect(!AccountIssueClassifier.isHTTPRemote("git@github.com:a/b.git"))
        #expect(!AccountIssueClassifier.isHTTPRemote("ssh://git@github.com/a/b.git"))
    }

    @Test func onlyConfiguredRulesCountAsRewrites() {
        let bare = Self.account()
        #expect(
            !AccountIssueClassifier.hasConfiguredRewrite(
                for: "https://github.com/acme/api.git",
                account: bare
            )
        )
        var configured = bare
        configured.applyInsteadOfPreset()
        #expect(
            AccountIssueClassifier.hasConfiguredRewrite(
                for: "https://github.com/acme/api.git",
                account: configured
            )
        )
    }
}
