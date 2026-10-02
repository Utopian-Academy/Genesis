"""Animals for Genesis: modelled from real proportions.

Each animal is lofted, the way a sculptor blocks one out: the body is a
smooth sweep of cross-sections from the tail through the barrel and chest,
up the neck and out to the nose; each leg is a tapered sweep through its
real joints (shoulder, elbow, knee or hock, fetlock, hoof or paw); ears,
eyes, hooves, beaks, manes and tails are added; the whole is subdivided
smooth. The coat is painted onto the vertices by anatomy: a bay horse's
black points, a Holstein's patches, a tabby's stripes, a mallard's green
head.

Poses change the skeleton, not the model: a grazing animal's neck swings
down until its muzzle reaches the grass; a sitting dog or cat drops its
rump and folds its hind legs; a flying bird spreads its wings.

    blender --background --factory-startup --python tools/blender/animals.py
"""

import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import gnkit  # noqa: E402

SCRIPT = "animals.py"
CATEGORY = "animals"


# --- a little noise, for patches, stripes and wool ---------------------------

def _hash(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 144665) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h & 0xFFFF) / 65535.0


def noise(p, scale, seed=0):
    """Smooth value noise in 0..1."""
    x, y, z = p.x / scale, p.y / scale, p.z / scale
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = x - ix, y - iy, z - iz
    fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
    total = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (fx if dx else 1 - fx) * (fy if dy else 1 - fy) * (fz if dz else 1 - fz)
                total += w * _hash(ix + dx, iy + dy, iz + dz, seed)
    return total


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# --- quadrupeds ----------------------------------------------------------------
# Standing, in metres: y forward (nose at +y), z up, feet on z = 0. Body
# stations run tail to nose: (y, z, half width, half height[, squareness]).
# NECK is the index of the station where the neck starts (grazing swings
# everything from there). Legs: chains of (y, z, radius), at +/- x.

