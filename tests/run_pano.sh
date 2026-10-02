#!/bin/bash
# Panorama acceptance, in a throwaway copy of the project with a real GPU.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# This machine's Godot, if tests/local.env names it (it is not checked in).
[ -f "$HERE/tests/local.env" ] && . "$HERE/tests/local.env"
GODOT="${GODOT:-godot}"
TMP="$(mktemp -d)"
cp -r "$HERE/project.godot" "$HERE/addons" "$HERE/genesis_assets" "$HERE/genesis_data" "$TMP/"
mkdir -p "$TMP/addons/gn_pano" && cp "$HERE/tests/pano_plugin/"* "$TMP/addons/gn_pano/"
# First open only imports the assets, with the test still off.
timeout 300 "$GODOT" --headless --editor --import --path "$TMP" > /dev/null 2>&1
sed -i 's#enabled=PackedStringArray("res://addons/genesis/plugin.cfg")#enabled=PackedStringArray("res://addons/genesis/plugin.cfg", "res://addons/gn_pano/plugin.cfg")#' "$TMP/project.godot"
timeout 900 "$GODOT" --editor --path "$TMP" > "$TMP/log.txt" 2>&1
code=$?
grep -E "GN_PANO|SCRIPT ERROR|^ERROR|at: " "$TMP/log.txt" | grep -v "BUG: Unreferenced" | head -300
mkdir -p "$HERE/renders" && cp "$TMP/renders/pano_"*.png "$HERE/renders/" 2>/dev/null ; cp "$TMP/renders/pano_tour.html" "$HERE/renders/" 2>/dev/null
rm -rf "$TMP"
# The exported tour, walked in a real browser (needs Node and Chrome).
if [ $code -eq 0 ] && command -v node > /dev/null && [ -f "$HERE/renders/pano_tour.html" ]; then
	node "$HERE/tests/tour_browser_check.mjs" "$HERE/renders/pano_tour.html" || code=1
fi
echo "exit $code"
exit $code
