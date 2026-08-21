# Changelog

All notable changes to keychord are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Drop hint in the popover** — a quiet dashed card explains the drop-on-icon gesture (“drag a project folder onto the menu bar icon”). Illustration only: drops still land on the status-item icon, never inside the popover. Shown while there is no current match, under the account list and above Doctor. (#24)
- **One-click `gitdir:` bind** — a dropped folder with no matching identity now lists **Bind to** plus one row per account. Tapping a row adds the folder to that account's scope (trailing slash, `~` under `$HOME`), saves `accounts.json`, regenerates the managed files, and re-resolves to the matched state. No confirmation dialog; a failed write shows an error on the card. (#25)
- **Clone under a popover account row** — the trailing disclosure on an account row reveals the same compact `org/repo` field + icon-only copy used by the match card. The match-card clone stays; Accounts detail still has none. (#26)
- **Several `gitdir:` paths per account** — `Account.Scope` holds a list, binding **adds** a path instead of replacing one, and the projector writes one `includeIf` per path pointing at the account's single managed sub file. The resolver matches every path (longest prefix still wins), popover rows list the paths, and Accounts detail edits them individually. Old single-path `accounts.json` and backups still load, and saved files stay readable by 0.5.0. (#27)
- **Zero-account empty state** — with no accounts the popover offers **Import from existing config** (the Settings → Import flow) and **Add identity**, plus a footer note about dragging a folder onto the icon. (#28)
- **Next actions when a probe fails** — a failing account row shows **Copy public key** and **Open … SSH settings** (copy only for custom providers), plus a **Probe again** retry that bypasses the 10-minute probe cache for that alias. Doctor states the diagnosis without repeating the buttons. (#29)
- **Restore confirmation** — restoring a snapshot now asks first, listing how many identities are replaced and the labels/emails inside the snapshot. (#30)
- **Git author vs SSH identity check** — after a drop, keychord compares the work tree's live `user.email` / `core.sshCommand` with the account that owns the SSH alias and flags a repo that would commit as one identity and push as another, on the match card and in Doctor (`GIT001`), with a re-project as the only automatic fix. (#31)
- **Menu-bar tooltip** — while a match is active the status item reads `KeyChord · <label>` (or `KeyChord · no match`); the idle icon is unchanged. (#32)
- **Unbind, rebind, and Open in Finder on the match card** — a successful match now offers **Open in Finder**, **Unbind** (drops just this folder's own `gitdir:` entry, never a parent scope like `~/work/`), and **Rebind to** (moves the folder to another identity in one save). Errors stay on the card. (#33)
- **Probe failures pick their own next action** — a red row is classified before it offers a button: a passphrase-protected key that `ssh-agent` does not hold shows **Unlock in Keychain** (`ssh-add --apple-use-keychain`, never prompting), a missing key file points at **Generate a key**, an unreachable host or host-key mismatch only offers a retry, and a rejected key keeps **Copy public key** + **Open … SSH settings**. A healthy account whose matched repository has an HTTPS remote with no `insteadOf` rule gets **Add SSH rewrite**. Healthy rows show nothing at all — no “all good” banner — and Doctor stays a summary that never repeats these buttons. (#34)
- **Filter the identity list** — with three or more accounts the popover shows a search field matching label, alias, email, username and provider, plus provider chips when more than one forge is in use. No avatars; the add row stays put. (#35)
- **Delete tells you what it leaves behind** — the delete confirmation names the private key path and every `gitdir:` path, and offers an opt-in (default off) **Also delete the private key** that refuses symlinks, missing files, and keys another account still uses. Managed files are regenerated; folders on disk are left alone. (#36)
- **The menu-bar icon lights up during a drag** — while a Finder folder hovers the status item it draws an accent-colored dashed ring and glow around the existing glyph. The symbol is never swapped, and the highlight clears on drop, exit, or a cancelled drag. (#37)
- **Stale `gitdir:` paths can be retargeted** — drop a renamed project and, when an account still points at a missing folder in the same parent directory, the card says the old path is gone, names the account, and offers **Point it at this folder** (replaces just that one path) or **Keep the old path**. No other account is touched. (#38)
- **Overlapping scopes are explained** — when several accounts scope the same repository the card lists them in the order git reads them, marks the one git actually uses, says who overrides whom, and offers **Only use {winner} here** (scope the exact folder) or **Unbind {loser} from {path}**. (#39)
- **The last drop sticks around** — a match now survives closing the popover and is only replaced by the next drop, the card's clear control, or an unbind, so the tooltip from #32 keeps naming the identity between clicks. (#40)

### Fixed

- **`includeIf` order now matches what the app claims** — git applies *every* matching `includeIf` in file order and the last one wins; specificity is irrelevant. The projector wrote one block per account in `accounts.json` order, so with `gitdir:~/` and `gitdir:~/work/` the effective identity depended on account order and could disagree with the account the popover named. `gitconfig.managed` now emits blocks least-specific-first (shared `GitdirPrecedence`, which the resolver also reads), so the most specific scope really is the one git uses. Covered by a test that runs the real `git` binary.
- **Backups taken in the same second disappeared from Restore** — the timestamp parser dropped collision-suffixed file names, so a pre-restore snapshot written in the same second as an existing one was unlistable (and never pruned). Restore's pre-restore snapshot is now always recoverable.

### Removed

- **Finder front-window reader** — `FinderContext` was unreachable dead code and the app still shipped an Apple Events usage description for it. Both are gone; keychord only resolves folders the user drops (#40).

## [0.5.0] — 2026-08-22

### Fixed

- **Dock icon after closing windows** — closing About, Accounts, or Sparkle’s update UI restores `.accessory` so the Dock icon goes away while KeyChord stays in the menu bar. One app-wide `NSWindow.willCloseNotification` listener replaces the Accounts-only handler.

### Added

- **In-app language** — Settings offers Follow System / English / 简体中文. The choice is persisted, applied via `AppleLanguages` + SwiftUI `locale`, and a Relaunch button appears when a full catalog refresh needs a process restart.

### Changed

- **Clone row** — removed from Accounts detail. Menubar match card keeps the compact clone field (prefilled from `origin` after an icon drop).
- **Account color** — removed the Appearance swatch row; click the title marker to open the system color panel. Colors store as `#RRGGBB` (legacy `blue`/`green`/… names still decode). Sidebar dots track the draft color live.
- **Settings window** — popover header is **KeyChord** + gear on one row (no separate Accounts section title). Gear opens a dedicated Settings `Window` (`id: "settings"`) with a sidebar: General (language + Open at Login), Keys (keygen), Import (auto-detects existing config), Backups (no duplicate title / Done chrome; absolute timestamps only), Config (Remove Include). Accounts toolbar keeps only **Add account**. App menu **About KeyChord** opens the same `AboutView` window as the popover (not the system about panel).
- **Settings chrome** — dropped helper captions under Language / Startup / Include / Import / Backups / Keygen (errors, relaunch warning, and empty states remain). Ed25519 picker label no longer says “recommended”.
- **Backup policy** — `AccountsStore` snapshots `accounts.json` only when **adding** an account (if a file already exists). `update` / `delete` / `touchLastUsed` / `replaceAll` write without a new backup. Settings → Backups can delete a snapshot; rows use rounded cards with icon-only Restore/Delete; expanded accounts open a read-only snapshot detail sheet.
- **Menu bar icon folder drop** — drag a folder onto the KeyChord menu bar icon to resolve which account applies, then automatically open the popover with the match card. No Choose Folder button or idle drop-zone prompt; popover `.onDrop` remains a secondary convenience. Opening after a drop suppresses match clearing so a transient MenuBarExtra `onDisappear` cannot wipe the result. The match is one-shot: dismissing the popover (or the card’s clear control) clears it; silent Finder auto-resolve on open is gone. Matched repos with `origin` prefill the compact clone field as `owner/repo` so copy is enabled immediately.

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