QUADS = {
    "horse": {
        # A 16-hand horse: level topline, withers a touch above the croup,
        # a deep narrow barrel, the chest jutting under the neck, belly
        # rising to the flank; a deep jaw tapering to the muzzle.
        "body": [(-0.99, 1.37, 0.06, 0.06), (-0.92, 1.38, 0.18, 0.19), (-0.78, 1.36, 0.25, 0.28, 2.2),
                 (-0.55, 1.33, 0.27, 0.33, 2.2), (-0.3, 1.3, 0.27, 0.34, 2.3), (0.0, 1.25, 0.27, 0.4, 2.3),
                 (0.28, 1.24, 0.25, 0.43, 2.2), (0.5, 1.26, 0.2, 0.42, 2.1), (0.64, 1.36, 0.15, 0.32), (0.76, 1.52, 0.12, 0.23),
                 (0.88, 1.68, 0.095, 0.17), (0.98, 1.82, 0.085, 0.13), (1.05, 1.86, 0.1, 0.15), (1.12, 1.78, 0.12, 0.18),
                 (1.21, 1.66, 0.1, 0.14), (1.32, 1.54, 0.085, 0.105), (1.41, 1.45, 0.08, 0.09), (1.47, 1.39, 0.078, 0.078),
                 (1.51, 1.35, 0.06, 0.06)],
        "neck": 8,
        "fore": (0.15, [(0.5, 1.28, 0.16, 0.08), (0.46, 1.05, 0.13, 0.12), (0.43, 0.93, 0.105), (0.46, 0.75, 0.078),
                        (0.48, 0.56, 0.052), (0.49, 0.5, 0.056), (0.5, 0.3, 0.038), (0.51, 0.17, 0.043), (0.54, 0.07, 0.045)]),
        "hind": (0.16, [(-0.62, 1.3, 0.2, 0.08), (-0.54, 1.1, 0.19, 0.12), (-0.42, 0.93, 0.145), (-0.5, 0.75, 0.1),
                        (-0.64, 0.56, 0.062), (-0.66, 0.5, 0.058), (-0.63, 0.3, 0.04), (-0.61, 0.17, 0.043), (-0.59, 0.07, 0.045)]),
        "hoof": (0.062, 0.048, 0.085),
        "tail": [(-0.99, 1.36, 0.045), (-1.06, 1.3, 0.07), (-1.12, 1.18, 0.085), (-1.15, 1.02, 0.095), (-1.16, 0.86, 0.095),
                 (-1.15, 0.72, 0.08), (-1.13, 0.62, 0.05), (-1.12, 0.57, 0.02)],
        "mane": True,
        "ears": [(0.05, 1.02, 1.97, 0.04, 0.15, "leaf")],
        "eyes": (0.1, 1.11, 1.8, 0.022),
        "height": 1.62,
    },
    "cow": {
        "body": [(-0.97, 1.3, 0.07, 0.07), (-0.88, 1.33, 0.24, 0.24, 2.8), (-0.62, 1.29, 0.31, 0.32, 3.2),
                 (-0.2, 1.18, 0.33, 0.39, 3.2), (0.2, 1.16, 0.32, 0.4, 3.0), (0.5, 1.17, 0.26, 0.36, 2.6),
                 (0.66, 1.17, 0.21, 0.32), (0.8, 1.22, 0.18, 0.27), (0.92, 1.24, 0.15, 0.22), (1.02, 1.22, 0.14, 0.18),
                 (1.12, 1.12, 0.13, 0.16), (1.24, 0.99, 0.11, 0.13), (1.33, 0.91, 0.105, 0.105), (1.38, 0.87, 0.09, 0.085),
                 (1.41, 0.85, 0.06, 0.06)],
        "neck": 6,
        "fore": (0.19, [(0.5, 1.2, 0.15, 0.09), (0.48, 0.95, 0.12, 0.15), (0.47, 0.75, 0.085), (0.5, 0.48, 0.058),
                        (0.5, 0.25, 0.048), (0.52, 0.07, 0.052)]),
        "hind": (0.2, [(-0.62, 1.2, 0.2, 0.09), (-0.52, 0.98, 0.17, 0.15), (-0.46, 0.8, 0.12), (-0.6, 0.5, 0.065),
                       (-0.58, 0.25, 0.048), (-0.56, 0.07, 0.052)]),
        "hoof": (0.06, 0.05, 0.07),
        "tail": [(-0.96, 1.28, 0.03), (-1.0, 1.0, 0.025), (-1.0, 0.62, 0.02), (-1.0, 0.45, 0.045), (-1.0, 0.38, 0.02)],
        "ears": [(0.13, 1.03, 1.2, 0.05, 0.13, "side")],
        "horns": (0.09, 1.01, 1.3),
        "eyes": (0.12, 1.12, 1.16, 0.024),
        "udder": (-0.55, 0.64, 0.15),
        "height": 1.4,
    },
    "sheep": {
        "body": [(-0.45, 0.62, 0.05, 0.05), (-0.4, 0.66, 0.2, 0.22), (-0.2, 0.64, 0.25, 0.26), (0.1, 0.64, 0.25, 0.26),
                 (0.3, 0.67, 0.21, 0.23), (0.4, 0.69, 0.14, 0.16), (0.48, 0.75, 0.1, 0.11), (0.56, 0.79, 0.08, 0.09),
                 (0.63, 0.75, 0.07, 0.08), (0.72, 0.67, 0.055, 0.06), (0.76, 0.64, 0.04, 0.045)],
        "neck": 5,
        "fore": (0.1, [(0.25, 0.52, 0.05), (0.25, 0.3, 0.03), (0.26, 0.1, 0.025), (0.27, 0.03, 0.028)]),
        "hind": (0.11, [(-0.3, 0.52, 0.06), (-0.25, 0.34, 0.04), (-0.32, 0.2, 0.025), (-0.3, 0.03, 0.028)]),
        "hoof": (0.03, 0.026, 0.04),
        "tail": [(-0.46, 0.62, 0.035), (-0.5, 0.55, 0.03), (-0.51, 0.47, 0.02)],
        "ears": [(0.075, 0.6, 0.79, 0.025, 0.08, "side")],
        "eyes": (0.06, 0.66, 0.78, 0.012),
        "wool": True,
        "height": 0.75,
    },
    "dog_large": {
        "body": [(-0.38, 0.52, 0.05, 0.05), (-0.32, 0.53, 0.12, 0.13), (-0.15, 0.52, 0.13, 0.15), (0.05, 0.5, 0.14, 0.18),
                 (0.2, 0.52, 0.13, 0.17), (0.3, 0.54, 0.1, 0.13), (0.36, 0.6, 0.08, 0.09), (0.42, 0.68, 0.07, 0.08),
                 (0.45, 0.73, 0.08, 0.08), (0.5, 0.735, 0.085, 0.075), (0.545, 0.715, 0.06, 0.055),
                 (0.59, 0.69, 0.05, 0.048, 2.6), (0.64, 0.675, 0.047, 0.044, 2.6), (0.665, 0.67, 0.035, 0.034)],
        "neck": 5,
        "fore": (0.08, [(0.22, 0.45, 0.045), (0.22, 0.3, 0.032), (0.23, 0.14, 0.024), (0.24, 0.05, 0.022)]),
        "hind": (0.085, [(-0.27, 0.46, 0.065), (-0.2, 0.32, 0.045), (-0.3, 0.17, 0.026), (-0.28, 0.05, 0.022)]),
        "paw": 0.035,
        "tail": [(-0.38, 0.53, 0.025), (-0.48, 0.5, 0.02), (-0.57, 0.42, 0.015), (-0.62, 0.34, 0.008)],
        "ears": [(0.07, 0.48, 0.77, 0.04, 0.12, "drop")],
        "eyes": (0.045, 0.535, 0.74, 0.012),
        "nose": (0.668, 0.68, 0.019),
        "height": 0.58,
        "sit_pivot": (0.2, 0.5),
    },
    "cat": {
        "body": [(-0.2, 0.24, 0.03, 0.03), (-0.17, 0.25, 0.07, 0.075), (-0.05, 0.24, 0.075, 0.085), (0.07, 0.24, 0.07, 0.08),
                 (0.14, 0.25, 0.055, 0.065), (0.18, 0.29, 0.045, 0.05), (0.21, 0.32, 0.05, 0.05), (0.24, 0.335, 0.053, 0.05),
                 (0.28, 0.32, 0.038, 0.034), (0.3, 0.31, 0.02, 0.02)],
        "neck": 5,
        "fore": (0.04, [(0.11, 0.2, 0.022), (0.11, 0.12, 0.014), (0.12, 0.03, 0.012)]),
        "hind": (0.045, [(-0.13, 0.2, 0.035), (-0.09, 0.13, 0.022), (-0.15, 0.06, 0.012), (-0.14, 0.02, 0.012)]),
        "paw": 0.016,
        "tail": [(-0.2, 0.25, 0.013), (-0.28, 0.28, 0.012), (-0.32, 0.36, 0.011), (-0.33, 0.46, 0.01), (-0.3, 0.52, 0.007)],
        "ears": [(0.03, 0.23, 0.37, 0.02, 0.045, "cat")],
        "eyes": (0.024, 0.275, 0.338, 0.009),
        "nose": (0.3, 0.315, 0.007),
        "height": 0.25,
        "sit_pivot": (0.1, 0.24),
    },
}
def _scaled(spec, s):
    """A copy of a spec scaled by s."""
    out = dict(spec)
    out["body"] = [tuple(v * s if i < 4 else v for i, v in enumerate(st)) for st in spec["body"]]
    out["fore"] = (spec["fore"][0] * s, [(y * s, z * s, r * s) for y, z, r in spec["fore"][1]])
    out["hind"] = (spec["hind"][0] * s, [(y * s, z * s, r * s) for y, z, r in spec["hind"][1]])
    out["tail"] = [(y * s, z * s, r * s) for y, z, r in spec["tail"]]
    out["ears"] = [(x * s, y * s, z * s, r * s, h * s, kind) for x, y, z, r, h, kind in spec["ears"]]
    out["eyes"] = tuple(v * s for v in spec["eyes"])
    out["nose"] = tuple(v * s for v in spec["nose"])
    out["paw"] = spec["paw"] * s
    out["height"] = spec["height"] * s
    out["sit_pivot"] = tuple(v * s for v in spec["sit_pivot"])
    return out


