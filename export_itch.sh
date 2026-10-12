#!/bin/bash
# Builds the web export and zips it for itch.io: build/itch/rocket-caro-web.zip
# (index.html must sit at the root of the zip; itch reads it from there).
cd "$(dirname "$0")" || exit 1
GODOT="${GODOT:-/Users/manhtien/Downloads/Godot.app/Contents/MacOS/Godot}"
mkdir -p build/web build/itch
rm -f build/web/index.* build/itch/rocket-caro-web.zip
"$GODOT" --headless --path . --export-release Web build/web/index.html >/dev/null 2>&1 || { echo "Export failed"; exit 1; }
(cd build/web && zip -q -r ../itch/rocket-caro-web.zip index.html index.js index.wasm index.pck index.png index.icon.png index.apple-touch-icon.png index.audio.worklet.js index.audio.position.worklet.js)
ls -lh build/itch/rocket-caro-web.zip
unzip -l build/itch/rocket-caro-web.zip | tail -n +4 | head -12
