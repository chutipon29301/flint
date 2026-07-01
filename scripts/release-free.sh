#!/usr/bin/env bash
#
# release-free.sh — Flint UNSIGNED (ad-hoc) DMG for free GitHub distribution.
#
# This is the NO-Apple-Developer-account path. It ad-hoc signs the app
# (codesign -s -), which is the minimum required for the binary to run on
# Apple Silicon, and packages a DMG with the built-in hdiutil (no create-dmg,
# no Node). The result is NOT notarized: on first launch users must approve it
# via System Settings → Privacy & Security → "Open Anyway" (see README).
#
# For the paid, notarized, Gatekeeper-clean release, use release.sh instead.
#
# USAGE:
#   bash scripts/release-free.sh [version]    # version optional; defaults to Info.plist MARKETING_VERSION
#
# ponytail: hdiutil over create-dmg — no Node dep, plain DMG is fine for a dev tool.
set -euo pipefail

SCHEME="Flint"
CONFIGURATION="Release"
APP_NAME="Flint.app"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

BUILD_DIR="${REPO_ROOT}/build"
DERIVED="${BUILD_DIR}/DerivedData"
DIST_DIR="${REPO_ROOT}/dist"

die()  { echo "❌ ERROR: $*" >&2; exit 1; }
info() { echo "▶ $*"; }
ok()   { echo "✅ $*"; }

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found — install Xcode."

VERSION="${1:-}"
if [[ -z "${VERSION}" ]]; then
  VERSION="$(xcodebuild -showBuildSettings -scheme "${SCHEME}" -configuration "${CONFIGURATION}" 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION =/{print $2; exit}')"
  VERSION="${VERSION:-0.0.0}"
fi
info "Version: ${VERSION}"

rm -rf "${DERIVED}" "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# 1. Release build (clean, into a scoped DerivedData so the path is predictable).
info "[1/4] Building ${SCHEME} (${CONFIGURATION})"
xcodebuild \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED}" \
  clean build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  || die "build failed."

APP_PATH="${DERIVED}/Build/Products/${CONFIGURATION}/${APP_NAME}"
[[ -d "${APP_PATH}" ]] || die "built app not found at ${APP_PATH}."
ok "Built ${APP_PATH}"

# 2. Ad-hoc sign. --deep is acceptable here: no Developer ID / notarization to
#    corrupt, and Apple Silicon requires at least an ad-hoc signature to launch.
info "[2/4] Ad-hoc signing (codesign -s -)"
codesign --force --deep --sign - "${APP_PATH}" || die "ad-hoc codesign failed."
codesign --verify --verbose "${APP_PATH}" || die "codesign verify failed."
ok "Ad-hoc signed."

# 3. Stage a DMG layout with an /Applications symlink for drag-install.
info "[3/4] Staging DMG contents"
STAGE="${BUILD_DIR}/dmg-stage"
rm -rf "${STAGE}"; mkdir -p "${STAGE}"
cp -R "${APP_PATH}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

# 4. Build the DMG.
DMG_PATH="${DIST_DIR}/Flint-${VERSION}.dmg"
info "[4/4] Building DMG → ${DMG_PATH}"
hdiutil create \
  -volname "Flint ${VERSION}" \
  -srcfolder "${STAGE}" \
  -ov -format UDZO \
  "${DMG_PATH}" >/dev/null || die "hdiutil create failed."
ok "DMG built: ${DMG_PATH}"

echo
ok "FREE RELEASE COMPLETE (unsigned / ad-hoc — NOT notarized)."
echo "    DMG: ${DMG_PATH}"
echo
echo "Publish to GitHub Releases:"
echo "    gh release create v${VERSION} \"${DMG_PATH}\" \\"
echo "      --title \"Flint ${VERSION}\" \\"
echo "      --notes \"See README for install (unsigned build — approve via System Settings → Privacy & Security).\""
