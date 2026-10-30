#!/bin/bash
# Package the accepted app as a signed dmgbuild disk image.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
if [ "${1:-}" = --help ]; then
    cat <<'USAGE'
Usage: SIGN_IDENTITY=... DEVELOPMENT_TEAM=... Scripts/package.sh
       DEVELOPMENT_TEAM=... Scripts/package.sh --verify
The app must already be Developer ID signed, Accepted and stapled. Run setup-dmg.sh
once to provision pinned tooling. DMGBUILD_VENV may select an existing environment
read-only; all three pinned versions are checked. The default environment is
.build-keyweave/tools/dmgbuild. No signed-app FinderInfo flags are modified.
Notarize/staple the resulting DMG separately, then --verify checks both final assets,
their mounted/extracted apps and writes SHA256SUMS.txt. No app is launched/installed.
USAGE
    exit 0
fi
[ "$#" -le 1 ] || fail 'Unexpected argument; use --help.'
mode="${1:-build}"
case "$mode" in build|--verify) ;; *) fail 'Unknown argument; use --help.' ;; esac
team="${DEVELOPMENT_TEAM:-}"
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || fail 'DEVELOPMENT_TEAM is required.'
if [ "$mode" = build ]; then
    identity="${SIGN_IDENTITY:-}"
    [ -n "$identity" ] && [ "$identity" != - ] || fail 'SIGN_IDENTITY must identify Developer ID Application.'
fi
DIST="$ROOT/dist"
[ -d "$DIST" ] && [ ! -L "$DIST" ] || fail 'Expected a regular dist directory.'
APP="$DIST/KeyWeave.app"
[ -d "$APP" ] && [ ! -L "$APP" ] || fail 'Expected a regular KeyWeave.app bundle.'
version="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || fail 'Unexpected app version.'
ZIP="$DIST/KeyWeave-$version-arm64.zip"
DMG="$DIST/KeyWeave-$version-arm64.dmg"
if [ "$mode" = build ]; then
    [ ! -e "$DMG" ] && [ ! -L "$DMG" ] || fail 'DMG already exists; verify/resume it rather than overwriting a submitted artifact.'
