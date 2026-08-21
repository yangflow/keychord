import Testing
import Foundation
@testable import keychord

@Suite("CloneURLRewriter")
struct CloneURLRewriterTests {

    // MARK: - Primary acceptance cases (#11)

    @Test func githubWorkAliasRewritesStandardGitHubSSHURL() {
        let account = makeAccount(alias: "github-work", provider: .github)
        let command = CloneURLRewriter.cloneCommand(
            for: account,
            input: "git@github.com:yangflow/keychord.git"
        )
        #expect(command == "git clone git@github-work:yangflow/keychord.git")
    }

    @Test func orgRepoShorthandUsesAlias() {
        let account = makeAccount(alias: "github-work", provider: .github)
        let command = CloneURLRewriter.cloneCommand(for: account, input: "org/repo")
        #expect(command == "git clone git@github-work:org/repo.git")
    }

    @Test func httpsGitHubURLRewritesOntoAlias() {
        let account = makeAccount(alias: "github-work", provider: .github)
        let command = CloneURLRewriter.cloneCommand(
            for: account,
            input: "https://github.com/org/repo.git"
        )
        #expect(command == "git clone git@github-work:org/repo.git")
    }

    // MARK: - urlRewrites take precedence by longest match

    @Test func specificURLRewriteBeatsProviderDefault() {
        var account = makeAccount(alias: "github-work", provider: .github)
        account.urlRewrites = [
            Account.URLRewrite(from: "https://github.com/acme/", to: "git@github-work:Acme/"),
        ]
        let command = CloneURLRewriter.cloneCommand(
            for: account,
            input: "https://github.com/acme/widget.git"
        )
        #expect(command == "git clone git@github-work:Acme/widget.git")
    }

    @Test func accountInsteadOfRulesAloneRewriteSSH() {
        var account = makeAccount(alias: "github-work", provider: .custom)
        account.urlRewrites = [
            Account.URLRewrite(from: "git@github.com:", to: "git@github-work:"),
        ]
        let url = CloneURLRewriter.rewriteURL(
            for: account,
            input: "git@github.com:org/repo.git"
        )
        #expect(url == "git@github-work:org/repo.git")
    }

    // MARK: - Edge cases

