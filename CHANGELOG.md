# Changelog

All notable changes to keychord are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-04-12

Initial public release. Source-of-truth is now `~/.config/keychord/accounts.json` and keychord projects managed files into SSH config + gitconfig via `Include` directives.

### Added

- **Persistent `Account` schema** with UUID, label, GitHub username, SSH alias, key path, git name/email, scope (global or `gitdir:`-scoped), URL rewrites, color tag, notes, and timestamps. Stored at `~/.config/keychord/accounts.json`.
- **`AccountsStore`** — `@MainActor` CRUD store with atomic JSON persistence.
- **`AccountProjector`** — pure projector from `[Account]` to managed files (`ssh_config.managed`, `gitconfig.managed`, `gitconfig-<uuid>.managed`) plus a side-effectful `regenerate` that writes + reinstalls include lines.
- **`IncludeInstaller`** — idempotent marker-wrapped `Include` injection into the user's real `~/.ssh/config` and `~/.gitconfig`; uninstall strips the marker block.
- **`AccountImporter`** — one-shot detection from a loaded `ConfigModel` into persistent `Account` records (host grouping by key, identity linking via `sshCommand`, default-host fallback, round-robin colors).
- **Accounts window** — native `NavigationSplitView` sidebar + detail pane for CRUD, opened from the popover's **Manage…** button.
- **Doctor** — diagnoses common config problems (missing keys, wrong perms, dangling `Include`, conflicting `IdentityFile`, proxy mismatch).
- **Fixer** — one-click repair for the diagnoses Doctor surfaces.
- **Network profile switcher** — Direct 22 / SSL 443 / HTTPS + Proxy profiles for `github.com`, with pre-write backups.
- **Keygen service** — generate ed25519 / RSA keys from the app with safe filenames and correct permissions.
- **Prober** — per-host `ssh -T git@<alias>` probing with success / failure parsing.
- **Restore view** — browse and restore pre-write backups.
- **Current-repo resolver** — drag a folder onto the menubar icon to resolve which account would push from there.
- **BackupService** — atomic pre-write backup with configurable retention.
- **Unit test suite** — 150 tests covering SSH config parser, git config IO, projector, store, importer, doctor, fixer, backup, network profile, and keygen services.

### Fixed

- Swift 6 `MainActor` isolation errors on `AccountsStore.defaultURL`, `AppState.init` default parameter, and `AppDelegate` observation methods.
- `SSHConfigDocument.parse("")` and `serialize([])` round-trip asymmetry that caused `saveSSHConfig` to throw `roundTripVerificationFailed` after removing the last Host block.

[Unreleased]: https://github.com/yangflow/keychord/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yangflow/keychord/releases/tag/v0.1.0
