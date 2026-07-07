<div align="center">

<img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="Flint icon">

# Flint

**A native macOS menubar toolkit for developers.**
Paste content, get the right transformation in under a second — fully offline, from anywhere on the system.

![Platform](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)
![Offline](https://img.shields.io/badge/network-none-brightgreen)

</div>

## What it does

Flint lives in your menubar and opens in under a second via a global hotkey. Every tool runs **100% on-device** — no network, no account, no subscription. Paste from the clipboard and Flint auto-detects the likely tool.

## Tools

| Tool | What it does |
|------|--------------|
| **JSON Formatter** | Pretty-print, minify, and validate JSON |
| **Base64 Encoder/Decoder** | Encode and decode Base64 text |
| **JWT Decoder** | Decode and inspect JSON Web Tokens |
| **Hash Generator** | MD5, SHA-1/256/384/512, CRC32 |
| **UUID Generator** | Generate v4 UUIDs |
| **Unix Timestamp Converter** | Convert between Unix time and human dates |
| **URL Encoder/Decoder** | Percent-encode and decode URLs |
| **Number Base Converter** | Convert between binary, octal, decimal, hex |
| **Regex Tester** | Test regular expressions live against sample text |
| **Text Diff** | Line- and word-level diff between two texts |
| **Color Converter** | Convert between HEX, RGB, HSL, OKLCH + eyedropper |
| **Markdown Previewer** | Live GitHub-flavored Markdown preview |
| **Image Compressor** | Compress and quantize PNG images |

## Features

- ⚡ **Instant** — cold start < 500ms, hotkey-to-popover < 200ms
- 🔒 **Fully offline** — zero network dependency, nothing leaves your Mac
- 📋 **Clipboard auto-detect** — paste and Flint suggests the right tool
- 🔍 **Searchable history** — recent transformations, searchable
- ⌨️ **Global hotkey** — open from any app, no window switching
- 🚀 **Launch at login** — always one keystroke away
- 🛡️ **Never crashes on bad input** — all inputs validated gracefully

## Install

### Homebrew (recommended)

```bash
brew tap chutiponh/flint
brew install --cask flint
```

If Homebrew asks you to trust the tap, run `brew trust chutiponh/flint` and install again. The cask strips the quarantine flag on install, so the app opens without a Gatekeeper prompt.

### With an AI coding agent

Paste this prompt into Claude Code, Cursor, or any AI terminal agent:

```text
Install the Flint macOS app via Homebrew. Run:
  brew tap chutiponh/flint
  brew trust chutiponh/flint    # third-party tap, required once by Homebrew 6.0+
  brew install --cask flint
If any step fails, show me the error. When done, confirm Flint.app is in /Applications.
```

### Manual (DMG)

Download the latest `Flint-x.y.z.dmg` from [**Releases**](../../releases), open it, and drag **Flint** to Applications.

> **First launch:** This build is not notarized by Apple, so macOS shows an "unverified developer" warning. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**. You only do this once.
>
> Terminal alternative: `xattr -dr com.apple.quarantine /Applications/Flint.app`

## Update

### Homebrew

```bash
brew update           # refresh the tap
brew upgrade --cask flint
```

`brew update` pulls the latest cask; `brew upgrade --cask flint` replaces the app with the newest release. Run `brew info --cask flint` to see the available vs. installed version.

### Manual (DMG)

Download the latest `Flint-x.y.z.dmg` from [**Releases**](../../releases), open it, and drag **Flint** to Applications, replacing the old copy. Quit Flint first (menubar icon → Quit) if it's running.

> **In-app auto-update is not available yet.** It requires signed + notarized builds via Sparkle (see [Sponsor](#sponsor)). Until then, update through Homebrew or the DMG.

## Build from source

Requires **Xcode 16.3+** and **macOS 14.0+**.

```bash
git clone https://github.com/chutiponh/flint.git
cd flint
open Flint.xcodeproj    # then ⌘R
```

Or build a distributable DMG:

```bash
bash scripts/release-free.sh    # unsigned/ad-hoc DMG → dist/
```

Maintainers with an Apple Developer account can produce a signed + notarized DMG with `scripts/release.sh` (see `DISTRIBUTION.md`).

## Tech

SwiftUI + MVVM · `MenuBarExtra` · GRDB (history) · KeyboardShortcuts (global hotkey) · swift-markdown · CryptoKit. See [`CLAUDE.md`](CLAUDE.md) for the full stack rationale.

## Sponsor

Flint is free and offline-first. If it saves you time, consider [**sponsoring**](https://github.com/sponsors/chutiponh).

**First goal — $99/year:** fund Apple Developer Program enrollment so releases can be **signed + notarized**. That removes the "unverified developer" warning on install and re-enables in-app auto-update.

## License

MIT
