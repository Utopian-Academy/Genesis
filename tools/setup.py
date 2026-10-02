"""Get a Genesis checkout ready to open: download the CC0 photographic
assets, then build the material presets and plants from them.

    python tools/setup.py            # everything
    python tools/setup.py --offline  # no downloads; generated fallbacks only

Godot is found from $GENESIS_GODOT, then PATH, then the portable copy under
~/tools/godot. Nothing here needs admin rights or installs anything.
"""

import glob
import os
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def find_godot():
    env = os.environ.get("GENESIS_GODOT")
    if env and os.path.exists(env):
        return env
    for name in ("godot", "godot4", "Godot"):
        found = shutil.which(name)
        if found:
            return found
    home = os.path.expanduser("~")
    for pattern in ("tools/godot/Godot_v4.*_console.exe", "tools/godot/Godot_v4.*", "tools/godot/godot"):
        hits = sorted(glob.glob(os.path.join(home, pattern)))
        if hits:
            return hits[-1]
    return None


def run(cmd):
    print("\n>", " ".join(os.path.basename(c) if i == 0 else c for i, c in enumerate(cmd)))
    return subprocess.call(cmd, cwd=ROOT)


def main():
    offline = "--offline" in sys.argv
    if not offline:
        if run([sys.executable, os.path.join("tools", "fetch_assets.py")]) != 0:
            print("Some downloads failed; continuing with what arrived.")
    godot = find_godot()
    if godot is None:
        print("Godot 4.7 not found. Set GENESIS_GODOT to its executable.")
        return 1
    # Import first so the scripts can load what was just downloaded.
    run([godot, "--headless", "--editor", "--import", "--path", "."])
    run([godot, "--headless", "--path", ".", "-s", "tools/make_materials.gd"])
    if os.path.isdir(os.path.join(ROOT, "genesis_data", "external", "atlases")):
        run([godot, "--headless", "--path", ".", "-s", "tools/make_plants.gd"])
    run([godot, "--headless", "--editor", "--import", "--path", "."])
    print("\nReady. Open the project with:\n  %s --editor --path %s" % (godot, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
