#!/bin/bash
# Measure, layers, plans and sections, in a throwaway copy of the project with a real GPU.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# This machine's Godot, if tests/local.env names it (it is not checked in).
[ -f "$HERE/tests/local.env" ] && . "$HERE/tests/local.env"
GODOT="${GODOT:-godot}"
TMP="$(mktemp -d)"
cp -r "$HERE/project.godot" "$HERE/addons" "$HERE/genesis_assets" "$HERE/genesis_data" "$TMP/"
mkdir -p "$TMP/addons/gn_tools" && cp "$HERE/tests/tools_plugin/"* "$TMP/addons/gn_tools/"
# First open only imports the assets, with the test still off.
timeout 300 "$GODOT" --headless --editor --import --path "$TMP" > /dev/null 2>&1
sed -i 's#enabled=PackedStringArray("res://addons/genesis/plugin.cfg")#enabled=PackedStringArray("res://addons/genesis/plugin.cfg", "res://addons/gn_tools/plugin.cfg")#' "$TMP/project.godot"
timeout 900 "$GODOT" --editor --path "$TMP" > "$TMP/log.txt" 2>&1
code=$?
grep -E "GN_TOOLS|SCRIPT ERROR|^ERROR|WARNING|at: |reimport|Reimport" "$TMP/log.txt" | grep -v "BUG: Unreferenced" | tail -60
mkdir -p "$HERE/renders" && cp "$TMP/renders/tools_"*.png "$HERE/renders/" 2>/dev/null
cp "$TMP/log.txt" "${TEMP:-/tmp}/tools_godot_log.txt" 2>/dev/null
rm -rf "$TMP"
echo "exit $code"
exit $code
