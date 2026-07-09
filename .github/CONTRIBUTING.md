# Contributing to Flint

Thanks for your interest in improving Flint! This is a native macOS menubar
toolkit for developers, built with SwiftUI. Contributions of all kinds are
welcome — bug reports, tools, fixes, and docs.

## Ground rules

- Be respectful. This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
- Keep the core value in mind: **every tool must be instant, correct, and never
  crash on bad input** — fully offline, no network dependency.
- Match the existing style: SwiftUI + MVVM, Swift 5.9+. See
  [`CLAUDE.md`](../CLAUDE.md) for the full stack rationale and native-vs-package
  decisions.

## Getting started

Requires **Xcode 16.3+** and **macOS 14.0+**.

```bash
git clone https://github.com/chutiponh/flint.git
cd flint
open Flint.xcodeproj    # then ⌘R to run
```

Run the tests before submitting:

```bash
xcodebuild test -project Flint.xcodeproj -scheme Flint -destination 'platform=macOS'
```

## Submitting changes

1. Fork the repo and create a branch from `main`.
2. Make your change. Keep the diff focused — one concern per PR.
3. Add or update tests for any non-trivial logic (see `FlintTests/`).
4. Make sure the app builds and tests pass.
5. Open a pull request using the template. Link any related issue.

## Reporting bugs & requesting features

Use the [issue templates](https://github.com/chutiponh/flint/issues/new/choose).
For security issues, **do not open a public issue** — see the
[Security Policy](SECURITY.md).

## Commit messages

Use clear, conventional-style messages where practical
(`fix:`, `feat:`, `docs:`). Keep the subject line under ~72 characters.
