#!/usr/bin/env bash
#
# release.sh — Flint signed + notarized DMG release pipeline (DIST-03).
#
# Produces a Developer-ID-signed, notarized, stapled Flint.app and DMG that pass
# Gatekeeper. Signing goes through Xcode's Archive → Export (developer-id) path,
# which re-signs Sparkle's XPC services in the correct order.
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ NEVER recursively re-sign with the codesign deep flag here. It silently   │
# │ corrupts Sparkle's XPC service signatures (Installer.xpc / Downloader.xpc │
# │ / Autoupdate), and the app will be rejected or its auto-update will break │
# │ in the field. Xcode -exportArchive re-signs nested code inside-out.       │
# │ Apple removed the legacy notarization upload tool in Nov 2023 — only      │
# │ `xcrun notarytool` is supported.                                          │
# └──────────────────────────────────────────────────────────────────────────┘
#
# PREREQUISITES (see DISTRIBUTION.md "Prerequisites" — all human, one-time):
#   1. Apple Developer Program enrollment.
#   2. A "Developer ID Application" certificate in the login Keychain
#      (verify: `security find-identity -v -p codesigning`).
#   3. A stored notarytool keychain profile named NOTARYTOOL_PROFILE
#      (one-time: `xcrun notarytool store-credentials "NOTARYTOOL_PROFILE" \
#        --apple-id <id> --team-id <TEAMID> --password <app-specific-password>`).
#   4. create-dmg installed: `brew install create-dmg` (or `npm install -g create-dmg`).
#   5. scripts/exportOptions.plist has your real teamID filled in (placeholder by default).
#
# USAGE:
#   bash scripts/release.sh <version>        # e.g. bash scripts/release.sh 0.0.1
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCHEME="Flint"
CONFIGURATION="Release"
NOTARY_PROFILE="NOTARYTOOL_PROFILE"          # must match `notarytool store-credentials` name
APP_NAME="Flint.app"

# Resolve repo root (this script lives in scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

BUILD_DIR="${REPO_ROOT}/build"
EXPORT_DIR="${BUILD_DIR}/export"
DIST_DIR="${REPO_ROOT}/dist"
ARCHIVE_PATH="${BUILD_DIR}/Flint.xcarchive"
EXPORT_OPTIONS="${SCRIPT_DIR}/exportOptions.plist"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die()  { echo "❌ ERROR: $*" >&2; exit 1; }
info() { echo "▶ $*"; }
ok()   { echo "✅ $*"; }

# ---------------------------------------------------------------------------
# Arg + environment validation
# ---------------------------------------------------------------------------
VERSION="${1:-}"
[[ -n "${VERSION}" ]] || die "version argument required. Usage: bash scripts/release.sh <version>  (e.g. 0.0.1)"

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found — install Xcode."
command -v xcrun      >/dev/null 2>&1 || die "xcrun not found — install Xcode command line tools."
command -v create-dmg >/dev/null 2>&1 || die "create-dmg not found — install with: brew install create-dmg (or npm install -g create-dmg)."
[[ -f "${EXPORT_OPTIONS}" ]] || die "missing ${EXPORT_OPTIONS} — required for Developer ID export."

# Refuse to ship the Sparkle public-key placeholder from plan 03-03.
if /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "${REPO_ROOT}/Info.plist" 2>/dev/null | grep -q "PLACEHOLDER"; then
  die "Info.plist SUPublicEDKey is still the placeholder. Generate the real EdDSA key (see DISTRIBUTION.md) and replace it BEFORE releasing — Sparkle cannot add it later without locking users out of updates."
fi

# Confirm a notarytool profile is reachable (does not validate creds, only presence).
info "Using notarytool keychain profile: ${NOTARY_PROFILE} (run store-credentials once if missing)."

# ---------------------------------------------------------------------------
# Clean previous outputs for this run
# ---------------------------------------------------------------------------
info "Cleaning previous build/export/dist outputs"
rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}"
mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

# ---------------------------------------------------------------------------
# 1. Archive (Release) — Xcode produces a notarization-ready archive.
# ---------------------------------------------------------------------------
info "[1/9] Archiving ${SCHEME} (${CONFIGURATION}) → ${ARCHIVE_PATH}"
xcodebuild \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -archivePath "${ARCHIVE_PATH}" \
  archive \
  || die "xcodebuild archive failed."
ok "Archive created."

