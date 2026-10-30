#!/bin/bash
# Internal Swift targets retain their upstream names. Public bundles are KeyWeave.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
if [ "${1:-}" = --help ]; then
    cat <<'USAGE'
Usage: Scripts/build.sh {app|eval}
  RELEASE=1                  Require Developer ID signing; never fall back.
  SIGN_IDENTITY=...           Developer ID certificate name or SHA-1 fingerprint.
  DEVELOPMENT_TEAM=...        Required expected ten-character team for RELEASE=1.
  CONFIG=Release             Release builds require Release; development defaults Debug.
No certificate, trust, credentials or app installation is created by this script.
USAGE
    exit 0
fi
[ "$#" -le 1 ] || fail 'Unexpected argument; use --help.'
cmd="${1:-app}"
case "$cmd" in app|eval) ;; *) fail 'Usage: Scripts/build.sh {app|eval}' ;; esac
release="${RELEASE:-0}"
case "$release" in 0|1) ;; *) fail 'RELEASE must be 0 or 1.' ;; esac
if [ "$release" = 1 ]; then
    [ "$cmd" = app ] || fail 'The release path packages the app only.'
    IDENTITY="${SIGN_IDENTITY:-}"
    TEAM="${DEVELOPMENT_TEAM:-}"
    [ -n "$IDENTITY" ] && [ "$IDENTITY" != - ] || fail 'RELEASE=1 requires SIGN_IDENTITY for a Developer ID Application certificate.'
    [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || fail 'RELEASE=1 requires DEVELOPMENT_TEAM.'
    CONFIG="${CONFIG:-Release}"
    [ "$CONFIG" = Release ] || fail 'RELEASE=1 requires CONFIG=Release.'
    identities="$(security find-identity -v -p codesigning)"
    if [[ "$IDENTITY" =~ ^[[:xdigit:]]{40}$ ]]; then
        match="$(printf '%s\n' "$identities" | grep -i -F -- "$IDENTITY" || true)"
    else
        [[ "$IDENTITY" = 'Developer ID Application:'* ]] || fail 'SIGN_IDENTITY must be a Developer ID Application name or certificate fingerprint.'
        match="$(printf '%s\n' "$identities" | grep -F -- "\"$IDENTITY\"" || true)"
    fi
    printf '%s\n' "$match" | grep -F 'Developer ID Application:' | grep -F "($TEAM)" >/dev/null || fail 'The requested Developer ID Application identity/private key is unavailable for the expected team.'
else
    CONFIG="${CONFIG:-Debug}"
    IDENTITY="${SIGN_IDENTITY:-Keyweave Dev}"
    if [ "$cmd" = app ] && ! security find-identity -v -p codesigning 2>/dev/null | grep -F -- "$IDENTITY" >/dev/null; then IDENTITY=-; fi
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_ROOT="$ROOT/.build-keyweave"
DERIVED="$BUILD_ROOT/xcode"
PRODUCTS="$DERIVED/Build/Products/$CONFIG"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/swift-module-cache"
if [ "$cmd" = eval ]; then
    swift build --scratch-path "$BUILD_ROOT/swift" --cache-path "$BUILD_ROOT/package-cache" \
        --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security" \
        -c release --product tabtype-eval
    printf 'Built: %s\n' "$BUILD_ROOT/swift/release/tabtype-eval"
    exit 0
fi
xcrun xcodebuild -scheme TabType -configuration "$CONFIG" \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
    -clonedSourcePackagesDirPath "$BUILD_ROOT/source-packages" \
    -packageCachePath "$BUILD_ROOT/package-cache" -skipPackageUpdates \
    -skipPackagePluginValidation build
[ ! -L "$ROOT/dist" ] || fail 'Refusing a symlink at dist.'
mkdir -p "$ROOT/dist"
stage="$(mktemp -d "$ROOT/dist/.KeyWeave-build.XXXXXXXX")"
destination="$ROOT/dist/KeyWeave.app"
cleanup() {
    local result=$?
    trap - EXIT
    if [ -d "$stage/previous.app" ] && [ ! -e "$destination" ]; then mv "$stage/previous.app" "$destination"; fi
    rm -rf "$stage"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
APP="$stage/KeyWeave.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$PRODUCTS/TabType" "$APP/Contents/MacOS/KeyWeave"
LLAMA_FW="$(find "$PRODUCTS" -maxdepth 2 -name llama.framework -type d | head -1)"
[ -n "$LLAMA_FW" ] || fail 'llama.framework is missing; refusing a broken app.'
cp -R "$LLAMA_FW" "$APP/Contents/Frameworks/"
if [ "$release" = 1 ]; then
    if ! otool -l "$APP/Contents/MacOS/KeyWeave" | grep -F '@executable_path/../Frameworks' >/dev/null; then
        install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/KeyWeave"
    fi
    lipo "$APP/Contents/MacOS/KeyWeave" -verify_arch arm64
else
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/KeyWeave" 2>/dev/null || true
fi
find "$PRODUCTS" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"; fi
if [ -f "$ROOT/LICENSE" ]; then cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"; fi
if [ "$release" = 1 ]; then
    [ -f "$APP/Contents/Resources/LICENSE" ] || fail 'MIT LICENSE is missing.'
    [ "$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")" = dev.anuhas.keyweave ] || fail 'Unexpected release bundle identifier.'
    [ "$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")" = KeyWeave ] || fail 'Unexpected release executable.'
    # Refuse new nested code until its signing order/entitlements are deliberate.
    while IFS= read -r -d '' candidate; do
        if [[ "$(file -b "$candidate")" == *Mach-O* ]]; then
            case "$candidate" in
                "$APP/Contents/MacOS/KeyWeave"|"$APP/Contents/Frameworks/llama.framework/llama"|"$APP/Contents/Frameworks/llama.framework/Versions/"*/llama) ;;
                *) fail "Unexpected nested executable: $candidate" ;;
            esac
        fi
    done < <(find "$APP" -type f -print0)
fi
sign_arguments=(--force --sign "$IDENTITY")
if [ "$release" = 1 ]; then sign_arguments+=(--options runtime --timestamp); fi
# Sign known code inside-out; app entitlements never propagate to the framework.
codesign "${sign_arguments[@]}" "$APP/Contents/Frameworks/llama.framework"
codesign "${sign_arguments[@]}" --identifier dev.anuhas.keyweave \
    --entitlements "$ROOT/Resources/TabType.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if [ "$release" = 1 ]; then
    requirement="=anchor apple generic and identifier \"dev.anuhas.keyweave\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$TEAM\""
    codesign --verify --strict --test-requirement "$requirement" "$APP"
    framework_requirement="=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$TEAM\""
    codesign --verify --strict --test-requirement "$framework_requirement" "$APP/Contents/Frameworks/llama.framework"
    signature="$(codesign -d --verbose=4 "$APP" 2>&1)"
    printf '%s\n' "$signature" | grep -q 'flags=.*runtime' || fail 'Hardened Runtime is missing.'
    printf '%s\n' "$signature" | grep -q '^Timestamp=' || fail 'Secure signing timestamp is missing.'
fi
if [ -e "$destination" ] || [ -L "$destination" ]; then
    [ -d "$destination" ] && [ ! -L "$destination" ] || fail 'Refusing to replace a non-bundle/symlink output.'
    mv "$destination" "$stage/previous.app"
fi
mv "$APP" "$destination"
printf 'Built: %s\n' "$destination"
if [ "$release" = 1 ]; then printf 'Developer ID signed; notarization has not yet run.\n';
else printf 'Development build; not a notarized distribution.\n'; fi
