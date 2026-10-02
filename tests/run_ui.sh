#!/bin/bash
# The UI journey test, in a throwaway copy of the project with a real window.
# Screenshots of each step land in tests/ui_shots/ for a person to review.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# This machine's Godot, if tests/local.env names it (it is not checked in).
[ -f "$HERE/tests/local.env" ] && . "$HERE/tests/local.env"
GODOT="${GODOT:-godot}"
TMP="$(mktemp -d)"
cp -r "$HERE/project.godot" "$HERE/addons" "$HERE/genesis_assets" "$HERE/genesis_data" "$TMP/"
mkdir -p "$TMP/addons/gn_ui" && cp "$HERE/tests/ui_plugin/"* "$TMP/addons/gn_ui/"
# First open only imports the assets, with the test still off.
timeout 300 "$GODOT" --headless --editor --import --path "$TMP" > /dev/null 2>&1
sed -i 's#enabled=PackedStringArray("res://addons/genesis/plugin.cfg")#enabled=PackedStringArray("res://addons/genesis/plugin.cfg", "res://addons/gn_ui/plugin.cfg")#' "$TMP/project.godot"
timeout 600 "$GODOT" --editor --path "$TMP" --resolution 1920x1080 > "$TMP/log.txt" 2>&1
code=$?
grep -E "GN_UI|SCRIPT ERROR|^ERROR|at: " "$TMP/log.txt" | grep -v "BUG: Unreferenced" | head -300
rm -rf "$HERE/tests/ui_shots" && cp -r "$TMP/ui_shots" "$HERE/tests/ui_shots" 2>/dev/null
rm -rf "$TMP"
echo "exit $code"
exit $code
