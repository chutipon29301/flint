#!/usr/bin/env bash
#
# update-cask.sh — bump the Homebrew cask in chutiponh/homebrew-flint to a new release.
#
# Run AFTER a GitHub release + DMG exist (e.g. after release.yml publishes vX.Y.Z).
# Downloads the published DMG, computes its sha256, rewrites version+sha256 in the
# cask, and pushes to the tap repo.
#
# USAGE:
#   bash scripts/update-cask.sh <version>          # e.g. 0.1.2
#
# Requires: gh (authed), git. Clones the tap into a temp dir; no local checkout needed.
set -euo pipefail

VERSION="${1:?usage: update-cask.sh <version>}"
REPO="chutiponh/flint"
TAP="chutiponh/homebrew-flint"
DMG_URL="https://github.com/${REPO}/releases/download/v${VERSION}/Flint-${VERSION}.dmg"

echo "▶ Downloading ${DMG_URL}"
TMP="$(mktemp -d)"
curl -fsSL "${DMG_URL}" -o "${TMP}/Flint.dmg" || { echo "❌ DMG not found — is release v${VERSION} published?"; exit 1; }
SHA="$(shasum -a 256 "${TMP}/Flint.dmg" | awk '{print $1}')"
echo "  sha256: ${SHA}"

echo "▶ Cloning tap ${TAP}"
# In CI, GH_TOKEN carries write access to the tap repo (default GITHUB_TOKEN
# can't push cross-repo). Locally, GH_TOKEN is unset and the credential helper
# handles auth via plain HTTPS.
if [[ -n "${GH_TOKEN:-}" ]]; then
  CLONE_URL="https://x-access-token:${GH_TOKEN}@github.com/${TAP}.git"
else
  CLONE_URL="https://github.com/${TAP}.git"
fi
git clone -q "${CLONE_URL}" "${TMP}/tap"
CASK="${TMP}/tap/Casks/flint.rb"

# Rewrite version + sha256 (BSD sed on macOS).
sed -i '' -E "s/^  version \".*\"/  version \"${VERSION}\"/" "${CASK}"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "${CASK}"

echo "▶ Updated cask:"
grep -E "^  (version|sha256)" "${CASK}"

cd "${TMP}/tap"
if git diff --quiet; then
  echo "✅ Cask already at ${VERSION} — nothing to push."
  exit 0
fi
git -c user.name="Chutipon Hirankanokkul" -c user.email="chutiponh@hotmail.com" \
  commit -q -am "chore: bump flint cask to ${VERSION}"
git push -q origin HEAD
echo "✅ Pushed flint cask ${VERSION} to ${TAP}"
