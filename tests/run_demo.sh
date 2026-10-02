#!/bin/bash
# Phase 2 acceptance: builds the demo in a throwaway copy of the project with a
# real GPU (a Godot window appears briefly), then copies the scene, the
# imported building and the image back.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# This machine's Godot, if tests/local.env names it (it is not checked in).
[ -f "$HERE/tests/local.env" ] && . "$HERE/tests/local.env"
GODOT="${GODOT:-godot}"
TMP="$(mktemp -d)"
cp -r "$HERE/project.godot" "$HERE/addons" "$HERE/genesis_assets" "$HERE/genesis_data" "$TMP/"
mkdir -p "$TMP/addons/gn_demo" && cp "$HERE/tests/demo_plugin/"* "$TMP/addons/gn_demo/"
# First open only imports the assets, with the demo builder still off;
# otherwise it runs twice and the editor reopens the half-built scene.
timeout 300 "$GODOT" --headless --editor --import --path "$TMP" > /dev/null 2>&1
sed -i 's#enabled=PackedStringArray("res://addons/genesis/plugin.cfg")#enabled=PackedStringArray("res://addons/genesis/plugin.cfg", "res://addons/gn_demo/plugin.cfg")#' "$TMP/project.godot"
timeout 300 "$GODOT" --editor --path "$TMP" > "$TMP/log.txt" 2>&1
code=$?
grep -E "GN_DEMO|SCRIPT ERROR|^ERROR|at: " "$TMP/log.txt" | grep -v "BUG: Unreferenced" | head -300
if [ $code -eq 0 ]; then
  mkdir -p "$HERE/scenes" "$HERE/assets" "$HERE/renders"
  cp "$TMP/scenes/demo.tscn" "$HERE/scenes/"
  cp "$TMP/assets/"demo_house.glb* "$HERE/assets/"
  cp "$TMP/renders/"*.png "$HERE/renders/"
  cp "$TMP/renders/"*.mp4 "$HERE/renders/" 2>/dev/null
  mkdir -p "$HERE/renders/frames" && cp "$TMP/renders/demo_movie/frame_00"{030,090,150,210}.png "$HERE/renders/frames/" 2>/dev/null
  for f in "$TMP"/genesis_assets/*/*.import; do rel="${f#$TMP/}"; cp "$f" "$HERE/$rel"; done
fi
rm -rf "$TMP"
echo "exit $code"
exit $code
