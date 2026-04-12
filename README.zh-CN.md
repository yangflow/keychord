# keychord

> 在 macOS 菜单栏管理多个 Git 身份——不用再手改 dotfiles。

简体中文 · [English](./README.md)

<p align="center">
  <img src="assets/menubar-popover.png" width="280" alt="菜单栏弹窗">
  <img src="assets/accounts-window.png" width="560" alt="账号管理窗口">
</p>

keychord 是一个常驻菜单栏的 macOS 小工具，让你在同一台 Mac 上同时保留多个 GitHub 账号——个人、公司、开源——每个账号都有自己的 SSH key、git name/email、URL 改写规则，以及可选的 `gitdir:` 目录级激活条件。keychord 管理着一个独立的 JSON 文件，并由它生成*受管*的 SSH config 与 gitconfig，只在你真实的 `~/.ssh/config` 和 `~/.gitconfig` 里塞一行 `Include`。你自己手写的 dotfiles 完全不被触碰。

## 为什么需要它

在同一台 Mac 上用多个 Git 身份，常见的做法要么是:

- 手改 `~/.ssh/config` + `~/.gitconfig` + `~/.gitconfig-work`，然后祈祷每次 `git clone` 记得用对 alias;
- 到处写 `GIT_SSH_COMMAND`。

keychord 把"账号集合"当成一等公民，用一个专门的窗口做 CRUD，并把结果回写进真实的 config 文件——可审计、可回滚，而且不动你手写的任何一行。

## 功能

<p align="center">
  <img src="assets/import-picker.png" width="320" alt="导入选择器">
  <img src="assets/keygen-sheet.png" width="320" alt="SSH Key 生成器">
</p>

- **账号 CRUD**：原生 `NavigationSplitView` 窗口增删改查账号。真实来源是 `~/.config/keychord/accounts.json`。
- **`gitdir:` 目录级作用域**：每个账号可以是全局，也可以通过 git 自带的 `includeIf gitdir:` 机制绑定到某个工作目录。
- **URL 改写**：每个账号都能带自己的 `insteadOf` / `pushInsteadOf` 规则。
- **选择性导入**：自动从你现有的 `~/.ssh/config` + `~/.gitconfig` 推断出逻辑账号，然后用勾选框选取要导入的账号。已存在的 alias 会自动标注并跳过。
- **Doctor & Fixer**：检测常见配置问题（key 丢失、权限错、悬空 `Include`、`IdentityFile` 冲突），并给出一键修复。
- **SSH 端口选择**：每个账号可单独设置 Direct 22 / SSL 443。22 端口被墙时可切到 443。
- **SSH Key 生成器**：在应用内生成 ed25519 或 RSA key，自带安全文件名与正确权限。
- **原子备份**：每次写入前都会在 `~/.config/keychord/backups/` 为 `accounts.json` 做快照，可从 Restore 视图浏览和恢复。
- **iCloud 同步**：可选功能，通过 `NSUbiquitousKeyValueStore` 在多台 Mac 之间同步账号列表。SSH key 留在本地，只同步元数据。
- **探针**：对每个 host 执行 `ssh -T git@<alias>`，一眼看出哪个账号还能正常认证。
- **常驻菜单栏**：`LSUIElement = YES`，没有 Dock 图标、不抢焦点。把一个文件夹拖到菜单栏图标上可以直接查出那个目录下会用哪个账号 push。

## 它的工作原理（managed-file 模型）

keychord 从不改写你现有 config 文件的正文。它做的事是:

1. `accounts.json` 是唯一的真实来源。
2. 每次保存，`AccountProjector` 在 `~/.config/keychord/` 下写出三种*受管*文件:
   - `ssh_config.managed`：每个账号一个 `Host` 块
   - `gitconfig.managed`：全局 `[user]`、URL 改写规则、scoped 账号的 `[includeIf]` 指针
   - `gitconfig-<uuid>.managed`：每个 `gitdir:` scoped 账号一份，包含 `[user]` + `[core] sshCommand`
3. `IncludeInstaller` 只在你真实的 `~/.ssh/config` 和 `~/.gitconfig` 顶部*幂等地*注入一段用 marker 包裹的 `Include`:
   ```
   # --- keychord managed ---
   Include ~/.config/keychord/ssh_config.managed
   # --- keychord managed end ---
   ```
4. marker 之外的一切内容原样保留。卸载就是把 marker 块删掉。

所以 keychord 能和手写 config、dotfile 管理器、home-manager 等等共存。

## 环境要求

- macOS 26.2 或更高
- Apple Silicon

## 安装

### Homebrew（推荐）

```bash
brew tap yangflow/keychord
brew install --cask keychord
```

### 手动下载

