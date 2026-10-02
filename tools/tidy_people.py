"""Tidy the people's glTF files after Blender exports them.

Blender marks every MakeHuman material as blended transparency; in a crowd
that is slow and sorts badly. Here skin, eyes, clothes and shoes become
opaque and only hair and eyebrows keep their alpha, as a cutout (MASK). The
exporter also re-encodes shared textures as PNG beside the JPEGs humans.py
saved; each file is pointed back at the JPEG where there is one, and
textures nothing uses any more are deleted.

    python tools/tidy_people.py [folder]
"""

import glob
import json
import os
import sys

HAIR_WORDS = ("eyebrow", "eyelash", "long0", "short0", "bob0", "braid", "ponytail", "afro")


def tidy(path):
    folder = os.path.dirname(path)
    with open(path, encoding="utf-8") as f:
        g = json.load(f)
    for m in g.get("materials", []):
        name = m.get("name", "").lower()
        if any(w in name for w in HAIR_WORDS):
            m["alphaMode"] = "MASK"
            m["alphaCutoff"] = 0.5
        else:
            m.pop("alphaMode", None)
            m.pop("alphaCutoff", None)
    for img in g.get("images", []):
        uri = img.get("uri", "")
        jpg = os.path.splitext(uri)[0] + ".jpg"
        if uri.endswith(".png") and os.path.exists(os.path.join(folder, jpg)):
            img["uri"] = jpg
            img["mimeType"] = "image/jpeg"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(g, f, indent=1)


def sweep(folder):
    """Delete textures no person refers to."""
    used = set()
    for path in glob.glob(os.path.join(folder, "*.gltf")):
        with open(path, encoding="utf-8") as f:
            for img in json.load(f).get("images", []):
                used.add(os.path.normpath(os.path.join(folder, img.get("uri", ""))))
    for tex in glob.glob(os.path.join(folder, "textures", "*")):
        if os.path.normpath(tex) not in used and not tex.endswith(".import"):
            os.remove(tex)


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "genesis_assets", "people")
    for path in glob.glob(os.path.join(folder, "*.gltf")):
        tidy(path)
    sweep(folder)


if __name__ == "__main__":
    main()
