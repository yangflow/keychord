# Changelog

All notable changes to keychord are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **Dock icon after closing windows** — closing About, Accounts, or Sparkle’s update UI restores `.accessory` so the Dock icon goes away while KeyChord stays in the menu bar. One app-wide `NSWindow.willCloseNotification` listener replaces the Accounts-only handler.

### Added

- **In-app language** — Settings offers Follow System / English / 简体中文. The choice is persisted, applied via `AppleLanguages` + SwiftUI `locale`, and a Relaunch button appears when a full catalog refresh needs a process restart.

### Changed

- **Clone row copy/layout** — Account detail section is plain “Clone” / “克隆” with a Form-style repository field and icon-only copy control; dropped the slogan helper line. Menubar compact clone field still works.
- **Account color** — removed the Appearance swatch row; click the title marker to open the system color panel. Colors store as `#RRGGBB` (legacy `blue`/`green`/… names still decode). Sidebar dots track the draft color live.

## [0.4.0] — 2026-08-22

### Removed

- **iCloud Sync** — the Accounts toolbar button, `CloudSyncService`, and related settings are gone. `accounts.json` on disk is the only source of truth; private keys were already local-only.

### Added

- **English + Simplified Chinese UI** — visible strings follow the system language via `Localizable.xcstrings`.
- **Restore snapshot preview** — backup rows show account count, labels, and size; expand a row to see git identity, SSH alias/provider/port, key path, scope, and URL rewrites before restoring.

### Changed

- **Accounts toolbar** — action icons share one optical size and live on the detail column only, so collapsing the sidebar no longer hitch-inserts a `»` into the action cluster.

### Added

- **Open at Login** — Accounts window → Settings offers **Open at Login** via `SMAppService.mainApp`. The toggle follows live registration status; register/unregister failures show a visible error and do not leave the switch claiming success. Unit tests cover the controller with a fake service (no real login-item writes).
- **Clone as this identity** — Account detail (and the current-repo hero) accepts `org/repo` or a pasted original URL and copies a rewritten `git clone git@<alias>:…` command. Pure `CloneURLRewriter` over alias + provider host + `urlRewrites`; read-only, no config writes.
- **Remove Include from Settings** — Accounts window → Settings offers **Remove Include (keep accounts.json)** with a confirmation dialog. Calls `IncludeInstaller.uninstallUserIncludes` to strip only the `# --- keychord managed ---` marker blocks from `~/.ssh/config` and `~/.gitconfig`; `accounts.json`, managed files, and private keys are left alone.
- **SSH probe cache** — popover opens reuse the last `ssh -T` result for each alias (10-minute TTL). Successful probes stay cached until **Refresh**; failures and never-probed aliases auto-reprobe after the TTL. The menu-bar icon keeps the cached worst severity instead of flashing key → warning on every open.
- **Multi-provider accounts** — `Account` carries a `provider` (`github` / `gitlab` / `gitea` / `custom`) and a generic `username` (legacy `githubUsername` still decodes). Account detail offers one-click `insteadOf` rewrite presets for common hosts; Keygen opens the matching SSH settings URL (custom only copies the public key). Old `accounts.json` without `provider` loads as GitHub with no data loss.
- **Account detail path pickers** — `gitdir` and private key fields keep TextFields (paste still works) and gain folder/file chooser buttons. Chosen directories are stored with a trailing slash (and `~` when under `$HOME`); chosen keys default the panel to `~/.ssh` and store an absolute or `~` path that still projects.
- **Attach generated SSH key to an account** — after keygen succeeds, **Use with this account** picks an existing account or creates a new one, writes `keyPath` / fingerprint, saves `accounts.json`, and regenerates managed files. Copy public key and provider-aware **Open … SSH settings** remain available (custom copies the key only); cancelling the attach picker does not write an account.
- **Current Repo in the MenuBarExtra popover** — drop a folder or git working copy onto the popover, or use **Choose Folder…**, to see which account applies (label, alias, email, scope). Unresolved paths explain why: not a git repo, no matching `gitdir:`, or conflicting globals. Optionally reads Finder's frontmost window path and stays quiet on Automation / AppleScript failure. Reuses `CurrentRepoResolver` with account/`gitdir:` matching; does not restore a custom `NSStatusItem`.
## [0.3.1] — 2026-04-14

### Changed

- **SwiftUI cleanup** — modernized the Accounts window detail pane: the optional draft binding now uses `Binding($draft)` unwrap instead of a manual `Binding(get:set:)`, eliminating a latent staleness bug. URL rewrite rows bind directly via subscript. Color swatches are now `Button` with `.plain` style so VoiceOver reads them correctly. The empty state uses `ContentUnavailableView`.
- **Date display** — account metadata and restore backups render with `Text(_, format:)` / `Date.formatted(date:time:)` instead of a per-view `DateFormatter`.
- **CloudSync status dot** — structural identity preserved by deriving the fill color from state rather than branching into four different `Circle` instances.
- **Menubar app lifecycle** — `DispatchQueue.main.asyncAfter` replaced with `Task.sleep(for:)` in the willClose handler.

### Removed

- **Dead code** (~490 lines): `HostEditView`, unused rows (`HostRow`, `IdentityRow`, `InsteadOfRow`, `IncludeIfRow`) in `PopoverRows`, and unused containers (`KCCard`, `KCSectionHeader`, `KCRowContainer`, `KCGroupedSection`, `KCHeroContainer`) in `DesignSystem`.

## [0.3.0] — 2026-04-14

### Changed

- **Menubar popover** — rewritten on top of SwiftUI `MenuBarExtra` + scene-based `WindowGroup`/`Window`, replacing the hand-rolled `NSStatusItem` + `NSPopover` + `AppDelegate` wiring. App state is now a single `@Observable` injected via `.environment()`.
- **Accounts window sidebar** — moved add/keygen/import/restore/iCloud actions into the window's `.toolbar`, removing the custom `safeAreaInset` bottom bar that was clobbering the split-view toggle and causing the `»` button to flash when expanding/collapsing the sidebar.
- **Accounts section styling** — popover rows are restyled to match native Mac list affordances: slimmer color dots, trailing chevron, `selectedContentBackgroundColor` hover, dividers inset past the icon, and a condensed alias · email subtitle. The heavy `KCCard` + header wrapper is gone.

### Removed

- **Drag-folder-onto-menubar** — no longer supported. The feature relied on a custom `NSStatusItem` subview, which is incompatible with the new `MenuBarExtra` popover.
- **"Current Repo" hero card** — the popover no longer resolves which account applies to a dropped folder, since there is no drop path to feed it. The `CurrentRepoResolver` service is retained for potential reuse.

## [0.2.1] — 2026-04-13

### Fixed

- **Add Account always reachable** — the popover's `+ Add Account` row is now shown even when there are no accounts. Previously the entire accounts section was hidden behind an `isEmpty` branch, making it impossible to add a first account from the popover.

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

[Unreleased]: https://github.com/yangflow/keychord/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/yangflow/keychord/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/yangflow/keychord/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/yangflow/keychord/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/yangflow/keychord/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/yangflow/keychord/releases/tag/v0.1.0