    @Test func emptyAliasReturnsNil() {
        let account = makeAccount(alias: "  ", provider: .github)
        #expect(CloneURLRewriter.cloneCommand(for: account, input: "org/repo") == nil)
        #expect(CloneURLRewriter.cloneCommand(
            for: account,
            input: "git@github.com:org/repo.git"
        ) == nil)
    }

    @Test func emptyOrBlankInputReturnsNil() {
        let account = makeAccount(alias: "github-work", provider: .github)
        #expect(CloneURLRewriter.cloneCommand(for: account, input: "") == nil)
        #expect(CloneURLRewriter.cloneCommand(for: account, input: "   ") == nil)
    }

    @Test func alreadyAliasedURLPassesThrough() {
        let account = makeAccount(alias: "github-work", provider: .github)
        let command = CloneURLRewriter.cloneCommand(
            for: account,
            input: "git@github-work:org/repo.git"
        )
        #expect(command == "git clone git@github-work:org/repo.git")
    }

    @Test func stripsLeadingGitCloneCommand() {
        let account = makeAccount(alias: "github-work", provider: .github)
        let command = CloneURLRewriter.cloneCommand(
            for: account,
            input: "git clone git@github.com:org/repo.git"
        )
        #expect(command == "git clone git@github-work:org/repo.git")
    }

    @Test func orgRepoAlreadyEndingInGitIsNotDoubled() {
        let account = makeAccount(alias: "github-work", provider: .github)
        let url = CloneURLRewriter.rewriteURL(for: account, input: "org/repo.git")
        #expect(url == "git@github-work:org/repo.git")
    }

    @Test func gitlabProviderRewritesCanonicalHost() {
        let account = makeAccount(alias: "gitlab-work", provider: .gitlab)
        let command = CloneURLRewriter.cloneCommand(
            for: account,
            input: "git@gitlab.com:group/project.git"
        )
        #expect(command == "git clone git@gitlab-work:group/project.git")
    }

    @Test func customProviderPeelsOwnerRepoFromForeignSSHURL() {
        let account = makeAccount(alias: "corp-git", provider: .custom)
        // Full foreign host URL still yields a clone onto this alias by
        // extracting owner/repo (needed after a folder drop whose origin
        // points at github.com while the account alias is custom).
        #expect(CloneURLRewriter.cloneCommand(
            for: account,
            input: "git@github.com:org/repo.git"
        ) == "git clone git@corp-git:org/repo.git")
        #expect(CloneURLRewriter.cloneCommand(
            for: account,
            input: "org/repo"
        ) == "git clone git@corp-git:org/repo.git")
    }

    @Test func preferredCloneInputExtractsOwnerRepo() {
        #expect(
            CloneURLRewriter.preferredCloneInput(
                fromOriginURL: "git@github-yangflow:yangflow/cumora.git"
            ) == "yangflow/cumora"
        )
        #expect(
            CloneURLRewriter.preferredCloneInput(
                fromOriginURL: "https://github.com/yangflow/cumora.git"
            ) == "yangflow/cumora"
        )
    }

    @Test func accountConvenienceMatchesStaticAPI() {
        let account = makeAccount(alias: "github-work", provider: .github)
        #expect(
            account.cloneCommand(for: "org/repo")
                == CloneURLRewriter.cloneCommand(for: account, input: "org/repo")
        )
    }

    // MARK: - git remote set-url for an HTTPS remote (#42)

    @Test func setURLCommandRewritesAnHTTPSRemote() {
        let account = makeAccount(alias: "github-work", provider: .github)
        #expect(
            CloneURLRewriter.remoteSetURLCommand(
                for: account,
                originURL: "https://github.com/acme/api.git"
            ) == "git remote set-url origin git@github-work:acme/api.git"
        )
    }

    /// The path is carried over exactly as the remote had it — subgroups
    /// included, and no `.git` invented — so set-url only changes host and
    /// transport.
    @Test func setURLCommandKeepsSubgroupsAndTheOriginalSuffix() {
        let account = makeAccount(alias: "gitlab-work", provider: .gitlab)
        #expect(
            CloneURLRewriter.remoteSetURLCommand(
                for: account,
                originURL: "https://gitlab.com/acme/group/api"
            ) == "git remote set-url origin git@gitlab-work:acme/group/api"
        )
        #expect(
            CloneURLRewriter.remoteSetURLCommand(
                for: account,
                originURL: "https://gitlab.com/acme/group/api.git"
            ) == "git remote set-url origin git@gitlab-work:acme/group/api.git"
        )
    }

    @Test func setURLCommandIsNilForAnSSHRemote() {
        let account = makeAccount(alias: "github-work", provider: .github)
        #expect(
            CloneURLRewriter.remoteSetURLCommand(
                for: account,
                originURL: "git@github.com:acme/api.git"
            ) == nil
        )
        #expect(
            CloneURLRewriter.remoteSetURLCommand(
                for: account,
                originURL: "git@github-work:acme/api.git"
            ) == nil
        )
    }

    @Test func setURLCommandIsNilWithoutAnAlias() {
        let account = makeAccount(alias: "", provider: .github)
        #expect(
            CloneURLRewriter.remoteSetURLCommand(
                for: account,
                originURL: "https://github.com/acme/api.git"
            ) == nil
        )
    }

    @Test func setURLCommandHonorsAnExplicitRemoteName() {
        let account = makeAccount(alias: "github-work", provider: .github)
        #expect(
            CloneURLRewriter.remoteSetURLCommand(
                for: account,
                originURL: "https://github.com/acme/api.git",
                remoteName: "upstream"
            ) == "git remote set-url upstream git@github-work:acme/api.git"
        )
    }

    // MARK: - Helpers

    private func makeAccount(alias: String, provider: Account.Provider) -> Account {
        Account.new(
            label: "Test",
            sshAlias: alias,
            keyPath: "~/.ssh/id_ed25519",
            provider: provider,
            gitUserName: "Test",
            gitUserEmail: "test@example.com"
        )
    }
}
