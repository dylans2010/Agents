# Coincide

[![CI](https://github.com/apoorvdarshan/coincide/actions/workflows/ci.yml/badge.svg)](https://github.com/apoorvdarshan/coincide/actions/workflows/ci.yml)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15854/badge)](https://www.bestpractices.dev/projects/15854)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/apoorvdarshan/coincide/badge)](https://scorecard.dev/viewer/?uri=github.com/apoorvdarshan/coincide)

Coincide is a native macOS application for coding agents built with **SwiftUI and AppKit**, powered in-process by the `coincide-core` Rust runtime and Google Antigravity ACP integration alongside Claude Code, Codex, Cursor, Grok Build, OpenCode, Lithos AI, and the ACP v1 agent registry. Coincide Remote is the separate iPhone and iPad companion.

## Build and Test on macOS

Install a Rust toolchain, Xcode, and `xcodegen` (`brew install xcodegen`).

```sh
# Build the in-process Rust staticlib FFI bridge backed by coincide-core
cargo build --release -p coincide-macos-ffi

# Generate Coincide.xcodeproj and build the Release native macOS app
xcodegen generate --spec project.yml
xcodebuild -project Coincide.xcodeproj -scheme Coincide -configuration Release \
  -derivedDataPath ./build/DerivedData build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run Swift & Rust test suites
xcodebuild test -project Coincide.xcodeproj -scheme Coincide \
  -derivedDataPath ./build/DerivedData \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
cargo test -p coincide-macos-ffi
cargo test -p coincide-core --locked
```

## Coincide Remote

The iOS companion app and its tests live in `CoincideRemote/`, `CoincideRemoteKit/`, `CoincideRemoteTests/`, and `CoincideRemoteUITests/`. Generate its Xcode project with `xcodegen generate --spec project-remote.yml`. Its store configuration is documented in [store/README.md](store/README.md).

## Repository

| Path | Purpose |
|---|---|
| `Coincide/` | Native macOS SwiftUI + AppKit application (Sidebar, Conversation, Composer, Inspector, Terminal, Settings, Commands) |
| `CoincideTests/` | Swift Testing unit and FFI roundtrip integration tests for macOS `Coincide` |
| `project.yml` | XcodeGen project specification for `Coincide.app` and `CoincideTests` |
| `crates/coincide-core/` | Portable Rust application core, SQLite storage, terminal PTYs, Git/GitHub, and Google Antigravity + provider runtimes |
| `crates/coincide-macos-ffi/` | C-ABI static library bridge (`libcoincide_macos_ffi.a`) linking `coincide-core` into native Swift 6 |
| `CoincideRemote/`, `CoincideRemoteKit/` | iOS companion and shared cross-platform `Codable` protocol package |
| `crates/coincide-desktop/` | Earlier cross-platform GPUI desktop implementation |
| `website/`, `discord/` | Website and community support service |

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Coincide follows the design of [T3 Code](https://github.com/pingdotgg/t3code). Third-party attributions are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Coincide is released under the [MIT License](LICENSE).
