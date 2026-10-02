#!/bin/bash
# Photo match acceptance, in a throwaway copy of the project with a real GPU.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# This machine's Godot, if tests/local.env names it (it is not checked in).
[ -f "$HERE/tests/local.env" ] && . "$HERE/tests/local.env"
GODOT="${GODOT:-godot}"
TMP="$(mktemp -d)"
cp -r "$HERE/project.godot" "$HERE/addons" "$HERE/genesis_assets" "$HERE/genesis_data" "$TMP/"
mkdir -p "$TMP/addons/gn_pm" && cp "$HERE/tests/photomatch_plugin/"* "$TMP/addons/gn_pm/"
# First open only imports the assets, with the test still off.
timeout 300 "$GODOT" --headless --editor --import --path "$TMP" > /dev/null 2>&1
sed -i 's#enabled=PackedStringArray("res://addons/genesis/plugin.cfg")#enabled=PackedStringArray("res://addons/genesis/plugin.cfg", "res://addons/gn_pm/plugin.cfg")#' "$TMP/project.godot"
timeout 900 "$GODOT" --editor --path "$TMP" > "$TMP/log.txt" 2>&1
code=$?
grep -E "GN_PM|SCRIPT ERROR|^ERROR|at: " "$TMP/log.txt" | grep -v "BUG: Unreferenced" | head -300
mkdir -p "$HERE/renders" && cp "$TMP/renders/pm_"*.png "$HERE/renders/" 2>/dev/null
rm -rf "$TMP"
echo "exit $code"
exit $code
