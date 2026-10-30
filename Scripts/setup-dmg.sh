#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
if [ "${1:-}" = --help ]; then
    cat <<'USAGE'
Usage: Scripts/setup-dmg.sh
Provision hash-pinned dmgbuild in ignored .build-keyweave/tools/dmgbuild.
Requires macOS and Python 3.10+. DMG_WHEELHOUSE may name an existing local wheel
directory for a completely offline install. No app/signing/notary operation runs.
USAGE
    exit 0
fi
[ "$#" -eq 0 ] || fail 'Unexpected argument; use --help.'
[ "$(uname -s)" = Darwin ] || fail 'dmgbuild requires macOS.'
python3 -c 'import sys; assert sys.version_info >= (3, 10), "Python 3.10+ is required"'
for directory in "$ROOT/.build-keyweave" "$ROOT/.build-keyweave/tools" "$ROOT/.build-keyweave/tools/dmgbuild"; do
    [ ! -L "$directory" ] || fail "Refusing a symlink at $directory."
done
venv="$ROOT/.build-keyweave/tools/dmgbuild"
if [ ! -e "$venv" ]; then python3 -m venv "$venv"; fi
[ -x "$venv/bin/python3" ] || fail "Incomplete tool environment: $venv"
arguments=(--disable-pip-version-check --require-hashes --only-binary=:all: -r "$ROOT/packaging/dmg/requirements.txt")
if [ -n "${DMG_WHEELHOUSE:-}" ]; then
    [ -d "$DMG_WHEELHOUSE" ] || fail 'DMG_WHEELHOUSE must be a directory of pinned wheels.'
    arguments+=(--no-index --find-links "$DMG_WHEELHOUSE")
fi
"$venv/bin/python3" -m pip install "${arguments[@]}"
"$venv/bin/python3" -m pip check
"$venv/bin/python3" -c 'from importlib.metadata import version; assert all(version(name) == expected for name, expected in [("dmgbuild", "1.6.7"), ("ds-store", "1.3.3"), ("mac-alias", "2.2.3")]), "Unexpected DMG tool versions"'
printf 'DMG tooling ready: %s/bin/dmgbuild\n' "$venv"
