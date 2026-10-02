#!/bin/bash
# Phase 1 acceptance test. Copies the project to a temp dir, enables the
# self-test plugin there, and runs the editor headless.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# This machine's Godot, if tests/local.env names it (it is not checked in).
[ -f "$HERE/tests/local.env" ] && . "$HERE/tests/local.env"
GODOT="${GODOT:-godot}"
TMP="$(mktemp -d)"
cp -r "$HERE/project.godot" "$HERE/addons" "$TMP/"
mkdir -p "$TMP/addons/gn_selftest" && cp "$HERE/tests/selftest_plugin/"* "$TMP/addons/gn_selftest/"
sed -i 's#enabled=PackedStringArray("res://addons/genesis/plugin.cfg")#enabled=PackedStringArray("res://addons/genesis/plugin.cfg", "res://addons/gn_selftest/plugin.cfg")#' "$TMP/project.godot"
timeout 300 "$GODOT" --headless --editor --path "$TMP" > "$TMP/log.txt" 2>&1
code=$?
grep -E "GN_SELFTEST|ERROR|SCRIPT ERROR|WARNING|leaked" "$TMP/log.txt"
echo "exit $code"
rm -rf "$TMP"
exit $code