# A small terrier: the dog's plan at a little over half the size.
QUADS["dog_small"] = _scaled(QUADS["dog_large"], 0.55)
QUADS["dog_small"]["ears"] = [(0.03, 0.27, 0.415, 0.02, 0.045, "fold")]


def _rot_yz(p, pivot, deg):
    a = math.radians(deg)
    dy, dz = p[0] - pivot[0], p[1] - pivot[1]
    return (pivot[0] + dy * math.cos(a) - dz * math.sin(a), pivot[1] + dy * math.sin(a) + dz * math.cos(a))


def _pose(spec, pose):
    """Returns (body stations, fore chain, hind chain, tail chain, head
    transform) for a pose: the head transform maps standing head points
    (ears, eyes, nose) to where the pose puts them."""
    body = [list(s) for s in spec["body"]]
    fore = [list(p) for p in spec["fore"][1]]
    hind = [list(p) for p in spec["hind"][1]]
    tail = [list(p) for p in spec["tail"]]
    head_xf = lambda y, z: (y, z)  # noqa: E731
    if pose == "grazing":
        # Swing the neck and head down about the neck's base until the muzzle
        # meets the grass.
        n = spec["neck"]
        pivot = (body[n][0], body[n][1])
        nose = (body[-1][0], body[-1][1])
        best = 0.0
        for deg in range(0, 121):
            if _rot_yz(nose, pivot, -deg)[1] <= spec["height"] * 0.06:
                best = deg
                break
            best = deg
        for st in body[n + 1:]:
            st[0], st[1] = _rot_yz((st[0], st[1]), pivot, -best)
        head_xf = lambda y, z, p=pivot, d=best: _rot_yz((y, z), p, -d)  # noqa: E731
    elif pose == "sitting":
        # Drop the rump: everything behind the shoulders swings down about
        # them; the hind legs fold under.
        pivot = spec["sit_pivot"]
        h = spec["height"]
        rump = (body[1][0], body[1][1])
        dist = math.hypot(rump[0] - pivot[0], rump[1] - pivot[1])
        deg = math.degrees(math.asin(max(-1.0, min(1.0, (pivot[1] - h * 0.24) / max(dist, 1e-6)))))
        for st in body:
            if st[0] < pivot[0]:
                st[0], st[1] = _rot_yz((st[0], st[1]), pivot, deg)
        hip = _rot_yz((hind[0][0], hind[0][1]), pivot, deg)
        r = [p[2] for p in hind]
        hind = [[hip[0], hip[1], r[0]], [hip[0] + h * 0.22, h * 0.2, r[1]], [hip[0] - h * 0.02, h * 0.07, r[2]],
                [hip[0] + h * 0.16, h * 0.03, r[-1]]]
        t0 = _rot_yz((tail[0][0], tail[0][1]), pivot, deg)
        tail = [[t0[0], t0[1], tail[0][2]], [t0[0] - h * 0.12, h * 0.04, tail[1][2]],
                [t0[0] - h * 0.05, h * 0.02, tail[2][2]], [t0[0] + h * 0.1, h * 0.02, tail[-1][2]]]
    return body, fore, hind, tail, head_xf


