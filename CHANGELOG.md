# Changelog

All notable changes to keychord are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] — 2026-04-12

### Added

- **Selective import** — `ImportPickerView` shows detected accounts from existing SSH/git config with checkboxes. Existing aliases are flagged and unchecked by default. Replaces the old destructive `replaceAll` import.
- **iCloud Sync** — `CloudSyncService` syncs the account list across machines via `NSUbiquitousKeyValueStore`. Merge strategy: newer `updatedAt` wins per UUID; tombstone tracking prevents deleted accounts from reappearing. `CloudSyncView` sheet for enable/disable + status. (Entitlements deferred until code signing is configured.)
- **Sidebar bottom bar** — keygen, restore, import, and iCloud actions moved from the toolbar to a `safeAreaInset` bottom bar in `AccountsSidebar`.
- **Add Account row** — popover's `Manage…` button replaced with an inline `+ Add Account` row at the bottom of the account list, matching `AccountRow` height.

### Changed

- **Backup granularity** — `BackupService` now snapshots `accounts.json` (account-level) instead of individual config files.
- **RestoreView** — redesigned to `Form(.grouped) + Divider + Footer` layout. Loads backup list synchronously to eliminate the initial flash.
- **API simplification** — `AccountProjector.regenerate`, `IncludeInstaller`, `ConfigStore`, and `Fixer` no longer require explicit path parameters; they use sensible defaults.

### Removed

- **Finder directory detection** — popover no longer queries Finder's frontmost window via AppleScript on every refresh. Drag-and-drop detection remains.

### Fixed

- **Probe scope** — SSH probes and Doctor diagnostics now run only against app-managed accounts, not all hosts in `~/.ssh/config`. Fixes false errors from OrbStack, jump-hosts, and other non-Git SSH entries.
- `IncludeInstaller` now appends (instead of prepends) the git include block, fixing compatibility with existing gitconfig content.
- `gitdir:` scope paths are normalized with a trailing slash to match git's `includeIf` semantics.

## [0.1.0] — 2026-04-12

Initial public release. Source-of-truth is `~/.config/keychord/accounts.json`; keychord projects managed files into SSH config + gitconfig via `Include` directives.

### Added

- **Persistent `Account` schema** with UUID, label, GitHub username, SSH alias, key path, git name/email, scope (global or `gitdir:`-scoped), URL rewrites, color tag, notes, and timestamps.
- **`AccountsStore`** — `@MainActor` CRUD store with atomic JSON persistence.
- **`AccountProjector`** — pure projector from `[Account]` to managed files (`ssh_config.managed`, `gitconfig.managed`, `gitconfig-<uuid>.managed`) plus a side-effectful `regenerate` that writes + reinstalls include lines.
- **`IncludeInstaller`** — idempotent marker-wrapped `Include` injection into the user's real `~/.ssh/config` and `~/.gitconfig`; uninstall strips the marker block.
- **`AccountImporter`** — detection from `ConfigModel` into persistent `Account` records (host grouping by key, identity linking via `sshCommand`, default-host fallback, round-robin colors).
- **Accounts window** — native `NavigationSplitView` sidebar + detail pane for CRUD.
- **Doctor** — diagnoses common config problems (missing keys, wrong perms, dangling `Include`, conflicting `IdentityFile`).
- **Fixer** — one-click repair for the diagnoses Doctor surfaces.
- **SSH port selection** — per-account Direct 22 / SSL 443 toggle.
- **Keygen service** — generate ed25519 / RSA keys from the app with safe filenames and correct permissions.
- **Prober** — per-host `ssh -T git@<alias>` probing with success / failure parsing.
- **Restore view** — browse and restore pre-write backups.
- **Current-repo resolver** — drag a folder onto the menubar icon to resolve which account would push from there.
- **BackupService** — atomic pre-write backup with configurable retention.
- **Unit test suite** — 130+ tests covering SSH config parser, git config IO, projector, store, importer, doctor, fixer, backup, and keygen services.

### Fixed

- Swift 6 `MainActor` isolation errors on `AccountsStore.defaultURL`, `AppState.init` default parameter, and `AppDelegate` observation methods.
- `SSHConfigDocument.parse("")` and `serialize([])` round-trip asymmetry that caused `saveSSHConfig` to throw `roundTripVerificationFailed` after removing the last Host block.

[Unreleased]: https://github.com/yangflow/keychord/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/yangflow/keychord/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/yangflow/keychord/releases/tag/v0.1.0