# ---------------------------------------------------------------------------
# 2. Export with Developer ID — re-signs Sparkle XPC services correctly.
#    No manual recursive re-signing; Xcode handles nested signing inside-out.
# ---------------------------------------------------------------------------
info "[2/9] Exporting Developer ID app → ${EXPORT_DIR}"
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}" \
  -exportPath "${EXPORT_DIR}" \
  || die "xcodebuild -exportArchive failed (check teamID/signing in ${EXPORT_OPTIONS})."

APP_PATH="${EXPORT_DIR}/${APP_NAME}"
[[ -d "${APP_PATH}" ]] || die "exported app not found at ${APP_PATH}."
ok "Exported ${APP_PATH}."

# ---------------------------------------------------------------------------
# 3. ZIP the app (ditto --keepParent) for notarytool submission.
# ---------------------------------------------------------------------------
APP_ZIP="${BUILD_DIR}/Flint.zip"
info "[3/9] Zipping app for notarization → ${APP_ZIP}"
rm -f "${APP_ZIP}"
ditto -c -k --keepParent "${APP_PATH}" "${APP_ZIP}" || die "ditto zip failed."
ok "Created ${APP_ZIP}."

# ---------------------------------------------------------------------------
# 4. Notarize the app ZIP and wait for the result.
# ---------------------------------------------------------------------------
info "[4/9] Submitting app to Apple notary service (--wait)"
xcrun notarytool submit "${APP_ZIP}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait \
  || die "notarytool submit (app) failed or was rejected. Run: xcrun notarytool log <submission-id> --keychain-profile ${NOTARY_PROFILE}"
ok "App notarized."

# ---------------------------------------------------------------------------
# 5. Staple the notarization ticket to the app.
# ---------------------------------------------------------------------------
info "[5/9] Stapling notarization ticket to app"
xcrun stapler staple "${APP_PATH}" || die "stapler staple (app) failed."
xcrun stapler validate "${APP_PATH}" || die "stapler validate (app) failed."
ok "App stapled + validated."

# ---------------------------------------------------------------------------
# 6. Gatekeeper assessment of the app.
# ---------------------------------------------------------------------------
info "[6/9] Verifying Gatekeeper acceptance (spctl)"
spctl -a -t exec -vvv "${APP_PATH}" \
  || die "spctl rejected the app — not 'accepted, source=Notarized Developer ID'."
ok "Gatekeeper: accepted (Notarized Developer ID)."

# ---------------------------------------------------------------------------
# 7. Build the DMG with create-dmg (notarization-ready layout).
# ---------------------------------------------------------------------------
info "[7/9] Building DMG with create-dmg → ${DIST_DIR}"
# create-dmg names the output "Flint <version>.dmg" from the app's CFBundleShortVersionString.
rm -f "${DIST_DIR}/Flint ${VERSION}.dmg"
create-dmg "${APP_PATH}" "${DIST_DIR}/" || die "create-dmg failed."

DMG_PATH="${DIST_DIR}/Flint ${VERSION}.dmg"
if [[ ! -f "${DMG_PATH}" ]]; then
  # Fall back to whatever .dmg create-dmg actually produced (name may vary by version metadata).
  DMG_PATH="$(ls -t "${DIST_DIR}"/*.dmg 2>/dev/null | head -1 || true)"
  [[ -n "${DMG_PATH}" && -f "${DMG_PATH}" ]] || die "create-dmg produced no .dmg in ${DIST_DIR}."
  info "Note: expected 'Flint ${VERSION}.dmg' but using produced DMG: ${DMG_PATH}"
fi
ok "DMG built: ${DMG_PATH}"

# ---------------------------------------------------------------------------
# 8. Notarize the DMG and wait.
# ---------------------------------------------------------------------------
info "[8/9] Submitting DMG to Apple notary service (--wait)"
xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait \
  || die "notarytool submit (DMG) failed or was rejected."
ok "DMG notarized."

# ---------------------------------------------------------------------------
# 9. Staple the DMG and final verify.
# ---------------------------------------------------------------------------
info "[9/9] Stapling notarization ticket to DMG"
xcrun stapler staple "${DMG_PATH}" || die "stapler staple (DMG) failed."
xcrun stapler validate "${DMG_PATH}" || die "stapler validate (DMG) failed."
ok "DMG stapled + validated."

echo
ok "RELEASE COMPLETE — signed, notarized, stapled."
echo "    App:  ${APP_PATH}"
echo "    DMG:  ${DMG_PATH}"
echo
echo "Next:"
echo "  • Copy the DMG into your updates/ folder and run generate_appcast (see scripts/dry-run-update.sh / DISTRIBUTION.md)."
echo "  • Confirm Sparkle XPC integrity: codesign --verify --deep --strict --verbose=2 \"${APP_PATH}\""