def _leg(name, x, chain, mat, side=1):
    """A leg through its joints. A station may give its own distance from the
    midline (4th value): the muscle at the top of a leg sits inboard, inside
    the body, and flattens against it, so the leg grows out of the body
    rather than being stuck on."""
    stations = []
    if len(chain[0]) <= 3:
        # No muscle given: one is made, above and inboard of the first joint,
        # so the leg blends into the body instead of being stuck on.
        y, z, r = chain[0]
        chain = [(y + r * 0.3, z + r * 2.2, r * 1.9, x * 0.45), (y, z + r * 0.8, r * 1.5, x * 0.8)] + list(chain)
    for st in chain:
        y, z, r = st[0], st[1], st[2]
        sx = st[3] if len(st) > 3 else x
        flat = 0.6 if len(st) > 3 else 1.0
        stations.append(((side * sx, y, z), r * flat, r * 1.1))
    return gnkit.loft(name, stations, mat, ring=16, steps=3, caps=(False, True), up=(0, 1, 0))


def quadruped(kind, pose, colour_name, colour_at):
    gnkit.reset()
    spec = QUADS[kind]
    coat = gnkit.coat_material("Coat " + kind, 0.75)
    horn = gnkit.material("Horn", (0.08, 0.07, 0.06), 0.45)
    eye_mat = gnkit.material("Eye", (0.02, 0.015, 0.01), 0.05, 0.0)
    body, fore, hind, tail, head_xf = _pose(spec, pose)
    stations = [((0.0, s[0], s[1]), s[2], s[3], s[4] if len(s) > 4 else 2.0) for s in body]
    parts = [gnkit.loft("Body", stations, coat, ring=28, steps=4, turn=6)]
    for side in (-1, 1):
        parts.append(_leg("Fore", spec["fore"][0], fore, coat, side))
        parts.append(_leg("Hind", spec["hind"][0], hind, coat, side))
    # Tails hang: their sections take "up" from the body's length, so they
    # never twist where the tail turns straight down.
    parts.append(gnkit.loft("Tail", [((0.0, y, z), r, r) for y, z, r in tail], coat, ring=14, steps=5, up=(0, 1, 0)))
    # Hooves or paws at the foot of each leg.
    for side in (-1, 1):
        for chain, sx in ((fore, spec["fore"][0]), (hind, spec["hind"][0])):
            y, z, r = chain[-1]
            if "hoof" in spec:
                r1, r2, h = spec["hoof"]
                gnkit.lathe("Hoof", [(r1, 0.0), (r2, h), (0.0, h)], horn, 20, (side * sx, y + 0.005, 0.0))
            else:
                pr = spec["paw"]
                gnkit.sphere("Paw", pr, (side * sx, y + pr * 0.35, pr * 0.62), coat, scale=(0.95, 1.3, 0.62), segments=16)
                # The leg carries on down into the paw.
                gnkit.loft("Pastern", [((side * sx, y, z), r, r * 1.1), ((side * sx, y + pr * 0.2, pr * 0.7), r * 0.95, r)],
                           coat, ring=12, steps=2, up=(0, 1, 0))
    # Head details follow the head wherever the pose takes it.
    ex, ey, ez, er = spec["eyes"]
    for side in (-1, 1):
        y, z = head_xf(ey, ez)
        gnkit.sphere("Eye", er, (side * ex, y, z), eye_mat, segments=12)
        for x, ey2, ez2, r, h, ekind in spec["ears"]:
            y, z = head_xf(ey2, ez2)
            if ekind == "leaf":
                gnkit.loft("Ear", [((side * x, y, z - 0.02), r * 0.9, r * 0.5), ((side * (x + 0.01), y + 0.005, z + h * 0.5), r, r * 0.45),
                                   ((side * (x + 0.02), y, z + h), 0.004, 0.004)], coat, ring=10, steps=3, up=(0, 1, 0))
            elif ekind in ("up", "cat"):
                gnkit.cylinder("Ear", r, h, (side * x, y, z + h / 2), coat, verts=10, radius2=r * 0.15)
            elif ekind == "side":
                gnkit.loft("Ear", [((side * x, y, z), r * 0.5, r * 0.25), ((side * (x + h * 0.6), y - 0.01, z + 0.01), r, r * 0.35),
                                   ((side * (x + h), y - 0.02, z + 0.005), r * 0.3, r * 0.15)], coat, ring=10, steps=2)
            else:  # drop or fold: flaps hanging down beside the head
                gnkit.loft("Ear", [((side * x, y, z), r, r * 0.3), ((side * (x + r * 0.5), y + r * 0.2, z - h * 0.5), r * 1.1, r * 0.25),
                                   ((side * (x + r * 0.6), y + r * 0.3, z - h), r * 0.6, r * 0.2)], coat, ring=10, steps=3, up=(0, 1, 0))
    if "nose" in spec:
        ny, nz, nr = spec["nose"]
        y, z = head_xf(ny, nz)
        gnkit.sphere("Nose", nr, (0.0, y, z), eye_mat, scale=(1.3, 0.8, 0.9), segments=12)
    if "horns" in spec:
        hx, hy, hz = spec["horns"]
        y, z = head_xf(hy, hz)
        for side in (-1, 1):
            gnkit.loft("Horn", [((side * hx, y, z), 0.022, 0.022), ((side * (hx + 0.07), y + 0.01, z + 0.04), 0.014, 0.014),
                                ((side * (hx + 0.09), y + 0.03, z + 0.09), 0.004, 0.004)], horn, ring=8, steps=3)
    if "udder" in spec and pose != "sitting":
        uy, uz, ur = spec["udder"]
        gnkit.sphere("Udder", ur, (0.0, uy, uz), coat, scale=(1.0, 1.1, 0.8), segments=20)
        for sx in (-1, 1):
            for sy in (-1, 1):
                gnkit.cylinder("Teat", 0.012, 0.06, (sx * 0.05, uy + sy * 0.05, uz - ur * 0.8 - 0.02), coat, verts=8)
    if spec.get("mane"):
        n = spec["neck"]
        # The mane lies along the crest of the neck, from just in front of
        # the withers to the poll, sunk into it so it grows out of it.
        crest = []
        for k, st in enumerate(body[n:n + 5]):
            t = k / 4.0
            crest.append(((0.0, st[0] - 0.03, st[1] + st[3] * 0.8), 0.03 * (1 - 0.3 * t), 0.05 + 0.02 * math.sin(t * math.pi)))
        gnkit.loft("Mane", crest, coat, ring=10, steps=3, caps=(True, True))

    person = gnkit.join_all(kind)
    # Two levels, so a coat's markings have vertices enough for a clean edge;
    # then lightened back to a sensible count.
    gnkit.subdivide(person, 2)
    tris = gnkit.triangles(person)
    if tris > 70000:
        bpy.context.view_layer.objects.active = person
        mod = person.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = 70000 / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if spec.get("wool"):
        # Wool: the fleece bulges in tufts, the face and legs stay smooth.
        for v in person.data.vertices:
            if v.co.z > spec["height"] * 0.5 and v.co.y < spec["body"][spec["neck"]][0]:
                v.co += v.normal * (noise(v.co, 0.03, 7) - 0.3) * 0.035
    gnkit.paint_vertices(person, lambda p, n: colour_at(p, n, spec))
    bpy.ops.object.shade_smooth()
    name = "%s_%s_%s" % (kind, colour_name, pose) if colour_name else "%s_%s" % (kind, pose)
    gnkit.export(CATEGORY, name, SCRIPT, {"label": "%s, %s%s" % (kind.replace("_", " ").capitalize(), pose,
                                          ", " + colour_name.replace("_", " ") if colour_name else ""),
                                          "kind": "animal", "animal": kind, "pose": pose})


