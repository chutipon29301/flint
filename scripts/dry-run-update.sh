#!/usr/bin/env bash
#
# dry-run-update.sh — Flint local v0.0.1 → v0.0.2 Sparkle update dry-run (DIST-04).
#
# Proves the EdDSA-signed auto-update loop end-to-end BEFORE the first public
# release: builds v0.0.1 and v0.0.2, signs both with generate_appcast, serves the
# appcast locally over HTTP, forces an immediate update check, and walks you
# through confirming Sparkle detects + installs v0.0.2.
#
# This orchestrates every step that can be automated and PRINTS the manual
# verification steps (launching the installed app, confirming the update sheet)
# where automation is impossible.
#
# PREREQUISITES (same credential-gated setup as release.sh — see DISTRIBUTION.md):
#   • Developer ID cert + NOTARYTOOL_PROFILE + create-dmg (release.sh needs them).
#   • Real Sparkle EdDSA key generated; private key in login Keychain (generate_appcast
#     reads it to sign the DMGs — you will get a Keychain access prompt).
#   • Info.plist SUFeedURL = http://localhost:8000/appcast.xml (the placeholder from
#     plan 03-03) so the served appcast matches what the app checks.
#
# USAGE:
#   bash scripts/dry-run-update.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BUNDLE_ID="com.flint.app"
HTTP_PORT=8000
FEED_PATH="appcast.xml"
V1="0.0.1"
V2="0.0.2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

RELEASE_SH="${SCRIPT_DIR}/release.sh"
DIST_DIR="${REPO_ROOT}/dist"
UPDATES_DIR="${REPO_ROOT}/updates"
INSTALLED_APP="/Applications/Flint.app"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die()    { echo "❌ ERROR: $*" >&2; exit 1; }
info()   { echo "▶ $*"; }
ok()     { echo "✅ $*"; }
manual() { echo "👉 MANUAL: $*"; }

