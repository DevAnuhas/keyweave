#!/bin/bash
# Local distribution pipeline only. Publishing to GitHub is a separate explicit action.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
if [ "${1:-}" = --help ]; then
    cat <<'USAGE'
Usage: SIGN_IDENTITY=... DEVELOPMENT_TEAM=... KEYCHAIN_PROFILE=... Scripts/release.sh
Build/sign the arm64 app, notarize/staple it, create ZIP/DMG, notarize/staple the
DMG, and calculate final checksums. Receipts stay outside git. A timeout stops
the pipeline; use the printed notarize.sh --resume command, then package.sh.
This does not install, launch, tag, push or publish anything to GitHub.
USAGE
    exit 0
fi
[ "$#" -eq 0 ] || fail 'Unexpected argument; use --help.'
[ -n "${SIGN_IDENTITY:-}" ] && [ "$SIGN_IDENTITY" != - ] || fail 'Release requires SIGN_IDENTITY for Developer ID Application.'
[[ "${DEVELOPMENT_TEAM:-}" =~ ^[A-Z0-9]{10}$ ]] || fail 'Release requires DEVELOPMENT_TEAM.'
[ -n "${KEYCHAIN_PROFILE:-}" ] || fail 'Release requires an existing KEYCHAIN_PROFILE; never pass credentials.'
RELEASE=1 CONFIG=Release "$ROOT/Scripts/build.sh" app
"$ROOT/Scripts/notarize.sh" app "$ROOT/dist/KeyWeave.app"
"$ROOT/Scripts/package.sh"
version="$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT/dist/KeyWeave.app/Contents/Info.plist")"
"$ROOT/Scripts/notarize.sh" dmg "$ROOT/dist/KeyWeave-$version-arm64.dmg"
"$ROOT/Scripts/package.sh" --verify