# Coats: colour at a point (world position, normal, spec).

def horse_bay(p, n, spec):
    base = (0.36, 0.17, 0.07)
    dark = (0.05, 0.04, 0.035)
    col = mix(base, (0.28, 0.13, 0.05), noise(p, 0.3, 1) * 0.6)
    if p.z < 0.52:  # black points below the knees and hocks
        col = mix(col, dark, smoothstep(0.52, 0.42, p.z))
    if p.y > 1.4 or (p.y > 1.2 and p.z > 1.6 and abs(p.x) < 0.02):
        col = mix(col, (0.12, 0.07, 0.05), 0.6)
    if (abs(p.x) < 0.045 and p.z > 1.55 and 0.6 < p.y < 1.08 and n.z > 0.1) or p.y < -1.0:  # mane and tail
        col = dark
    if abs(p.x) < 0.018 and p.y > 1.12 and n.y > 0.5 and p.z > 1.4:  # a narrow white blaze
        col = (0.9, 0.88, 0.84)
    return col


def horse_grey(p, n, spec):
    col = mix((0.72, 0.72, 0.7), (0.45, 0.45, 0.46), noise(p, 0.12, 3) ** 2)
    if p.z < 0.3 or p.y < -0.97:
        col = mix(col, (0.3, 0.3, 0.3), 0.5)
    return col


