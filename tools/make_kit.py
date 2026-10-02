"""Rebuild Genesis's generated kit (people, production gear, furniture,
vehicles, animals) with Blender. The results are committed, so this is only
needed after changing a generator.

    python tools/make_kit.py [generator ...]

Blender is found on PATH, in BLENDER, or in the usual install places.
"""

import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GENERATORS = ["humans", "audio", "lighting", "control", "av", "furniture", "vehicles", "animals", "craft"]
# These run with the user's Blender settings, for the MPFB extension
# (tools/setup_makehuman.py installs it); the rest start from factory.
NEEDS_EXTENSIONS = ["humans"]


def find_blender():
    for c in [os.environ.get("BLENDER"), shutil.which("blender"),
              os.path.expanduser("~/tools/blender-5.2.2-windows-x64/blender.exe"),
              r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe",
              "/Applications/Blender.app/Contents/MacOS/Blender"]:
        if c and os.path.exists(c):
            return c
    sys.exit("Blender not found: set BLENDER to its path.")


def main():
    blender = find_blender()
    wanted = sys.argv[1:] or GENERATORS
    for name in wanted:
        script = os.path.join(HERE, "blender", name + ".py")
        if not os.path.exists(script):
            print("skip", name, "(no generator yet)")
            continue
        print("==", name)
        flags = [] if name in NEEDS_EXTENSIONS else ["--factory-startup"]
        subprocess.run([blender, "--background", *flags, "--python", script], check=True)


if __name__ == "__main__":
    main()
