# Changelog

Notable changes in each Agents release. A release's notes on GitHub are its section here, so a version's section must exist before its tag is pushed (see [docs/releasing.md](docs/releasing.md)).

## Unreleased

Reconstruction of Coincide as the native macOS app Agents: SwiftUI + AppKit UI over the `coincide-core` Rust runtime via the `coincide-macos-ffi` C-ABI bridge, with the Rust workspace in `Rust Backend/`.

- Native macOS app in `Agents/` with `AgentsTests/`; the Windows app (`windows/`), website (`website/`), Discord bot (`discord/`), and npm installer (`npm/`) are removed.
- System Assets imported from `dylans2010/Qwen-Code` at pinned revision `ac20a141`, indexed and retrieved by `SystemAssetManager`.
- System Toolset setting (System Tools by default, Provider Tools as the alternative) with a per-thread system prompt delivered to Codex and Claude only.
- Computer Use wired into the Swift app for real: the 20-tool engine catalog (observe, click, type, launch, move/resize) executes through the real engine dispatch via the FFI pump and the native macOS executor, with a Settings › Computer Use pane (enable switch, Accessibility/Screen Recording permissions) and an Inspector › Computer Use tab (run-a-tool form, real screenshots, action history). Screen recording is not available: the engine has no recording tool.
- Liquid Glass (macOS 26 native `glassEffect`) on the floating surfaces only — composer bar, `@`/`/` completions card, queued follow-ups, approval/question attention cards, toast banner, Jump to Latest pill, terminal exited-session banner — centralized as `glassPanel` / `glassCapsule` / `glassPanelTinted` in `AppTheme`; transcript tool cards, inspector cards, settings panes, and the welcome screen keep semantic fills, and sheets/popovers use the system glass chrome. Sidebar slimmed (232/264) and the conversation column focused to 800 with wider transcript padding. No build or visual check run in this environment; see README's Liquid Glass section for the full design note.
- CI path filters, sparse checkouts, and cargo working directories updated to the `Rust Backend/` layout; workflows for the deleted website, Discord bot, and Windows app removed.

## 0.1.0

Historical note: this section records the upstream 0.1.0 release as shipped. Agents → Check for Updates does not exist in the current app — the updater is dead in the shipped native app (see [docs/updater-audit.md](docs/updater-audit.md)).

The first public release of Agents, a native macOS app for the coding agents you already pay for.

- **Every agent, one window:** Claude Code, Codex, Cursor, Grok Build, OpenCode and Antigravity, each through its own command-line tool and your existing sign-in, with one model picker across them.
- **Switch agents mid-thread:** the next agent gets a recap of the turns it missed and continues in the same folder.
- Projects and threads with search, pinning, archiving, snoozing and a ⌘K command palette, plus chats without a project.
- Plan mode, approvals or full access, questions answered inline, attachments, `@` file mentions and `/` commands.
- Git built in: diffs, per-turn checkpoints, worktrees, commits, pushes and pull requests, and a GitHub PR workspace.
- An integrated terminal and a browser in every thread, which agents can drive when you allow it.
- Passkeys in the browser: sign in with passkeys saved in Bitwarden (you confirm each sign-in, with optional Touch ID), or sign in with your passkey in your default browser and import that sign-in into Agents.
- Computer Use (off by default), scheduled tasks, bots, dictation, Keep Awake, a usage dashboard and the `coincide` command-line tool.
- 19 languages (machine-translated; corrections are welcome).
- Ships as a notarized universal DMG for Apple silicon and Intel Macs, with `brew install --cask apoorvdarshan/tap/coincide` and `npx coincide-dev` as other ways to install. Agents → Check for Updates installs later releases.
