"""Surfaces for the production kit, from ambientCG's CC0 scanned materials.

Each surface is one ambientCG set, optionally tinted (a white fine-textured
plastic becomes black, white or grey powder coat), resized to 1K and saved
as colour, normal, roughness and metalness maps in
genesis_assets/kit_textures/, which every kit model shares. The Blender
generators (tools/blender/gnkit.py kit_material) build materials from them.

    python tools/fetch_kit_textures.py
"""

import io
import json
import os
import urllib.request
import zipfile

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CACHE = os.path.join(ROOT, "genesis_data", "external", "ambientcg_kit")
OUT = os.path.join(ROOT, "genesis_assets", "kit_textures")
SIZE = 1024

# surface: (ambientCG set, tint as linear-ish RGB the colour map is scaled to, or None)
SURFACES = {
    "grille": ("SheetMetal001", (0.02, 0.02, 0.022)),
    "powder_black": ("Plastic013A", (0.045, 0.045, 0.05)),
    "powder_white": ("Plastic013A", (0.86, 0.86, 0.84)),
    "powder_grey": ("Plastic013A", (0.32, 0.33, 0.35)),
    "plastic_black": ("Plastic006", None),
    "alu_brushed": ("Metal009", None),
    "alu_satin": ("Metal011", None),
    "chrome": ("Metal012", None),
    "rubber": ("Rubber004", None),
    "deck": ("Rubber001", None),
    "fabric_black": ("Fabric030", (0.05, 0.05, 0.055)),
    "fabric_white": ("Fabric030", (0.9, 0.9, 0.88)),
    # Furniture and vehicles (furniture.py, vehicles.py).
    "leather_black": ("Leather027", None),
    "linen": ("Fabric032", (0.93, 0.93, 0.9)),
    "velvet_red": ("Fabric030", (0.42, 0.03, 0.05)),
    "fabric_burgundy": ("Fabric030", (0.34, 0.04, 0.07)),
    "wood_light": ("Wood092", None),
    "diamond_plate": ("DiamondPlate009", (0.5, 0.51, 0.53)),
}
MAPS = {"color": "_Color.jpg", "normal": "_NormalGL.jpg", "roughness": "_Roughness.jpg", "metalness": "_Metalness.jpg"}


def download(asset):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, "%s_1K-JPG.zip" % asset)
    if not os.path.exists(path):
        print("downloading", asset)
        req = urllib.request.Request("https://ambientcg.com/get?file=%s_1K-JPG.zip" % asset,
                                     headers={"User-Agent": "Genesis asset setup"})
        with urllib.request.urlopen(req) as r, open(path, "wb") as f:
            f.write(r.read())
    return zipfile.ZipFile(path)


def tint(img, rgb):
    """Scale the colour map so its average becomes `rgb`, keeping its texture."""
    img = img.convert("RGB")
    small = img.resize((64, 64))
    px = list(small.getdata())
    mean = [max(sum(p[c] for p in px) / len(px) / 255.0, 0.02) for c in range(3)]
    bands = [b.point(lambda v, k=rgb[c] / mean[c]: min(255, int(v * k))) for c, b in enumerate(img.split())]
    return Image.merge("RGB", bands)


def main():
    os.makedirs(OUT, exist_ok=True)
    licences = {}
    for surface, (asset, rgb) in SURFACES.items():
        z = download(asset)
        names = z.namelist()
        for key, suffix in MAPS.items():
            member = next((n for n in names if n.endswith(suffix)), None)
            if member is None:
                continue
            img = Image.open(io.BytesIO(z.read(member)))
            if key == "color" and rgb:
                img = tint(img, rgb)
            img = img.convert("RGB" if key in ("color", "normal") else "L").resize((SIZE, SIZE), Image.LANCZOS)
            img.save(os.path.join(OUT, "%s_%s.jpg" % (surface, key)), quality=88)
        licences[surface] = {"source": "https://ambientcg.com/view?id=" + asset, "author": "ambientCG",
                             "license": "CC0-1.0", "tint": rgb}
        print("made", surface, "from", asset)
    with open(os.path.join(OUT, "LICENSES.json"), "w") as f:
        json.dump(licences, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
