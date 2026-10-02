"""Set up MakeHuman for rebuilding Genesis's people: install the MPFB
extension into Blender and put MakeHuman's CC0 asset packs in its user data.

Only needed to rebuild the people (tools/blender/humans.py); the people
themselves are committed. Everything fetched here is CC0:
  - MPFB, from Blender's extensions platform (checked against its SHA-256);
  - the MakeHuman system assets (bodies, skins, hair, eyes, clothes) and
    the sitting poses, from MakeHuman's CC0 asset packs.

    python tools/setup_makehuman.py
"""

import hashlib
import os
import subprocess
import sys
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(ROOT, "genesis_data", "external", "makehuman")
sys.path.insert(0, HERE)
from make_kit import find_blender  # noqa: E402

MPFB = ("mpfb-2.0.17.zip",
        "https://extensions.blender.org/download/sha256:4f0a879d64a39bf646fbf5f53601ac678855da329d650617dca5737548239a87/"
        "add-on-mpfb-v2.0.17.zip?repository=%2Fapi%2Fv1%2Fextensions%2F&blender_version_min=4.2.0",
        "4f0a879d64a39bf646fbf5f53601ac678855da329d650617dca5737548239a87")
PACKS = [
    ("makehuman_system_assets_cc0.zip",
     "https://files2.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip"),
    ("poses01_cc0.zip", "https://files2.makehumancommunity.org/asset_packs/poses01/poses01_cc0.zip"),
]


def fetch(name, url):
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        print("downloading", name)
        urllib.request.urlretrieve(url, path)
    return path


def user_data():
    base = os.environ.get("APPDATA") or os.path.expanduser("~/.config")
    for version in sorted(os.listdir(os.path.join(base, "Blender Foundation", "Blender")), reverse=True):
        d = os.path.join(base, "Blender Foundation", "Blender", version, "extensions", ".user", "user_default", "mpfb", "data")
        if os.path.isdir(os.path.dirname(d)):
            return d
    sys.exit("MPFB's user folder was not found: did the extension install?")


def main():
    os.makedirs(CACHE, exist_ok=True)
    name, url, sha = MPFB
    path = fetch(name, url)
    if hashlib.sha256(open(path, "rb").read()).hexdigest() != sha:
        sys.exit("MPFB download does not match its published SHA-256; not installing it.")
    subprocess.run([find_blender(), "--command", "extension", "install-file", "-r", "user_default", "-e", path], check=True)
    data = user_data()
    for name, url in PACKS:
        print("unpacking", name)
        zipfile.ZipFile(fetch(name, url)).extractall(data)
    print("MakeHuman is ready:", data)


if __name__ == "__main__":
    main()
