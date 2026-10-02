"""Start a new Genesis project for a job, separate from this one.

    python tools/new_project.py "C:/Projects/Riverside House"

Copies the plugin, the asset library and the built materials, skies and
plants into a fresh Godot project, so each job keeps its own scenes, renders
and imported models. The large CC0 downloads are copied too, so the new
project works offline.
"""

import os
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
COPY = ["addons/genesis", "genesis_assets", "genesis_data"]
SKIP = {".godot", "backplates", "looks"}


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    dest = os.path.abspath(sys.argv[1])
    if os.path.exists(dest) and os.listdir(dest):
        print("%s already exists and is not empty." % dest)
        return 1
    os.makedirs(dest, exist_ok=True)
    for rel in COPY:
        src = os.path.join(ROOT, rel)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(dest, rel),
                            ignore=lambda d, names: [n for n in names if n in SKIP])
    name = os.path.basename(dest.rstrip("/\\"))
    with open(os.path.join(ROOT, "project.godot"), encoding="utf-8") as f:
        project = f.read().replace('config/name="Genesis"', 'config/name="%s"' % name)
    with open(os.path.join(dest, "project.godot"), "w", encoding="utf-8") as f:
        f.write(project)
    for d in ("scenes", "assets", "renders"):
        os.makedirs(os.path.join(dest, d), exist_ok=True)
    open(os.path.join(dest, "renders", ".gdignore"), "w").close()
    print("New project ready: %s" % dest)
    print("Open it in Godot 4.7 (Project Manager > Import, or godot --editor --path \"%s\")." % dest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
