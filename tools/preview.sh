#!/usr/bin/env bash
# Pictures of EasyGear's own windows, drawn without the game (layout and colors; fonts and icons are stand-ins).
#
#   tools/preview.sh <output folder>          writes window.png, ring.png, profile.png, edit.png, toast.png, feed.png
#                                             (feed.png: EasyGear's marks in rows of EllesmereUI's Loot Feed, on a
#                                             plain model of the feed - where the marks sit, not the feed's real look)
#   EUI=1 tools/preview.sh <output folder>    the same with the accent color of an EllesmereUI theme
#
# Needs Lua 5.1 and python3 with Pillow. See tools/preview/dump.lua.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?usage: tools/preview.sh <output folder>}"
mkdir -p "$OUT"
for scene in window ring profile edit toast feed; do
    lua5.1 tools/preview/dump.lua "$scene" > "$OUT/$scene.json"
    python3 tools/preview/draw.py "$OUT/$scene.json" "$OUT/$scene.png"
    rm -f "$OUT/$scene.json"
done