def cow_holstein(p, n, spec):
    white, black = (0.9, 0.89, 0.86), (0.04, 0.04, 0.04)
    if p.z < 0.45 or (p.z < 0.7 and abs(p.y + 0.55) < 0.2 and abs(p.x) < 0.2):  # legs, udder
        return white if p.z > 0.1 else (0.85, 0.72, 0.68)
    v = noise(p, 0.35, 11) + 0.3 * noise(p, 0.12, 12)
    col = mix(white, black, smoothstep(0.58, 0.68, v))
    if p.y > 1.35 and p.z < 1.0:  # muzzle
        col = (0.55, 0.45, 0.42)
    return col


def cow_brown(p, n, spec):
    col = mix((0.35, 0.18, 0.08), (0.25, 0.12, 0.05), noise(p, 0.4, 5))
    if p.y > 1.35 and p.z < 1.0:
        col = (0.6, 0.5, 0.45)
    return col


def sheep_blackface(p, n, spec):
    wool = mix((0.86, 0.83, 0.74), (0.72, 0.68, 0.58), noise(p, 0.04, 9))
    if p.y > spec["body"][spec["neck"]][0] + 0.06 or p.z < 0.42:
        return (0.06, 0.05, 0.05)
    return wool


def sheep_white(p, n, spec):
    if p.y > spec["body"][spec["neck"]][0] + 0.06 or p.z < 0.42:
        return (0.78, 0.74, 0.66)
    return mix((0.9, 0.88, 0.8), (0.76, 0.73, 0.64), noise(p, 0.04, 9))


def dog_yellow(p, n, spec):
    return mix((0.83, 0.64, 0.38), (0.7, 0.5, 0.27), noise(p, 0.15, 2) * 0.7 + max(0, n.z) * 0.2)


def dog_black(p, n, spec):
    return mix((0.05, 0.045, 0.04), (0.1, 0.09, 0.08), noise(p, 0.15, 2))


def dog_chocolate(p, n, spec):
    return mix((0.3, 0.17, 0.09), (0.22, 0.12, 0.06), noise(p, 0.15, 2))


def terrier(p, n, spec):
    white, tan = (0.9, 0.88, 0.84), (0.6, 0.38, 0.18)
    if p.y > spec["body"][spec["neck"]][0] + 0.02 and p.z > spec["height"] * 1.1:  # tan head and ears
        return tan if not (abs(p.x) < 0.012 and n.y > 0.4) else white
    if noise(p, 0.08, 4) > 0.68 and p.z > spec["height"] * 0.7:
        return tan
    return white


def cat_tabby(p, n, spec):
    base = (0.45, 0.38, 0.3)
    stripe = (0.12, 0.1, 0.08)
    # Stripes round the body and rings round the tail, broken by noise.
    s = math.sin(p.y * 90.0 + noise(p, 0.05, 6) * 5.0)
    col = mix(base, stripe, smoothstep(0.5, 0.9, s))
    if n.z < -0.4 and p.z < spec["height"]:  # pale belly
        col = mix(col, (0.8, 0.75, 0.65), 0.7)
    return col


def cat_ginger(p, n, spec):
    s = math.sin(p.y * 90.0 + noise(p, 0.05, 6) * 5.0)
    return mix((0.78, 0.45, 0.18), (0.6, 0.3, 0.1), smoothstep(0.4, 0.9, s))


def cat_black(p, n, spec):
    col = (0.04, 0.035, 0.035)
    if n.y > 0.5 and p.z < spec["height"] * 1.05 and p.z > spec["height"] * 0.6:  # white bib
        col = (0.85, 0.85, 0.83)
    return col


# --- birds -------------------------------------------------------------------------

BIRDS = {
    "pigeon": {"s": 1.0, "beak": (0.022, 0.006), "legs": 0.13, "span": 0.33},
    "seagull": {"s": 1.6, "beak": (0.05, 0.01), "legs": 0.15, "span": 0.65},
    "duck": {"s": 1.55, "beak": (0.05, 0.02), "legs": 0.09, "span": 0.45},
}


