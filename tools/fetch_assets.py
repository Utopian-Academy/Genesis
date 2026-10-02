"""Download Genesis's photographic CC0 assets: HDRI skies, scanned
materials and leaf atlases.

    python tools/fetch_assets.py

Everything comes from two CC0 libraries, Poly Haven and ambientCG, and lands
in genesis_data/external/, which git ignores: about 200 MB of binaries
that this script can always recreate. Each asset gets a .license.json
recording where it came from, who made it and its licence, which is the
record the brief asks for. Without these files Genesis still works,
using the generated fallbacks.

Standard library only. Re-running skips anything already downloaded.
"""

import io
import json
import os
import sys
import urllib.request
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "genesis_data", "external")
UA = {"User-Agent": "Genesis asset fetch (Utopian Academy)"}

# Mostly pure skies (sky without ground, because the ground is ours). The
# "field" one keeps its photographed landscape: a real horizon for open sites,
# and a genuine site photo for testing photo match.
SKIES = {
    "partly_cloudy": "kloofendal_48d_partly_cloudy_puresky",
    "clear": "autumn_field_puresky",
    "overcast": "overcast_soil_puresky",
    "sunset": "belfast_sunset_puresky",
    "field": "kloofendal_48d_partly_cloudy",
}
SKY_RES = "4k"

# name -> ambientCG asset id. Chosen for architecture: what facades,
# paving and gardens are actually made of.
MATERIALS = {
    "brick": "Bricks097",
    "concrete": "Concrete034",
    "plaster": "PaintedPlaster017",
    "wood": "Planks037A",
    "paving": "PavingStones130",
    "asphalt": "Asphalt031",
    "metal": "Metal049A",
    "lawn": "Grass004",
    "bark": "Bark001",
    # Ground to paint on terrain.
    "earth": "Ground103",
    "gravel": "Gravel043",
    "sand": "Ground080",
    "rock": "Rock051",
    "forest_floor": "Ground078",
    "snow": "Snow010A",
    "mud": "Ground109",
    "fallen_leaves": "ScatteredLeaves008",
}
# Leaf and grass atlases for the card-built plants: the leaves of the
# species Genesis grows (tools/make_plants.gd), in season and out.
ATLASES = {
    "leaves_broad": "LeafSet024",
    "leaves_small": "LeafSet017",
    "grass_blades": "Foliage001",
    "leaves_oak": "LeafSet016",
    "leaves_maple_autumn": "LeafSet027",
    "leaves_autumn_red": "LeafSet028",
    "leaves_autumn_yellow": "LeafSet021",
    "leaves_dried": "LeafSet030",
    "leaves_green_a": "LeafSet022",
    "leaves_green_b": "LeafSet023",
    "leaves_spring": "LeafSet014",
    "leaves_garden": "LeafSet025",
    "leaves_tree_a": "LeafSet009",
    "leaves_tree_b": "LeafSet010",
    "leaves_mixed": "LeafSet013",
    "needles": "LeafSet019",
    "pine_needles": "PineNeedles001",
    "ivy": "LeafSet029",
    "dandelion": "LeafSet020",
    "vegetation": "LeafSet026",
    "weeds_a": "Foliage002",
    "weeds_b": "Foliage003",
    "weeds_c": "Foliage004",
    "plants": "Foliage005",
    "grass_strands": "Foliage006",
    "garden_grass": "Foliage007",
    "lawn_blades": "Foliage008",
}
# Barks, one per kind of tree trunk.
BARKS = {
    "bark_oak": "Bark012",
    "bark_fir": "Bark014",
    "bark_smooth_light": "Bark004",
    "bark_smooth_dark": "Bark002",
    "bark_rough_light": "Bark007",
    "bark_grey_moss": "Bark011",
    "bark_mossy": "Bark013",
    "bark_old": "Bark015",
}
MAPS = ("Color", "NormalGL", "Roughness", "Opacity", "AmbientOcclusion")


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        return r.read()


def write_license(path, record):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(record, f, indent=2)
        f.write("\n")


def fetch_sky(name, asset):
    folder = os.path.join(OUT, "skies")
    os.makedirs(folder, exist_ok=True)
    dest = os.path.join(folder, name + ".hdr")
    if os.path.exists(dest):
        return
    files = json.loads(get("https://api.polyhaven.com/files/" + asset))
    info = json.loads(get("https://api.polyhaven.com/info/" + asset))
    url = files["hdri"][SKY_RES]["hdr"]["url"]
    print("sky", name, "<-", asset, SKY_RES)
    data = get(url)
    with open(dest, "wb") as f:
        f.write(data)
    write_license(os.path.join(folder, name + ".license.json"), {
        "source": "https://polyhaven.com/a/" + asset,
        "author": ", ".join(info.get("authors", {}).keys()),
        "license": "CC0-1.0",
        "attribution": "None required",
    })


def fetch_ambientcg(kind, name, asset):
    folder = os.path.join(OUT, kind, name)
    if os.path.isdir(folder) and any(f.endswith("_Color.jpg") for f in os.listdir(folder)):
        return
    os.makedirs(folder, exist_ok=True)
    print(kind, name, "<-", asset)
    data = get("https://ambientcg.com/get?file=%s_2K-JPG.zip" % asset)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for member in z.namelist():
            for m in MAPS:
                if member.endswith("_%s.jpg" % m):
                    with open(os.path.join(folder, "%s_%s.jpg" % (name, m)), "wb") as f:
                        f.write(z.read(member))
    write_license(os.path.join(folder, name + ".license.json"), {
        "source": "https://ambientcg.com/view?id=" + asset,
        "author": "ambientCG (Lennart Demes)",
        "license": "CC0-1.0",
        "attribution": "None required",
    })


def main():
    failed = []
    jobs = [(fetch_sky, (n, a)) for n, a in SKIES.items()]
    jobs += [(fetch_ambientcg, ("materials", n, a)) for n, a in MATERIALS.items()]
    jobs += [(fetch_ambientcg, ("atlases", n, a)) for n, a in ATLASES.items()]
    jobs += [(fetch_ambientcg, ("barks", n, a)) for n, a in BARKS.items()]
    for fn, args in jobs:
        try:
            fn(*args)
        except Exception as e:  # keep going; report at the end
            failed.append("%s: %s" % (args[-1], e))
    if failed:
        print("\nNot downloaded:\n  " + "\n  ".join(failed))
        return 1
    print("\nAll assets present in", OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
