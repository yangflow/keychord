## Summary

<!-- What does this PR change and why. Keep it short — one paragraph. -->

## Kind of change

- [ ] Bug fix (regression test added)
- [ ] New feature
- [ ] Refactor (no behavior change)
- [ ] Docs / scaffolding only

## Test plan

- [ ] `xcodebuild test -project keychord.xcodeproj -scheme keychord -destination 'platform=macOS' -only-testing:keychordTests` exits 0
- [ ] Added / updated unit tests for the code path this PR touches
- [ ] Manually verified in the menubar app (what you clicked and what you saw)

## Managed-file side effects

<!-- Does this change the content of ssh_config.managed, gitconfig.managed,
or gitconfig-*.managed? If yes, describe the shape of the diff. -->

## Swift 6 concurrency

<!-- If this PR adds a new class/struct that holds mutable state, say
whether it's @MainActor / Sendable / actor, and why. -->

## Screenshots

<!-- Optional for UI changes. -->
