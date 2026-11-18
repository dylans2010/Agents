# Agents

[![CI](https://github.com/apoorvdarshan/coincide/actions/workflows/ci.yml/badge.svg)](https://github.com/apoorvdarshan/coincide/actions/workflows/ci.yml)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15854/badge)](https://www.bestpractices.dev/projects/15854)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/apoorvdarshan/coincide/badge)](https://scorecard.dev/viewer/?uri=github.com/apoorvdarshan/coincide)

Agents is a native macOS application for coding agents built with **SwiftUI and AppKit**, powered in-process by the `coincide-core` Rust runtime and Google Antigravity ACP integration alongside Claude Code, Codex, Cursor, Grok Build, OpenCode, Lithos AI, and the ACP v1 agent registry. Coincide Remote is the separate iPhone and iPad companion.

## Build and Test on macOS

Install a Rust toolchain, Xcode, and `xcodegen` (`brew install xcodegen`).

```sh
# Build the in-process Rust staticlib FFI bridge backed by coincide-core
cargo build --release --manifest-path "Rust Backend/Cargo.toml" -p coincide-macos-ffi

# Build the stdio MCP server that serves the System Tools to provider CLIs
cargo build --release --manifest-path "Rust Backend/Cargo.toml" -p coincide-mcp-server

The Xcode preBuildScript runs both cargo builds on every build (cargo itself is incremental, so an unchanged tree rebuilds fast); it never skips a build because the artifacts already exist.

# Generate Agents.xcodeproj and build the Release native macOS app
xcodegen generate --spec project.yml
xcodebuild -project Agents.xcodeproj -scheme Agents -configuration Release \
  -derivedDataPath ./build/DerivedData build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run Swift & Rust test suites
xcodebuild test -project Agents.xcodeproj -scheme Agents \
  -derivedDataPath ./build/DerivedData \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
cargo test --manifest-path "Rust Backend/Cargo.toml" -p coincide-macos-ffi
cargo test --manifest-path "Rust Backend/Cargo.toml" -p coincide-core --locked
cargo test --manifest-path "Rust Backend/Cargo.toml" -p coincide-mcp-server
```

## Coincide Remote

The iOS companion app and its tests live in `CoincideRemote/`, `CoincideRemoteKit/`, `CoincideRemoteTests/`, and `CoincideRemoteUITests/`. Generate its Xcode project with `xcodegen generate --spec project-remote.yml`. Its store configuration is documented in [store/README.md](store/README.md).

## Repository

| Path | Purpose |
|---|---|
| `Agents/` | Native macOS SwiftUI + AppKit application (Sidebar, Conversation, Composer, Inspector, Terminal, Settings, Commands) |
| `AgentsTests/` | Swift Testing unit and FFI roundtrip integration tests for macOS `Agents` |
| `project.yml` | XcodeGen project specification for `Agents.app` and `AgentsTests` |
| `Rust Backend/crates/coincide-core/` | Portable Rust application core, SQLite storage, terminal PTYs, Git/GitHub, and Google Antigravity + provider runtimes |
| `Rust Backend/crates/coincide-macos-ffi/` | C-ABI static library bridge (`libcoincide_macos_ffi.a`) linking `coincide-core` into native Swift 6 |
| `Rust Backend/crates/coincide-mcp-server/` | Standalone stdio MCP server (`coincide-mcp-server`) serving the 326 System Tools plus SystemAssets resources/prompts to provider CLIs |
| `Rust Backend/crates/coincide-desktop/` | Earlier cross-platform GPUI desktop implementation |
| `CoincideRemote/`, `CoincideRemoteKit/` | iOS companion and shared cross-platform `Codable` protocol package |
| `docs/` | Historical acceptance records and feature documentation |
| `scripts/` | Release, sync, and Rust test scripts |
| `store/` | Coincide Remote App Store release configuration |

A literal source-dir-plus-`.xcodeproj`-only root is not possible here: the Rust backend workspace and the XcodeGen spec have to live somewhere, so the backend lives in `Rust Backend/` and the spec in `project.yml` at the root.

## System Assets

Assist's system prompt and tool guidance come from System Assets (`Agents/Resources/SystemAssets/`), imported from [`dylans2010/Qwen-Code`](https://github.com/dylans2010/Qwen-Code) (`Sources/QwenCode/Resources/SystemAssets`) at pinned revision `ac20a141`. Re-sync with `scripts/sync-system-assets.sh`; the import is pinned, never floating.

## System Toolset

Settings › General › Agent Tools offers two toolsets: **System Tools** (default) and **Provider Tools**. System Tools runs 326 tools (63 distinct actions) behind a system prompt built from the System Assets; Provider Tools uses the provider's own tools with no system prompt. A per-thread system prompt is delivered as a genuine developer/system instruction only for **Codex and Claude**; other providers receive the tools and assets through the bundled MCP server instead. See [docs/SYSTEM-TOOLSET.md](docs/SYSTEM-TOOLSET.md).

## Liquid Glass

Agents targets macOS 26 and uses the native Liquid Glass APIs for its floating and overlay surfaces: the composer bar, the `@`/`/` completions card, queued follow-ups, approval and question attention cards, the toast banner, the floating Jump to Latest pill, and the terminal exited-session banner. The shared styles live in `Agents/Core/AppTheme.swift` (`glassPanel`, `glassCapsule`, `glassPanelTinted`); they wrap SwiftUI `glassEffect(.regular, in:)` and nothing else, so the glass language stays consistent and no view carries a one-off glass modifier. Attention cards keep their semantic tint and stroke (warning for approvals, accent for questions) because the tint is the signal, not decoration.

Glass is deliberately not used in the content layer: transcript tool-call and result cards, inspector diff/git/files/workers cards, settings panes, and the welcome screen keep their semantic fills so tool activity stays prominent and readable. Sheets and popovers (command palette, model picker, rename, checkout, bot editor, session import) rely on the system glass chrome macOS 26 applies to those containers instead of adding a second glass layer. All glass and material choices use semantic or dynamic colors only, so they read in both Light and Dark mode, and no control is hidden behind hover-only or glass-only affordances.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Agents follows the design of [T3 Code](https://github.com/pingdotgg/t3code). Third-party attributions are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Agents is released under the [MIT License](LICENSE).