def bird(kind, pose, colour_at):
    gnkit.reset()
    spec = BIRDS[kind]
    s = spec["s"]
    coat = gnkit.coat_material("Plumage " + kind, 0.7)
    beak_mat = gnkit.material("Beak " + kind, (0.95, 0.7, 0.1) if kind != "pigeon" else (0.1, 0.09, 0.09), 0.4)
    leg_mat = gnkit.material("Legs " + kind, (0.9, 0.45, 0.2) if kind == "duck" else (0.75, 0.45, 0.45), 0.6)
    eye_mat = gnkit.material("Eye", (0.02, 0.015, 0.01), 0.05)
    lift = 0.0 if pose == "flying" else spec["legs"] * s * 0.6
    z0 = lift + 0.05 * s
    stations = [((0, -0.16 * s, z0 + 0.03 * s), 0.018 * s, 0.01 * s), ((0, -0.1 * s, z0 + 0.03 * s), 0.05 * s, 0.04 * s),
                ((0, -0.02 * s, z0 + 0.035 * s), 0.065 * s, 0.062 * s), ((0, 0.05 * s, z0 + 0.045 * s), 0.058 * s, 0.065 * s),
                ((0, 0.1 * s, z0 + 0.075 * s), 0.038 * s, 0.045 * s), ((0, 0.125 * s, z0 + 0.11 * s), 0.028 * s, 0.03 * s),
                ((0, 0.14 * s, z0 + 0.14 * s), 0.027 * s, 0.027 * s), ((0, 0.165 * s, z0 + 0.15 * s), 0.024 * s, 0.022 * s),
                ((0, 0.18 * s, z0 + 0.145 * s), 0.012 * s, 0.011 * s)]
    if kind == "duck":
        # A boat of a body, sitting lower and flatter.
        stations = [((0, -0.17 * s, z0 + 0.04 * s), 0.02 * s, 0.012 * s), ((0, -0.12 * s, z0 + 0.03 * s), 0.07 * s, 0.045 * s),
                    ((0, -0.02 * s, z0 + 0.03 * s), 0.08 * s, 0.06 * s), ((0, 0.07 * s, z0 + 0.035 * s), 0.07 * s, 0.06 * s),
                    ((0, 0.12 * s, z0 + 0.07 * s), 0.04 * s, 0.045 * s), ((0, 0.13 * s, z0 + 0.12 * s), 0.028 * s, 0.03 * s),
                    ((0, 0.145 * s, z0 + 0.155 * s), 0.03 * s, 0.03 * s), ((0, 0.17 * s, z0 + 0.16 * s), 0.024 * s, 0.022 * s),
                    ((0, 0.185 * s, z0 + 0.155 * s), 0.012 * s, 0.01 * s)]
    gnkit.loft("Body", stations, coat, ring=24, steps=4)
    head = Vector((0, 0.185 * s, z0 + (0.155 if kind == "duck" else 0.145) * s))
    bl, bh = spec["beak"]
    if kind == "duck":
        gnkit.loft("Bill", [((0, head.y - 0.005, head.z - 0.005), 0.014 * s, 0.009 * s),
                            ((0, head.y + bl * 0.6, head.z - 0.012), 0.016 * s, 0.006 * s),
                            ((0, head.y + bl, head.z - 0.016), 0.012 * s, 0.004 * s)], beak_mat, ring=12, steps=3)
    else:
        gnkit.loft("Beak", [((0, head.y - 0.004, head.z), bh, bh * 0.9), ((0, head.y + bl, head.z - bl * 0.12), 0.0015, 0.0015)],
                   beak_mat, ring=10, steps=3)
    for side in (-1, 1):
        gnkit.sphere("Eye", 0.006 * s, (side * 0.02 * s, head.y - 0.012 * s, head.z + 0.004 * s), eye_mat, segments=10)
    # Tail feathers: a fan behind.
    gnkit.loft("Tail", [((0, -0.15 * s, z0 + 0.03 * s), 0.02 * s, 0.004 * s), ((0, -0.22 * s, z0 + 0.025 * s), 0.035 * s, 0.003 * s),
                        ((0, -0.25 * s, z0 + 0.022 * s), 0.03 * s, 0.002 * s)], coat, ring=10, steps=3)
    if pose == "flying":
        span = spec["span"]
        for side in (-1, 1):
            st = [((side * 0.03 * s, 0.01 * s, z0 + 0.06 * s), 0.055 * s, 0.01 * s),
                  ((side * (span * 0.35), -0.005 * s, z0 + 0.075 * s), 0.06 * s, 0.007 * s),
                  ((side * (span * 0.7), -0.02 * s, z0 + 0.085 * s), 0.05 * s, 0.005 * s),
                  ((side * span, -0.05 * s, z0 + 0.08 * s), 0.018 * s, 0.003 * s)]
            gnkit.loft("Wing", st, coat, ring=12, steps=4)
    else:
        for side in (-1, 1):
            gnkit.loft("Wing", [((side * 0.055 * s, 0.07 * s, z0 + 0.06 * s), 0.008 * s, 0.03 * s),
                                ((side * 0.06 * s, -0.04 * s, z0 + 0.05 * s), 0.009 * s, 0.035 * s),
                                ((side * 0.04 * s, -0.16 * s, z0 + 0.035 * s), 0.005 * s, 0.015 * s)], coat, ring=10, steps=3,
                       up=(0, 0, 1))
            # Legs and feet.
            x = side * 0.02 * s
            gnkit.loft("Leg", [((x, 0.0, z0), 0.006 * s, 0.006 * s), ((x, 0.005 * s, 0.01), 0.0035 * s, 0.0035 * s)],
                       leg_mat, ring=8, steps=2, up=(0, 1, 0))
            for a in (-35, 0, 35):
                d = Vector((math.sin(math.radians(a)), math.cos(math.radians(a)), 0.0))
                gnkit.loft("Toe", [((x, 0.005 * s, 0.004), 0.0025 * s, 0.002 * s),
                                   ((x + d.x * 0.03 * s, 0.005 * s + d.y * 0.03 * s, 0.003), 0.0015 * s, 0.0015 * s)],
                           leg_mat, ring=6, steps=2)
            if kind == "duck":
                gnkit.box("Web", (0.04 * s, 0.03 * s, 0.002), (x, 0.02 * s, 0.001), leg_mat)
    b = gnkit.join_all(kind)
    gnkit.subdivide(b, 1)
    gnkit.paint_vertices(b, lambda p, n: colour_at(p, n, s, z0))
    bpy.ops.object.shade_smooth()
    gnkit.export(CATEGORY, "%s_%s" % (kind, pose), SCRIPT, {"label": "%s, %s" % (kind.capitalize(), pose),
                                                            "kind": "animal", "animal": kind, "pose": pose,
                                                            "wingspan_m": round(2 * spec["span"], 2)})