从 [Releases](https://github.com/yangflow/keychord/releases) 下载最新的 `KeyChord-<version>.dmg`，打开后将 **KeyChord.app** 拖到 `/Applications`。

如果应用未经公证，首次启动前需要清除隔离标记:

```bash
xattr -cr /Applications/KeyChord.app
open /Applications/KeyChord.app
```

### 从源码构建

```bash
git clone https://github.com/yangflow/keychord.git
cd keychord
open keychord.xcodeproj
```

选 `keychord` scheme，⌘R 运行。或者用构建脚本生成独立的 `.app`:

```bash
./scripts/build.sh
mv dist/KeyChord.app /Applications/
```

首次启动时按需创建 `~/.config/keychord/`；在你保存账号之前，真实 dotfiles 不会被写入任何内容。

### 跑测试

```bash
xcodebuild test \
  -scheme keychord \
  -destination 'platform=macOS' \
  -only-testing keychordTests \
  CODE_SIGNING_ALLOWED=NO
```

单元测试覆盖 SSH config parser、git config IO 层、`AccountProjector`、`AccountsStore`、`AccountImporter`、`Doctor`、`Fixer`、`BackupService`，以及 keygen 服务。

## 使用

1. 点击菜单栏图标。弹出窗口显示账号列表、Doctor 诊断信息，以及当前仓库上下文。
2. 点击账号列表底部的 **+** 行来添加新账号（会打开账号管理窗口），或者点任意账号行跳到详情。
3. 在账号窗口中，使用侧栏底部的工具栏:
   - **+** 新建账号
   - **钥匙** 生成 SSH key
   - **时钟** 浏览并恢复备份
   - **导入** 从现有配置检测并选择性导入账号
   - **iCloud** 配置云同步
4. 填写 label、git name/email、SSH alias、key path，以及可选的 `gitdir:` scope 和 URL 改写。⌘S 保存。
5. 每次保存都会重新生成 managed 文件，并在真实 config 里重新安装 `Include`（如果被误删）。
6. 回到 popover，**Doctor** 区会列出检测到的配置问题，附带一键修复按钮。

## 目录结构

```
keychord/
├── keychord/                # App 源码
│   ├── Models/              # Account, ConfigModel, Diagnosis
│   ├── Services/            # AccountsStore, AccountProjector,
│   │                        # AccountImporter, IncludeInstaller,
│   │                        # ConfigStore, Doctor, Fixer, Prober,
│   │                        # BackupService, CloudSyncService,
│   │                        # KeygenService, …
│   ├── Views/               # MenuBarContent, AccountsWindowView,
│   │                        # AccountDetailView, AccountsSidebar,
│   │                        # ImportPickerView, RestoreView,
│   │                        # CloudSyncView, KeygenView, …
│   ├── AppDelegate.swift
│   └── AppState.swift
├── keychordTests/           # Swift Testing 单元测试
├── keychordUITests/
├── scripts/                 # build.sh, release.sh, generate-icon
└── keychord.xcodeproj
```

## 卸载

1. 从菜单栏退出 KeyChord（电源图标，或 ⌘Q）。
2. 删除 `/Applications/KeyChord.app`。
3. 删除托管配置（可选）:
   ```bash
   rm -rf ~/.config/keychord
   ```
4. 删除 keychord 注入的 `Include` 块——在 `~/.ssh/config` 和 `~/.gitconfig` 中找到 `# --- keychord managed ---` 到 `# --- keychord managed end ---` 之间的内容删掉即可。

如果通过 Homebrew 安装: `brew uninstall --cask keychord`。

## 发布

维护者发版流程:

```bash
# 1. 构建 DMG（unsigned / signed / notarized）
./scripts/release.sh 0.2.0

# 2. 创建 GitHub Release 并上传
gh release create v0.2.0 \
  --title 'KeyChord 0.2.0' \
  dist/KeyChord-0.2.0.dmg

# 3. 更新 Homebrew cask 的版本号 + SHA256
#    （SHA256 在 dist/KeyChord-0.2.0.dmg.sha256）
```

`release.sh` 通过环境变量支持四种模式:

| 模式 | 环境变量 | 结果 |
|------|----------|------|
| **unsigned** | （无） | Ad-hoc 签名 DMG。Gatekeeper 首次启动时会提示。 |
| **signed** | `DEVELOPER_ID_APPLICATION` | Developer ID 签名 DMG。 |
| **notarized** | signed + `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | 公证 + staple。完全通过 Gatekeeper。 |
| **sparkle** | notarized + `SPARKLE_PRIVATE_KEY` | 额外输出 Sparkle Ed25519 签名，用于 appcast.xml。 |

## 参与贡献

欢迎 PR——构建、测试、commit 规范见 [CONTRIBUTING.md](./CONTRIBUTING.md)。

Bug 和需求请走 [GitHub Issues](https://github.com/yangflow/keychord/issues)。

## License

[MIT](./LICENSE) © 2026 yangflow