# ---------------------------------------------------------------------------
# Locate Sparkle's generate_appcast (resolved into DerivedData by SPM).
# ---------------------------------------------------------------------------
find_generate_appcast() {
  local found
  found="$(find "${HOME}/Library/Developer/Xcode/DerivedData" \
            -name generate_appcast -path '*Sparkle*' -perm -u+x 2>/dev/null | head -1 || true)"
  if [[ -z "${found}" ]]; then
    # Also check a local SPM checkout, if the project ever vendors one.
    found="$(find "${REPO_ROOT}" -name generate_appcast -path '*Sparkle*' -perm -u+x 2>/dev/null | head -1 || true)"
  fi
  echo "${found}"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
[[ -f "${RELEASE_SH}" ]] || die "missing ${RELEASE_SH} — Task 2 output required."
command -v python3 >/dev/null 2>&1 || die "python3 not found — needed to host the appcast."
command -v defaults >/dev/null 2>&1 || die "defaults not found (macOS only)."

GENERATE_APPCAST="$(find_generate_appcast)"
[[ -n "${GENERATE_APPCAST}" ]] || die "could not locate Sparkle's generate_appcast. Build the app once (so SPM resolves Sparkle 2.9.3), or check ~/Library/Developer/Xcode/DerivedData/.../SourcePackages/artifacts/sparkle/Sparkle/bin/."
info "Using generate_appcast: ${GENERATE_APPCAST}"

mkdir -p "${UPDATES_DIR}"

# ---------------------------------------------------------------------------
# 1. Build + notarize v0.0.1 (CFBundleVersion = 1) and stage its DMG.
# ---------------------------------------------------------------------------
info "[1/9] Building + notarizing v${V1} (CFBundleVersion=1)"
manual "Set MARKETING_VERSION=${V1} and CURRENT_PROJECT_VERSION=1 before this step"
manual "(in Xcode build settings, or pass them through to xcodebuild in release.sh)."
bash "${RELEASE_SH}" "${V1}" || die "release.sh ${V1} failed."

V1_DMG="${DIST_DIR}/Flint ${V1}.dmg"
[[ -f "${V1_DMG}" ]] || V1_DMG="$(ls -t "${DIST_DIR}"/*.dmg 2>/dev/null | head -1 || true)"
[[ -n "${V1_DMG}" && -f "${V1_DMG}" ]] || die "v${V1} DMG not found in ${DIST_DIR}."
cp "${V1_DMG}" "${UPDATES_DIR}/"
ok "Staged $(basename "${V1_DMG}") into updates/."

# ---------------------------------------------------------------------------
# 2. Generate the initial appcast (v0.0.1 only). Signs with the Keychain key.
# ---------------------------------------------------------------------------
info "[2/9] Running generate_appcast over updates/ (v${V1} only)"
manual "Grant Keychain access when prompted — generate_appcast reads the EdDSA private key."
"${GENERATE_APPCAST}" "${UPDATES_DIR}/" || die "generate_appcast (v${V1}) failed."
[[ -f "${UPDATES_DIR}/${FEED_PATH}" ]] || die "appcast.xml not produced in updates/."
ok "appcast.xml generated for v${V1}."

# ---------------------------------------------------------------------------
# 3. Serve updates/ locally so http://localhost:8000/appcast.xml matches SUFeedURL.
# ---------------------------------------------------------------------------
info "[3/9] Serving updates/ at http://localhost:${HTTP_PORT}/${FEED_PATH}"
( cd "${UPDATES_DIR}" && python3 -m http.server "${HTTP_PORT}" ) &
HTTP_PID=$!
# Stop the local server on exit no matter how the script ends.
trap 'kill "${HTTP_PID}" 2>/dev/null || true' EXIT
sleep 1
ok "Local appcast server running (PID ${HTTP_PID})."
echo
echo "    NOTE (Open Question #3 — HTTP vs HTTPS):"
echo "    Sparkle may refuse a plain-HTTP feed in production mode. If the update is"
echo "    NOT detected over http://localhost, use an HTTPS fallback for the dry-run:"
echo "      • ngrok:   ngrok http ${HTTP_PORT}   → set SUFeedURL to the https://… URL it prints"
echo "      • staging: host updates/ on any HTTPS server and point SUFeedURL at it"
echo "    Swap SUFeedURL back to the production HTTPS URL before v1.0 (see DISTRIBUTION.md)."
echo

# ---------------------------------------------------------------------------
# 4. Install v0.0.1 to /Applications/Flint.app.
# ---------------------------------------------------------------------------
info "[4/9] Installing v${V1} to ${INSTALLED_APP}"
manual "Mount '$(basename "${V1_DMG}")' and drag Flint.app to /Applications (or:"
manual "  cp -R 'build/export/Flint.app' '${INSTALLED_APP}')."
manual "Then quit any running Flint and launch the installed v${V1} once."

# ---------------------------------------------------------------------------
# 5. Build + notarize v0.0.2 (CFBundleVersion = 2) and stage its DMG.
# ---------------------------------------------------------------------------
info "[5/9] Building + notarizing v${V2} (CFBundleVersion=2)"
manual "Set MARKETING_VERSION=${V2} and CURRENT_PROJECT_VERSION=2 before this step."
bash "${RELEASE_SH}" "${V2}" || die "release.sh ${V2} failed."

V2_DMG="${DIST_DIR}/Flint ${V2}.dmg"
[[ -f "${V2_DMG}" ]] || V2_DMG="$(ls -t "${DIST_DIR}"/*.dmg 2>/dev/null | head -1 || true)"
[[ -n "${V2_DMG}" && -f "${V2_DMG}" ]] || die "v${V2} DMG not found in ${DIST_DIR}."
cp "${V2_DMG}" "${UPDATES_DIR}/"
ok "Staged $(basename "${V2_DMG}") into updates/."

# ---------------------------------------------------------------------------
# 6. Re-run generate_appcast over BOTH DMGs → produces v0.0.1→v0.0.2 delta.
# ---------------------------------------------------------------------------
info "[6/9] Re-running generate_appcast over updates/ (now v${V1} + v${V2})"
manual "Grant Keychain access again if prompted."
"${GENERATE_APPCAST}" "${UPDATES_DIR}/" || die "generate_appcast (v${V1}+v${V2}) failed."
ok "appcast.xml updated with v${V2} (and delta from v${V1})."

# ---------------------------------------------------------------------------
# 7. Force an immediate update check (skip Sparkle's normal interval).
# ---------------------------------------------------------------------------
info "[7/9] Forcing an immediate update check"
defaults delete "${BUNDLE_ID}" SULastCheckTime 2>/dev/null || true
ok "SULastCheckTime reset for ${BUNDLE_ID}."

# ---------------------------------------------------------------------------
# 8. Launch v0.0.1 and confirm Sparkle offers v0.0.2.
# ---------------------------------------------------------------------------
info "[8/9] Launch the installed v${V1} and confirm the update"
manual "Launch ${INSTALLED_APP} (the installed v${V1})."
manual "EXPECTED: Sparkle shows an update sheet offering v${V2}; it downloads,"
manual "verifies the EdDSA signature, installs, and the app relaunches as v${V2}."

# ---------------------------------------------------------------------------
# 9. Verify the result.
# ---------------------------------------------------------------------------
info "[9/9] Verify"
manual "Confirm the relaunched app reports version ${V2} (Flint About / version)."
manual "Confirm NO Sparkle signature error appeared (a mismatched key is rejected)."
echo
ok "Dry-run orchestration complete."
echo "    The local appcast server stops when this script exits. To keep it running"
echo "    while you finish the manual verification, run the http.server step in a"
echo "    separate terminal:  ( cd updates && python3 -m http.server ${HTTP_PORT} )"
echo
echo "Press Ctrl-C to stop the local appcast server and end the dry-run."
# Keep the server alive so the running app can still fetch the feed during verification.
wait "${HTTP_PID}"