def pigeon_colours(p, n, s, z0):
    col = mix((0.45, 0.47, 0.52), (0.38, 0.4, 0.45), noise(p, 0.02, 3))
    if 0.1 * s < p.y < 0.15 * s and p.z > z0 + 0.07 * s:  # the iridescent neck
        col = mix((0.25, 0.38, 0.3), (0.4, 0.25, 0.4), noise(p, 0.01, 4))
    if p.y < -0.22 * s:  # dark tail band
        col = (0.12, 0.12, 0.14)
    if abs(p.x) > 0.045 * s and -0.06 * s < p.y < -0.02 * s:  # wing bars
        col = (0.15, 0.15, 0.17)
    return col


def gull_colours(p, n, s, z0):
    white, grey = (0.93, 0.93, 0.92), (0.6, 0.63, 0.67)
    col = white
    if abs(p.x) > 0.05 * s and p.z > z0 + 0.045 * s:  # wings and back
        col = grey
    if abs(p.x) > 0.5 * s * 0.8 or (abs(p.x) > 0.04 * s and p.y < -0.12 * s and p.z > z0 + 0.04 * s):
        col = (0.05, 0.05, 0.06)  # black tips
    return col


def mallard_colours(p, n, s, z0):
    if p.z > z0 + 0.13 * s:
        return mix((0.03, 0.28, 0.13), (0.1, 0.18, 0.35), noise(p, 0.01, 5) * 0.6)  # green head
    if abs(p.z - (z0 + 0.12 * s)) < 0.006 * s:
        return (0.92, 0.92, 0.9)  # white collar
    if p.y > 0.07 * s:
        return (0.42, 0.2, 0.12)  # chestnut breast
    if p.y < -0.15 * s:
        return (0.05, 0.05, 0.05)
    return mix((0.62, 0.62, 0.6), (0.5, 0.5, 0.48), noise(p, 0.01, 6))


def main():
    only = os.environ.get("GN_ANIMAL", "")
    jobs = [
        ("horse", "standing", "bay", horse_bay), ("horse", "grazing", "bay", horse_bay),
        ("horse", "standing", "grey", horse_grey),
        ("cow", "standing", "holstein", cow_holstein), ("cow", "grazing", "holstein", cow_holstein),
        ("cow", "standing", "brown", cow_brown),
        ("sheep", "standing", "", sheep_blackface), ("sheep", "grazing", "", sheep_blackface),
        ("sheep", "standing", "white", sheep_white),
        ("dog_large", "standing", "yellow", dog_yellow), ("dog_large", "sitting", "black", dog_black),
        ("dog_large", "standing", "chocolate", dog_chocolate),
        ("dog_small", "standing", "", terrier), ("dog_small", "sitting", "", terrier),
        ("cat", "standing", "tabby", cat_tabby), ("cat", "sitting", "ginger", cat_ginger), ("cat", "sitting", "black", cat_black),
    ]
    for kind, pose, colour, fn in jobs:
        if only and not kind.startswith(only):
            continue
        quadruped(kind, pose, colour, fn)
    for kind, fn in (("pigeon", pigeon_colours), ("seagull", gull_colours), ("duck", mallard_colours)):
        if only and not kind.startswith(only):
            continue
        for pose in ("standing", "flying"):
            bird(kind, pose, fn)


main()
