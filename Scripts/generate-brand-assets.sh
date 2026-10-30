#!/bin/bash
# Resize the generated masters; no artwork generation or network access here.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON="$ROOT/Resources/Branding/KeyWeaveIcon.png"
MARK="$ROOT/Resources/Branding/KeyWeaveMark.png"
ASSETS="$ROOT/Sources/TabType/Resources/Assets.xcassets"
stage="$(mktemp -d "${TMPDIR:-/tmp}/keyweave-icon.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/AppIcon.iconset"
for entry in '16 16x16' '32 16x16@2x' '32 32x32' '64 32x32@2x' '128 128x128' '256 128x128@2x' '256 256x256' '512 256x256@2x' '512 512x512' '1024 512x512@2x'; do
    read -r pixels name <<< "$entry"
    sips -z "$pixels" "$pixels" "$ICON" --out "$stage/AppIcon.iconset/icon_$name.png" >/dev/null
done
iconutil -c icns "$stage/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
cp "$stage/AppIcon.iconset/"*.png "$ASSETS/AppIcon.appiconset/"
cp "$ICON" "$ASSETS/AppIcon.appiconset/AppIcon.png"
rm -f "$ASSETS/AppIcon.appiconset/icon_512x512@2x.png"
sips -z 18 18 "$MARK" --out "$ASSETS/MenuBarIcon.imageset/MenuBarIcon.png" >/dev/null
sips -z 36 36 "$MARK" --out "$ASSETS/MenuBarIcon.imageset/MenuBarIcon@2x.png" >/dev/null
mkdir -p "$ROOT/Sources/TabType/Resources/Branding"
cp "$ICON" "$ROOT/Sources/TabType/Resources/Branding/KeyWeaveIcon.png"
cp "$ASSETS/MenuBarIcon.imageset/"*.png "$ROOT/Sources/TabType/Resources/Branding/"
python3 - "$ASSETS" <<'PY'
from pathlib import Path
import json,sys
assets=Path(sys.argv[1])
images=[]
for size in [16,32,128,256,512]:
    for scale in [1,2]:
        suffix='@2x' if scale==2 else ''
        filename='AppIcon.png' if size==512 and scale==2 else f'icon_{size}x{size}{suffix}.png'
        images.append({'idiom':'mac','size':f'{size}x{size}','scale':f'{scale}x','filename':filename})
(assets/'AppIcon.appiconset/Contents.json').write_text(json.dumps({'images':images,'info':{'author':'xcode','version':1}},indent=2)+'\n')
PY
printf 'Generated KeyWeave ICNS, app icon sizes, brand image and template menu images.\n'
