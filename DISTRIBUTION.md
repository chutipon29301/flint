# Flint — Distribution & Release Checklist

This document is the authoritative checklist for shipping Flint as a **signed,
notarized DMG that passes Gatekeeper** (DIST-03) with a working **Sparkle
EdDSA-signed auto-update** path (DIST-04).

The mechanics are encoded in two scripts:

- [`scripts/release.sh`](scripts/release.sh) — Archive → Developer ID export →
  notarize → staple → create-dmg → notarize DMG → staple DMG.
- [`scripts/dry-run-update.sh`](scripts/dry-run-update.sh) — local
  v0.0.1 → v0.0.2 Sparkle update dry-run that proves the auto-update loop **before**
  the first public release.

---

## NEVER (non-negotiable anti-patterns)

> Each of these has caused a shipped-and-broken release in the wild. They are not
> stylistic preferences.

- **NEVER run `codesign --deep`.** It silently corrupts Sparkle's nested XPC
  service signatures (`Installer.xpc`, `Downloader.xpc`, `Autoupdate`). Use the
  Xcode **Archive → Export (Developer ID)** path (`xcodebuild -exportArchive` with
  `method=developer-id`), which re-signs nested code in the correct inside-out
  order. `release.sh` enforces this — it contains no `codesign --deep`.
- **NEVER use `altool`.** Apple removed it from the notary service in November
  2023. Use `xcrun notarytool` only.
- **NEVER lose the Sparkle EdDSA private key.** It lives in the **login Keychain**
  after `generate_keys`. Back it up off-machine (1Password / a CI secret store)
  the moment you generate it. If you lose it, you can never sign another update
  that existing users will accept — they are permanently locked out of auto-update.
- **NEVER ship without the real `SUPublicEDKey` already embedded.** Sparkle
  refuses to *add* a public key in a later release (it treats that as a security
  downgrade), which permanently breaks auto-update for everyone who installed the
  keyless build. The public key MUST be present **from the very first release**.
- **NEVER commit the private key** to the repo, dotfiles, env vars, or CI logs.
  Only the **public** key (`SUPublicEDKey`) belongs in `Info.plist`.

---

## Prerequisites (one-time, human-only)

These cannot be automated by the release scripts — they require Apple Developer
Program credentials and external tools.

1. **Apple Developer Program enrollment** — required to obtain a Developer ID cert.
2. **Developer ID Application certificate** installed in the **login Keychain**.
   Verify:
   ```bash
   security find-identity -v -p codesigning
   # Expect a line like: "Developer ID Application: Your Name (TEAMID)"
   ```
3. **App-specific password** for notarization — create at
   <https://appleid.apple.com> → Sign-In and Security → App-Specific Passwords.
4. **Stored notarytool credentials** (one-time, writes to the Keychain):
   ```bash
   xcrun notarytool store-credentials "NOTARYTOOL_PROFILE" \
     --apple-id  "you@example.com" \
     --team-id   "TEAMID" \
     --password  "app-specific-password"
   ```
   The profile name `NOTARYTOOL_PROFILE` must match the one in `release.sh`.
5. **create-dmg** installed (not bundled with Xcode):
   ```bash
   brew install create-dmg        # recommended
   # or: npm install -g create-dmg   (Node.js 22 is present on this machine)
   create-dmg --version            # confirm it resolves
   ```
6. **Team ID filled into `scripts/exportOptions.plist`** — replace
   `REPLACE_WITH_YOUR_TEAM_ID` with your real 10-character Team ID.
7. **Sparkle EdDSA key generated and backed up** — see the next section.

---

## Sparkle EdDSA key — generate ONCE, back up forever (DIST-04)

The Info.plist currently ships a **placeholder** `SUPublicEDKey` (from plan 03-03).
Before any release you must replace it with a real key:

1. Locate Sparkle 2.9.3's `generate_keys` tool (resolved via SPM into DerivedData):
   ```bash
   find ~/Library/Developer/Xcode/DerivedData -name generate_keys -path '*Sparkle*' 2>/dev/null | head -1
   # typically: .../SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```
2. Run it **once**. It stores the **private** key in the login Keychain and prints
   the **public** key:
   ```bash
   /path/to/Sparkle/bin/generate_keys
   # Output: "Public key (SUPublicEDKey value): <base64-string>"
   ```
3. Replace the placeholder in `Info.plist`:
   ```bash
   /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey <base64-string>" Info.plist
   /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Info.plist   # confirm real key
   ```
4. **Back up the private key off-machine** (Keychain Access → search "Sparkle" /
   "ed25519" → export, store in 1Password / CI secret). It must never enter the repo.
5. `generate_appcast` later reads this private key from the Keychain automatically
   to sign each update; you will not type it again.

> `release.sh` refuses to run while `SUPublicEDKey` is still the placeholder.

---