fi
tool_environment="${DMGBUILD_VENV:-$ROOT/.build-keyweave/tools/dmgbuild}"
python="$tool_environment/bin/python3"
dmgbuild="$tool_environment/bin/dmgbuild"
[ -x "$python" ] && [ -x "$dmgbuild" ] || fail 'Run Scripts/setup-dmg.sh first, or select an existing pinned DMGBUILD_VENV.'
export PYTHONDONTWRITEBYTECODE=1
"$python" -c 'from importlib.metadata import version; assert all(version(name) == expected for name, expected in [("dmgbuild", "1.6.7"), ("ds-store", "1.3.3"), ("mac-alias", "2.2.3")]), "Run Scripts/setup-dmg.sh: unexpected DMG tool versions"'
app_requirement="=anchor apple generic and identifier \"dev.anuhas.keyweave\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$team\""
dmg_requirement="=anchor apple generic and identifier \"dev.anuhas.keyweave.dmg\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$team\""
verify_app() {
    local candidate="$1"
    [ "$(plutil -extract CFBundleIdentifier raw -o - "$candidate/Contents/Info.plist")" = dev.anuhas.keyweave ] || fail 'Unexpected app bundle identity.'
    [ "$(plutil -extract CFBundleExecutable raw -o - "$candidate/Contents/Info.plist")" = KeyWeave ] || fail 'Unexpected app executable.'
    [ "$(plutil -extract CFBundleShortVersionString raw -o - "$candidate/Contents/Info.plist")" = "$version" ] || fail 'App version changed while packaging.'
    [ -f "$candidate/Contents/Resources/AppIcon.icns" ] || fail 'The KeyWeave app/volume icon is missing.'
    codesign --verify --deep --strict --test-requirement "$app_requirement" "$candidate"
    xcrun stapler validate "$candidate"
    spctl --assess --type execute --verbose=4 "$candidate"
    lipo "$candidate/Contents/MacOS/KeyWeave" -verify_arch arm64
}
verify_app "$APP"
lock="$DMG.lock"
mkdir "$lock" 2>/dev/null || fail "Another package operation may be using this DMG (lock: $lock)."
stage=""
cleanup_mounts() {
    # Never detach another project's or the user's unrelated mounted image.
    hdiutil info -plist > "$stage/mounts.plist" 2>> "$stage/cleanup.log" || return 1
    "$python" - "$stage" <<'PY' > "$stage/devices.txt" || return 1
import os, plistlib, re, sys
stage = os.path.realpath(sys.argv[1]) + os.sep
with open(stage + "mounts.plist", "rb") as stream:
    images = plistlib.load(stream).get("images", [])
for image in images:
    if os.path.realpath(image.get("image-path", "")).startswith(stage):
        devices = [entry.get("dev-entry", "") for entry in image.get("system-entities", [])]
        disk = next((device for device in devices if re.fullmatch(r"/dev/disk[0-9]+", device)), None)
        if not disk:
            raise SystemExit("Cannot identify an owned image device; preserve the stage for inspection")
        print(disk)
PY
    local device
    while IFS= read -r device; do
        hdiutil detach "$device" >> "$stage/cleanup.log" 2>&1 || return 1
    done < "$stage/devices.txt"
}
cleanup() {
    local result=$? detached=1
    trap - EXIT
    if [ -n "$stage" ]; then
        if ! cleanup_mounts; then
            printf 'Could not detach an owned packaging disk; stage and lock preserved: %s\n' "$stage" >&2
            result=1
            detached=0
        fi
        if [ "$result" = 0 ]; then rm -rf "$stage";
        else printf 'DMG diagnostics preserved: %s\n' "$stage" >&2; fi
    fi
    if [ "$detached" = 1 ]; then rmdir "$lock" || true; fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
stage="$(mktemp -d "$DIST/.KeyWeave-package.XXXXXXXX")"
if [ "$mode" = build ]; then
    app="$stage/KeyWeave.app"
    ditto "$APP" "$app"
    ditto "$ROOT/LICENSE" "$stage/LICENSE"
    verify_app "$app" > "$stage/app-validation.log" 2>&1
    "$python" - "$ROOT/packaging/dmg" <<'PY'
from pathlib import Path
import struct, sys
directory = Path(sys.argv[1])
for name, expected in [("background.png", (600, 400)), ("background@2x.png", (1200, 800))]:
    with (directory / name).open("rb") as stream:
        header = stream.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", header[16:24]) == expected, f"Unexpected DMG background: {name}"
PY
    mkdir "$stage/tmp"
    # dmgbuild's temporary backing images stay inside this invocation's owned stage.
    TMPDIR="$stage/tmp" "$dmgbuild" -s "$ROOT/packaging/dmg/settings.py" \
        -D "app=$app" -D "resources=$ROOT/packaging/dmg" -D "license=$stage/LICENSE" \
        "KeyWeave $version" "$stage/distribution.dmg" > "$stage/dmgbuild.log" 2>&1 || fail "dmgbuild failed; see $stage/dmgbuild.log."
    image="$stage/distribution.dmg"
else
    [ -f "$DMG" ] && [ ! -L "$DMG" ] && [ -f "$ZIP" ] && [ ! -L "$ZIP" ] || fail 'Final ZIP/DMG must be regular files.'
    # Only mount a backing image owned by this invocation. The cleanup ownership
    # filter must never select another mount of the public distribution image.
    image="$stage/final-verification.dmg"
    ditto "$DMG" "$image"
    cmp "$DMG" "$image"
    zip_before="$(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"
    codesign --verify --strict --test-requirement "$dmg_requirement" "$image"
    xcrun stapler validate "$image"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$image"
    mkdir "$stage/archive"
    ditto -x -k "$ZIP" "$stage/archive"
    verify_app "$stage/archive/KeyWeave.app"
    cmp "$APP/Contents/MacOS/KeyWeave" "$stage/archive/KeyWeave.app/Contents/MacOS/KeyWeave"
    cmp "$APP/Contents/_CodeSignature/CodeResources" "$stage/archive/KeyWeave.app/Contents/_CodeSignature/CodeResources"
    cmp "$ROOT/LICENSE" "$stage/archive/LICENSE"
fi
hdiutil verify "$image" > "$stage/image-validation.log" 2>&1
mkdir "$stage/verify"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$stage/verify" -plist "$image" > "$stage/attach.plist" 2> "$stage/attach.stderr"
verify_app "$stage/verify/KeyWeave.app" > "$stage/packaged-app-validation.log" 2>&1
cmp "$APP/Contents/MacOS/KeyWeave" "$stage/verify/KeyWeave.app/Contents/MacOS/KeyWeave"
cmp "$APP/Contents/_CodeSignature/CodeResources" "$stage/verify/KeyWeave.app/Contents/_CodeSignature/CodeResources"
cmp "$ROOT/LICENSE" "$stage/verify/License.txt"
[ "$(readlink "$stage/verify/Applications")" = /Applications ] || fail 'DMG Applications link is incorrect.'
cleanup_mounts || fail 'Cannot detach the verification image; refusing to publish.'
if [ "$mode" = build ]; then
    codesign --force --sign "$identity" --timestamp --identifier dev.anuhas.keyweave.dmg "$image" > "$stage/signing.log" 2>&1
    codesign --verify --strict --test-requirement "$dmg_requirement" "$image" >> "$stage/signing.log" 2>&1
    codesign -d --verbose=4 "$image" >> "$stage/signing.log" 2>&1
    grep -q '^Timestamp=' "$stage/signing.log" || fail 'The DMG has no secure signing timestamp.'
    [ ! -e "$DMG" ] && [ ! -L "$DMG" ] || fail 'DMG destination appeared during packaging; refusing to overwrite it.'
    mv "$image" "$DMG"
    printf 'Signed dmgbuild DMG built; notarize/staple before publication: %s\n' "$DMG"
else
    [ ! -L "$DIST/SHA256SUMS.txt" ] || fail 'Refusing a symlink at SHA256SUMS.txt.'
    cmp "$DMG" "$image" || fail 'Distribution DMG changed during verification.'
    [ "$zip_before" = "$(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)" ] || fail 'Distribution ZIP changed during verification.'
    (cd "$DIST"; shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")") > "$stage/SHA256SUMS.txt"
    mv "$stage/SHA256SUMS.txt" "$DIST/SHA256SUMS.txt"
    printf 'Final stapled ZIP and dmgbuild DMG verified. Checksums: %s\n' "$DIST/SHA256SUMS.txt"
fi
