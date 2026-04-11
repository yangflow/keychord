# Contributing to keychord

Thanks for your interest in keychord. This document covers how to build, test, and send changes.

## Ground rules

- Be kind. Bug reports and PRs are welcome from everyone.
- Discuss large changes in an issue before starting so we can align on scope and design.
- keychord owns `~/.config/keychord/` and injects a single `Include` line into the user's real config; no change should expand that contract without discussion.

## Prerequisites

- macOS 26.2 or later
- Xcode 26 or later
- Apple Silicon

## Build

```bash
git clone https://github.com/yangflow/keychord.git
cd keychord
open keychord.xcodeproj
```

Select the `keychord` scheme, press ⌘R.

## Test

The unit suite is the source of truth for correctness. UI tests are not relied on in CI.

```bash
xcodebuild test \
  -project keychord.xcodeproj \
  -scheme keychord \
  -destination 'platform=macOS' \
  -only-testing:keychordTests
```

Before opening a PR, make sure `xcodebuild test … -only-testing:keychordTests` exits 0.

If you add a bug fix, please add a regression test that fails on the old code. If you add a service, please add unit tests covering its happy path + at least one error case.

## Code style

- Swift 6, strict concurrency. The project enables the upcoming features `InferIsolatedConformances`, `NonisolatedNonsendingByDefault`, `GlobalActorIsolatedTypesUsability` — keep diffs concurrency-safe.
- SwiftUI for views, AppKit only where the menubar status item + popover + window plumbing makes it necessary.
- Prefer plain structs + enums with associated values over class hierarchies.
- No force unwraps on user input. Throw typed errors.
- No unrelated refactors in bug-fix PRs.
- No emojis in source, comments, or commit messages.

## Commit messages

Short imperative subject (under ~70 chars), optional body explaining the *why*. Match the shape of the existing history:

```
<short subject, imperative>

<optional body explaining the why, not the what>
```

Examples from the log:

```
Fix Swift 6 MainActor isolation + SSH config round-trip
Popover cleanup: drop legacy Add/Edit/Delete + Raw config (Commit D')
AccountProjector + IncludeInstaller (Commit B')
```

Squash your PR into one commit per logical change before requesting review. We do not require `Signed-off-by`.

## Pull request flow

1. Fork + branch off `main`.
2. Implement the change. Add or update tests.
3. Run the test command above. Confirm it exits 0.
4. Push, open a PR against `main`.
5. In the PR body: describe the *why*, not the *what*; point out any config-file side effects; mention any managed-file format changes.

## Areas that need extra care

- **`IncludeInstaller`** — idempotency matters. A second `installSSHInclude` must not double-inject. Test both the first-install and second-install path.
- **`AccountProjector`** — `project` is pure. Never introduce I/O there; keep `write` as the only side effect.
- **`BackupService`** — every write path must pre-backup the target file if it already exists. Not negotiable.
- **Swift 6 concurrency** — when you add a new service that touches shared state, ask whether it needs `@MainActor`, `Sendable`, or both. When in doubt, read `AccountsStore.swift` for the pattern.

## Security

If you discover a security issue, please email the maintainer instead of opening a public issue.

## License

By contributing to keychord you agree your contributions are licensed under the [MIT License](./LICENSE).
