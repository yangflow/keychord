# keychord

> Manage multiple Git identities from your macOS menubar — without touching your dotfiles.

[简体中文](./README.zh-CN.md) · English

keychord is a menubar-only macOS app that lets you keep several GitHub accounts on one machine — personal, work, open source — each with its own SSH key, git name/email, URL rewrites, and optional `gitdir:`-scoped activation. keychord owns a small JSON file and generates *managed* SSH config and gitconfig files; it injects a single `Include` line into your existing `~/.ssh/config` and `~/.gitconfig`. Your dotfiles stay yours.

## Why

Using more than one Git identity on the same Mac usually means either:
- hand-editing `~/.ssh/config` + `~/.gitconfig` + `~/.gitconfig-work` and hoping you remember which alias to `git clone` with, or
- sprinkling `GIT_SSH_COMMAND` everywhere.

keychord makes the identity set a first-class thing you can CRUD from a window, and projects the result back into real config files in a way that is auditable, reversible, and leaves everything else you wrote by hand untouched.

## Features

- **Account CRUD** — add, edit, delete accounts from a native `NavigationSplitView` window. Source of truth: `~/.config/keychord/accounts.json`.
- **`gitdir:` scoping** — each account can be global or scoped to a working directory via git's `includeIf gitdir:` mechanism.
- **URL rewrites** — per-account `insteadOf` / `pushInsteadOf` rules land in the generated gitconfig.
- **Import existing config** — one click detects logical accounts from your current `~/.ssh/config` + `~/.gitconfig` and seeds `accounts.json`.
- **Doctor & Fixer** — diagnose common config problems (missing keys, wrong permissions, dangling `Include`, conflicting `IdentityFile`) and apply one-click fixes.
- **Network profile switcher** — for `github.com`, flip between Direct 22 / SSL 443 / HTTPS + Proxy. Useful on networks where port 22 is blocked.
- **SSH key generator** — create an ed25519 or RSA key from the app with safe filenames and correct permissions.
- **Atomic backups** — every write is preceded by a pre-write backup in `~/.config/keychord/backups/`, browsable from the Restore view.
- **Probes** — per-host `ssh -T git@<alias>` probes so you can see at a glance which accounts authenticate.
- **Menubar-only** — `LSUIElement = YES`. No dock icon, no window stealing focus. Drag a folder onto the menubar icon to resolve which account would push from there.

## How it works (the managed-file model)

keychord never rewrites the body of your existing config files. Instead:

1. `accounts.json` is the source of truth.
2. On every save, `AccountProjector` writes three flavors of *managed* files under `~/.config/keychord/`:
   - `ssh_config.managed` — one `Host` block per account
   - `gitconfig.managed` — global `[user]`, url rewrites, `[includeIf]` pointers for scoped accounts
   - `gitconfig-<uuid>.managed` — one per `gitdir:`-scoped account, holding `[user]` + `[core] sshCommand`
3. `IncludeInstaller` injects (once, idempotently) a marker-wrapped `Include` block at the top of your real `~/.ssh/config` and `~/.gitconfig`:
   ```
   # --- keychord managed ---
   Include ~/.config/keychord/ssh_config.managed
   # --- keychord managed end ---
   ```
4. Everything outside the marker block is left exactly as you wrote it. Uninstalling is removing the marker block.

This means keychord plays nicely with hand-written config, dotfile managers, and home-manager.

## Requirements

- macOS 26.2 or later
- Xcode 26 or later (Swift 6 mode with strict concurrency)
- Apple Silicon

## Build from source

```bash
git clone https://github.com/yangflow/keychord.git
cd keychord
open keychord.xcodeproj
```

Select the `keychord` scheme and ⌘R. The first launch creates `~/.config/keychord/` on demand; nothing is written to your real dotfiles until you click **Save** on an account.

### Running tests

```bash
xcodebuild test \
  -project keychord.xcodeproj \
  -scheme keychord \
  -destination 'platform=macOS' \
  -only-testing:keychordTests
```

The unit test suite covers the SSH config parser, the git config IO layer, the `AccountProjector`, `AccountsStore`, `AccountImporter`, `Doctor`, `Fixer`, `BackupService`, network profile apply/rewrite, and the keygen service.

## Usage

1. Click the menubar icon. The first time, the accounts section will say *"No accounts yet"*.
2. Click **Manage…** to open the accounts window.
3. **Import existing** detects whatever is already in `~/.ssh/config` + `~/.gitconfig` and fills `accounts.json`, or click **+** to start an empty account.
4. Fill in label, git name/email, SSH alias, key path, optional `gitdir:` scope and URL rewrites. ⌘S saves.
5. Every save regenerates the managed files and reinstalls the `Include` line if it got wiped.
6. Back in the popover, the **Doctor** section surfaces any problems `ConfigStore` picks up on the next reload, with one-click fixes.

## Project layout

```
keychord/
├── keychord/                # App sources
│   ├── Models/              # Account, ConfigModel, Diagnosis, …
│   ├── Services/            # AccountsStore, AccountProjector,
│   │                        # AccountImporter, IncludeInstaller,
│   │                        # ConfigStore, Doctor, Fixer, Prober, …
│   ├── Views/                # MenuBarContent, AccountsWindowView,
│   │                        # AccountDetailView, PopoverRows, …
│   ├── AppDelegate.swift
│   └── AppState.swift
├── keychordTests/           # Swift Testing unit tests
├── keychordUITests/
└── keychord.xcodeproj
```

## Contributing

Pull requests welcome — see [CONTRIBUTING.md](./CONTRIBUTING.md) for build, test, and commit-message guidelines.

Bug reports and feature ideas go to [GitHub Issues](https://github.com/yangflow/keychord/issues).

## License

[MIT](./LICENSE) © 2026 yangflow