## Version bump convention

Flint uses two coordinated version numbers per release:

| Field (build setting)      | Info.plist key              | Meaning                          | Example bump        |
|----------------------------|-----------------------------|----------------------------------|---------------------|
| `MARKETING_VERSION`        | `CFBundleShortVersionString`| Human-facing version             | `0.0.1` → `0.0.2`   |
| `CURRENT_PROJECT_VERSION`  | `CFBundleVersion`           | **Monotonic integer** build no.  | `1` → `2` → `3`     |

- `CFBundleVersion` MUST be a **plain incrementing integer** (`1`, `2`, `3`, …),
  never a dotted string. Sparkle compares updates by this number, and it MUST match
  the `sparkle:version` value in `appcast.xml`.
- Bump both for every release. The dry-run uses `CFBundleVersion=1` for v0.0.1 and
  `CFBundleVersion=2` for v0.0.2.

Set them in the project (or via `xcodebuild ... MARKETING_VERSION=0.0.2 CURRENT_PROJECT_VERSION=2`).

---

## Release procedure

1. **Bump the version** (`MARKETING_VERSION` + integer `CURRENT_PROJECT_VERSION`).
2. **Confirm the real `SUPublicEDKey`** is in `Info.plist` (not the placeholder).
3. **Run the release script:**
   ```bash
   bash scripts/release.sh 0.0.1
   ```
   This archives, exports with Developer ID, notarizes + staples the app, verifies
   Gatekeeper (`spctl`), builds the DMG with `create-dmg`, then notarizes + staples
   the DMG. It exits non-zero if any verification fails.
4. **Sanity-check Sparkle XPC integrity** (proves no `--deep` corruption):
   ```bash
   codesign --verify --deep --strict --verbose=2 build/export/Flint.app
   ```
5. **Generate / update the appcast** over your `updates/` folder (see below).
6. **Swap `SUFeedURL` to the production HTTPS URL** *before* v1.0 (see next section).
7. **Publish** `appcast.xml`, the DMG(s), and any `.delta` files to your HTTPS host
   at the path the `SUFeedURL` points to.

---

## Appcast generation & SUFeedURL

```bash
# Place the notarized+stapled DMG(s) into an updates/ folder, then:
/path/to/Sparkle/bin/generate_appcast updates/
# → writes updates/appcast.xml (EdDSA-signed, reads private key from Keychain)
# → writes delta files for incremental updates
```

- **`SUFeedURL` placeholder swap:** `Info.plist` currently points `SUFeedURL` at
  `http://localhost:8000/appcast.xml` for the local dry-run only. **Before v1.0**,
  replace it with the **production HTTPS** appcast URL:
  ```bash
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL https://your-host/appcast.xml" Info.plist
  ```
- Sparkle requires HTTPS for production feeds. Plain `http://localhost` is tolerated
  only for the local dry-run; if Sparkle rejects it even locally, use a tunneling
  service (ngrok) or a staging HTTPS server (see `scripts/dry-run-update.sh`).

---

## Auto-update dry-run (DIST-04 validation — do this before v1.0)

Run the scripted v0.0.1 → v0.0.2 dry-run to prove the whole update loop end-to-end:

```bash
bash scripts/dry-run-update.sh
```

It builds v0.0.1 (`CFBundleVersion=1`) and v0.0.2 (`CFBundleVersion=2`), signs both
with `generate_appcast`, serves the appcast locally, resets `SULastCheckTime` to
force an immediate check, and walks you through confirming Sparkle detects and
installs v0.0.2. See the script header and "Deferred Manual Verification" in the
plan summary for the exact pass criteria.

---

## Final pre-release checklist

- [ ] Apple Developer Program enrolled; Developer ID Application cert in Keychain.
- [ ] `NOTARYTOOL_PROFILE` stored (`xcrun notarytool store-credentials`).
- [ ] `create-dmg` installed and on `PATH`.
- [ ] `scripts/exportOptions.plist` `teamID` set to the real Team ID.
- [ ] Real `SUPublicEDKey` in `Info.plist` (NOT the placeholder).
- [ ] Sparkle private key backed up off-machine; never committed.
- [ ] `MARKETING_VERSION` + integer `CFBundleVersion` bumped.
- [ ] `bash scripts/release.sh <version>` completes; DMG notarized + stapled.
- [ ] Installed DMG opens with **no Gatekeeper warning**
      (`spctl -a -t exec -vvv /Applications/Flint.app` → "Notarized Developer ID").
- [ ] `codesign --verify --deep --strict` passes (Sparkle XPC intact).
- [ ] v0.0.1 → v0.0.2 dry-run completed; update detected, installed, restarted at v0.0.2.
- [ ] `SUFeedURL` swapped to the **production HTTPS** URL.
- [ ] `appcast.xml` + DMG + deltas published to the HTTPS host.
