"""Lighting fixtures: moving heads, washes, beams, profiles, pars, strobes,
blinders, battens, tubes, followspots, hazers.

Sized like the class of fixture each stands for and nicknamed after it,
never a real brand or model number. Every fixture stands base-down with its
beam pointing up (Blender +Z) at home position; hung from truss it is simply
turned over. Moving heads export as three parts, Base > Yoke > Head, with
the yoke's origin on the pan axis and the head's on the tilt axis, so
Genesis can pan and tilt them.

    blender --background --factory-startup --python tools/blender/lighting.py
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import gnkit  # noqa: E402
from gnkit import box, cylinder, sphere, tube  # noqa: E402

SCRIPT = "lighting.py"
CATEGORY = "lighting"


def _hex_lenses(radius, lens_r, z, mat, rings=2):
    """Lenses packed in hexagonal rings, the face of an LED wash."""
    out = [cylinder("Lens", lens_r, 0.012, (0, 0, z), mat, verts=12)]
    for ring in range(1, rings + 1):
        for k in range(6 * ring):
            a = k * 2 * math.pi / (6 * ring)
            r = ring * lens_r * 2.1
            if r > radius - lens_r:
                continue
            out.append(cylinder("Lens", lens_r, 0.012, (math.cos(a) * r, math.sin(a) * r, z), mat, verts=12))
    return out


def _lens(z, radius, pal, centre=(0.0, 0.0), glow=0.45):
    """A front lens: a ring of dark glass round a bright centre, as a lit
    lens looks from the front, domed slightly proud of `z`."""
    cx, cy = centre
    gnkit.lathe("LensGlass", [(radius, z), (radius * glow, z + radius * 0.06)], pal["lens_glass"], 32, (cx, cy, 0))
    gnkit.lathe("LensCore", [(radius * glow, z + radius * 0.06), (radius * glow * 0.6, z + radius * 0.1), (0.0, z + radius * 0.11)],
                pal["lens_warm"], 32, (cx, cy, 0))


def _head(face, R, L, tilt_z, pal):
    """The head, its beam along +Z, built round its tilt point."""
    z0 = tilt_z
    if face == "beam":
        # A ball, split by a seam, with a small bright lens in a bezel.
        pts = [(R * math.sin(t * math.pi / 16), z0 - R * math.cos(t * math.pi / 16)) for t in range(0, 14)]
        gnkit.lathe("Ball", pts + [(R * 0.6, z0 + R * 0.83)], pal["paint"], 40)
        gnkit.lathe("Seam", [(R * 1.005, z0 - 0.004), (R * 1.005, z0 + 0.004)], pal["plastic"], 40)
        gnkit.lathe("Bezel", [(R * 0.6, z0 + R * 0.8), (R * 0.64, z0 + R * 0.84), (R * 0.64, z0 + R * 0.95),
                              (R * 0.52, z0 + R * 0.97), (R * 0.5, z0 + R * 0.93)], pal["dark_metal"], 40)
        _lens(z0 + R * 0.93, R * 0.5, pal, glow=0.4)
    elif face == "wash":
        # A short drum, a honeycomb of domed LED lenses in the front.
        gnkit.lathe("Drum", [(0.0, z0 - L * 0.5), (R * 0.78, z0 - L * 0.46), (R * 0.97, z0 - L * 0.25), (R, z0 - L * 0.05),
                             (R, z0 + L * 0.42), (R * 1.03, z0 + L * 0.46), (R * 1.03, z0 + L * 0.52),
                             (R * 0.94, z0 + L * 0.52), (R * 0.94, z0 + L * 0.48), (0.0, z0 + L * 0.48)], pal["paint"], 48)
        lens_r = R * 0.12
        rings = 3
        for ring in range(rings + 1):
            count = max(1, 6 * ring)
            for k in range(count):
                ang = 2 * math.pi * k / count
                rr = ring * lens_r * 2.15
                if rr + lens_r > R * 0.92:
                    continue
                _lens(z0 + L * 0.48, lens_r, pal, (math.cos(ang) * rr, math.sin(ang) * rr), glow=0.55)
    else:
        # A spot: a capsule, a wide bezel, a big front lens, vents behind.
        gnkit.lathe("Body", [(0.0, z0 - L * 0.5), (R * 0.55, z0 - L * 0.48), (R * 0.85, z0 - L * 0.41), (R * 0.98, z0 - L * 0.3),
                             (R, z0 - L * 0.2), (R, z0 + L * 0.38), (R * 1.04, z0 + L * 0.42), (R * 1.04, z0 + L * 0.54),
                             (R * 0.9, z0 + L * 0.55), (R * 0.88, z0 + L * 0.5), (0.0, z0 + L * 0.5)], pal["paint"], 48)
        for zz in (z0 - L * 0.1, z0 + L * 0.3):
            gnkit.lathe("Seam", [(R * 1.004, zz - 0.003), (R * 1.004, zz + 0.003)], pal["plastic"], 48)
        for k in range(10):
            a = 2 * math.pi * k / 10
            box("Vent", (0.006, 0.006, L * 0.14), (math.cos(a) * R * 0.995, math.sin(a) * R * 0.995, z0 - L * 0.28), pal["plastic"])
        _lens(z0 + L * 0.5, R * 0.87, pal, glow=0.42)
    # Tilt hubs, where the head meets the yoke.
    for s in (-1, 1):
        gnkit.lathe("TiltHub", [(R * 0.34, 0.0), (R * 0.34, 0.02 * s), (R * 0.2, 0.028 * s), (0.0, 0.028 * s)],
                    pal["dark_metal"], 32, (s * R * 0.98, 0.0, z0), axis="X")


def moving_head(name, label, base, arm_h, head_r, head_len, face="spot", lens_r=None):
    """base (w, d, h); arms rise arm_h above the base; the head is a drum of
    radius head_r and length head_len, its beam up. Three parts, Base >
    Yoke > Head, pivoting where the real ones do."""
    gnkit.reset()
    pal = gnkit.palette()
    bw, bd, bh = base
    lens_r = lens_r or head_r * 0.7
    # Base: rounded case, display and keys at the front, vents and handles on
    # the sides, rubber feet.
    before = set(bpy.data.objects)
    gnkit.bevel(box("Base", (bw, bd, bh), (0, 0, 0.012), pal["paint"]), min(0.03, bh * 0.2), 4)
    gnkit.picture("Display", bw * 0.26, bh * 0.36, (-bw * 0.08, bd / 2 + 0.0125, bh * 0.53), gnkit.screen_material("screen_small"), "+Y")
    for k in range(4):
        cylinder("Key", 0.007, 0.006, (bw * 0.12 + k * 0.022, bd / 2 + 0.003, bh * 0.52), pal["key"], axis="Y", verts=12)
    for sd in (-1, 1):
        for i in range(7):
            for j in range(2):
                box("Vent", (0.004, 0.012, 0.01), (sd * (bw / 2 + 0.001), -bd * 0.35 + i * 0.02, bh * 0.3 + j * 0.02),
                    pal["plastic"])
        gnkit.side_handle(sd * bw / 2, bd * 0.15, bh * 0.25, bd * 0.3, bh * 0.5, sd, pal["plastic"], pal["dark_metal"])
        for y in (-1, 1):
            cylinder("Foot", 0.02, 0.012, (sd * bw * 0.38, y * bd * 0.36, 0.006), pal["rubber"], verts=12)
    gnkit.lathe("Turntable", [(bd * 0.3, bh + 0.012), (bd * 0.3, bh + 0.022), (bd * 0.26, bh + 0.026), (0.0, bh + 0.026)],
                pal["dark_metal"], 40)
    base_obj = gnkit.join_group(gnkit.made_since(before), "Base")

    # Yoke: two round-ended arms on a bridge; pans about the vertical axis.
    span = head_r * 2 + 0.04
    arm_w = max(0.045, head_r * 0.3)
    arm_r = min(bd * 0.22, head_r * 0.62)
    tilt_z = bh + arm_h
    before = set(bpy.data.objects)
    gnkit.bevel(box("Bridge", (span + arm_w * 2, arm_r * 2, 0.05), (0, 0, bh + 0.022), pal["paint"]), 0.012, 3)
    for sd in (-1, 1):
        x = sd * (span / 2 + arm_w / 2)
        gnkit.bevel(gnkit.stadium("Arm", arm_r * 2, tilt_z - bh - 0.03, arm_r, arm_w, (x, 0.0, bh + 0.03), pal["paint"]),
                    0.01, 3)
        for k in range(4):
            box("ArmVent", (0.004, arm_r * 0.9, 0.008), (x + sd * arm_w / 2, 0.0, bh + 0.08 + k * 0.022), pal["plastic"])
    yoke = gnkit.join_group(gnkit.made_since(before), "Yoke", (0, 0, bh))

    # Head: tilts about the axis through the tops of the arms.
    before = set(bpy.data.objects)
    _head(face, head_r, head_len, tilt_z, pal)
    head = gnkit.join_group(gnkit.made_since(before), "Head", (0, 0, tilt_z))
    for o in (base_obj, yoke, head):
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))

    gnkit.parent(head, yoke)
    gnkit.parent(yoke, base_obj)
    gnkit.export(CATEGORY, name, SCRIPT, {"label": label, "kind": "moving_head", "face": face,
                                          "tilt_height_m": round(tilt_z, 3), "lens_radius_m": round(lens_r, 3)})


def _fixed(name, label, kind, extra=None):
    gnkit.join_all(name)
    info = {"label": label, "kind": kind}
    info.update(extra or {})
    gnkit.export(CATEGORY, name, SCRIPT, info)


def _yoke_and_clamp(width, height, pal):
    """A fixed fixture's stirrup yoke with a hook clamp on top of it,
    hanging (the clamp at the top, where the pipe would be)."""
    for s in (-1, 1):
        box("Stirrup", (0.012, 0.05, height), (s * width / 2, 0, 0), pal["dark_metal"])
    box("StirrupBar", (width + 0.012, 0.05, 0.012), (0, 0, 0), pal["dark_metal"])


def _stirrup(r, z_axis, pal, clamp=True):
    """A fixed fixture's yoke: a flat steel stirrup round the body, with a
    big lock knob each side and a hook clamp under the bar."""
    w = r + 0.018
    box("StirrupBar", (2 * w + 0.03, 0.04, 0.008), (0, 0, 0.0), pal["dark_metal"])
    for sd in (-1, 1):
        box("StirrupSide", (0.008, 0.04, z_axis + 0.02), (sd * (w + 0.011), 0, 0.0), pal["dark_metal"])
        gnkit.lathe("LockKnob", [(0.024, 0.0), (0.024, 0.02 * sd), (0.018, 0.028 * sd), (0.0, 0.028 * sd)], pal["plastic"], 24,
                    (sd * (w + 0.015), 0, z_axis), axis="X")
    if clamp:
        box("Clamp", (0.03, 0.05, 0.04), (0, 0, -0.04), pal["dark_metal"])
        tube("Hook", [(0, 0.02, -0.04), (0, 0.045, -0.06), (0, 0.035, -0.1), (0, -0.01, -0.11)], 0.008, pal["dark_metal"])


def par_can(name, label, led=False):
    gnkit.reset()
    pal = gnkit.palette()
    if led:
        r, length, z = 0.12, 0.13, 0.18
        gnkit.lathe("Body", [(0.0, z - length / 2), (r * 0.8, z - length / 2), (r, z - length * 0.3), (r, z + length / 2),
                             (r * 1.04, z + length / 2 + 0.01), (r * 0.95, z + length / 2 + 0.012), (0.0, z + length / 2 + 0.012)],
                    pal["paint"], 48)
        for k in range(12):
            a = 2 * math.pi * k / 12
            box("Fin", (0.004, 0.03, length * 0.6), (math.cos(a) * r * 0.9, math.sin(a) * r * 0.9, z - length * 0.4), pal["dark_metal"])
        for ring in range(4):
            for k in range(max(1, 6 * ring)):
                ang = 2 * math.pi * k / max(1, 6 * ring)
                rr = ring * r * 0.22
                if rr + r * 0.1 < r * 0.93:
                    _lens(z + length / 2 + 0.012, r * 0.1, pal, (math.cos(ang) * rr, math.sin(ang) * rr), glow=0.55)
        _stirrup(r, z, pal)
    else:
        # The classic can: flared back, straight body, rolled rim, colour
        # frame runners.
        r, length, z = 0.115, 0.36, 0.2
        gnkit.lathe("Can", [(0.0, z - length / 2 - 0.03), (r * 0.5, z - length / 2 - 0.03), (r * 0.95, z - length / 2 + 0.03),
                            (r, z - length / 2 + 0.06), (r, z + length / 2), (r * 1.1, z + length / 2 + 0.005),
                            (r * 1.1, z + length / 2 + 0.03), (r * 0.98, z + length / 2 + 0.03)], pal["paint"], 48)
        for zz in (z - length * 0.2, z + length * 0.2):
            gnkit.lathe("Rib", [(r * 1.006, zz - 0.004), (r * 1.006, zz + 0.004)], pal["paint"], 48)
        _lens(z + length / 2 + 0.02, r * 0.97, pal, glow=0.5)
        for sd in (-1, 1):
            box("Runner", (0.012, r * 2.2, 0.012), (sd * r * 1.02, 0, z + length / 2 + 0.028), pal["dark_metal"])
        _stirrup(r, z, pal)
    _fixed(name, label, "par")


def profile_spot(name, label):
    """An ellipsoidal: the lamp house, the shutter plane with its four
    handles, a long lens barrel, the lamp cap behind."""
    gnkit.reset()
    pal = gnkit.palette()
    z = 0.2
    gnkit.lathe("LampHouse", [(0.0, z - 0.2), (0.05, z - 0.19), (0.1, z - 0.13), (0.135, z - 0.04), (0.14, z + 0.06),
                              (0.13, z + 0.1)], pal["paint"], 48)
    gnkit.lathe("ShutterPlane", [(0.13, z + 0.1), (0.135, z + 0.1), (0.135, z + 0.17), (0.11, z + 0.17)], pal["paint"], 48)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        box("ShutterHandle", (0.03, 0.03, 0.015), (math.cos(a) * 0.155, math.sin(a) * 0.155, z + 0.12), pal["dark_metal"])
    gnkit.lathe("Barrel", [(0.11, z + 0.17), (0.105, z + 0.2), (0.105, z + 0.44), (0.115, z + 0.45), (0.115, z + 0.48),
                           (0.1, z + 0.48)], pal["paint"], 48)
    box("BarrelKnob", (0.02, 0.02, 0.03), (0.11, 0, z + 0.3), pal["plastic"])
    box("GelSlot", (0.24, 0.24, 0.012), (0, 0, z + 0.465), pal["dark_metal"])
    _lens(z + 0.48, 0.1, pal, glow=0.5)
    gnkit.lathe("LampCap", [(0.0, z - 0.26), (0.05, z - 0.25), (0.05, z - 0.19)], pal["dark_metal"], 32)
    _stirrup(0.14, z, pal)
    _fixed(name, label, "profile")


def fresnel(name, label):
    """A fresnel: a vented box body, a big stepped lens, four-leaf barn doors."""
    gnkit.reset()
    pal = gnkit.palette()
    z = 0.22
    gnkit.bevel(box("Housing", (0.28, 0.28, 0.3), (0, 0, z - 0.16), pal["paint"]), 0.025, 3)
    for k in range(6):
        box("Vent", (0.2, 0.3, 0.006), (0, 0, z + 0.16 + k * 0.012), pal["plastic"])
    gnkit.lathe("LensRing", [(0.13, z + 0.14), (0.135, z + 0.14), (0.135, z + 0.16), (0.12, z + 0.16)], pal["dark_metal"], 48)
    # The fresnel's rings, stepped.
    for k in range(4):
        rr = 0.12 - k * 0.028
        gnkit.lathe("Step", [(rr, z + 0.16), (rr - 0.01, z + 0.166 + k * 0.002), (rr - 0.028, z + 0.162)], pal["lens_glass"], 48)
    _lens(z + 0.162, 0.04, pal, glow=0.8)
    for k, (x, y) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
        w = 0.28 if k < 2 else 0.2
        door = box("Door", (w if k < 2 else 0.004, 0.004 if k < 2 else w, 0.14), (x * 0.14, y * 0.14, z + 0.16), pal["paint"])
        gnkit.rotate_about([door], "X" if k < 2 else "Y", (-35 if y > 0 else 35) if k < 2 else (35 if x > 0 else -35),
                           (x * 0.14, y * 0.14, z + 0.16))
    _stirrup(0.14, z, pal)
    _fixed(name, label, "fresnel")


def strobe(name, label):
    """An LED strobe: a rounded extruded body, a face of pixel cells behind
    clear domes, cooling fins, a yoke."""
    gnkit.reset()
    pal = gnkit.palette()
    w, d, h = 0.56, 0.22, 0.2
    prof = [(d / 2, 0.02), (d / 2, h - 0.02), (d / 2 - 0.02, h), (-d / 2 + 0.03, h), (-d / 2, h - 0.04), (-d / 2, 0.04),
            (-d / 2 + 0.03, 0.0), (d / 2 - 0.02, 0.0)]
    gnkit.bevel(gnkit.prism("Body", prof, w, pal["paint"]), 0.01, 3)
    # A flat bezel round the pixel face.
    for sy in (-1, 1):
        box("BezelLong", (w - 0.02, 0.012, 0.008), (0, sy * (d / 2 - 0.016), h), pal["dark_metal"])
    for sx in (-1, 1):
        box("BezelEnd", (0.012, d - 0.03, 0.008), (sx * (w / 2 - 0.016), 0, h), pal["dark_metal"])
    for i in range(12):
        for j in range(3):
            x = -w / 2 + 0.045 + i * (w - 0.09) / 11
            y = -d / 2 + 0.055 + j * (d - 0.11) / 2
            gnkit.lathe("Cell", [(0.018, h + 0.002), (0.012, h + 0.012), (0.0, h + 0.014)], pal["lens_warm"], 16, (x, y, 0))
    for sd in (-1, 1):
        for k in range(6):
            box("Fin", (0.004, d * 0.8, 0.05), (sd * (w / 2 - 0.02 - k * 0.012), 0, -0.05), pal["dark_metal"])
    _stirrup(w / 2 - 0.02, h * 0.5, pal)
    _fixed(name, label, "strobe")


def blinder(name, label, cells=4):
    """A blinder: warm lamps in polished reflector bowls, in a steel frame
    with side knobs and a handle."""
    gnkit.reset()
    pal = gnkit.palette()
    cols = 2 if cells >= 2 else 1
    rows = cells // cols
    cell = 0.24
    w, h = cols * cell, rows * cell
    # An open frame: a back pan, walls round the edge and between the cells,
    # so the bowls and lamps show from the front.
    gnkit.bevel(box("BackPan", (w + 0.04, h + 0.04, 0.07), (0, 0, 0.04), pal["paint"]), 0.015, 3)
    for sy in (-1, 1):
        box("Wall", (w + 0.04, 0.012, 0.11), (0, sy * (h / 2 + 0.014), 0.1), pal["paint"])
    for sx in (-1, 1):
        box("Wall", (0.012, h + 0.04, 0.11), (sx * (w / 2 + 0.014), 0, 0.1), pal["paint"])
    for i in range(1, cols):
        box("Divider", (0.006, h, 0.1), (-w / 2 + i * cell, 0, 0.1), pal["paint"])
    for j in range(1, rows):
        box("Divider", (w, 0.006, 0.1), (0, -h / 2 + j * cell, 0.1), pal["paint"])
    for i in range(cols):
        for j in range(rows):
            x = -w / 2 + cell / 2 + i * cell
            y = -h / 2 + cell / 2 + j * cell
            gnkit.lathe("Reflector", [(0.105, 0.21), (0.1, 0.2), (0.07, 0.15), (0.035, 0.12), (0.0, 0.118)], pal["alu"], 32,
                        (x, y, 0), caps=False)
            gnkit.lathe("Lamp", [(0.062, 0.16), (0.05, 0.175), (0.025, 0.182), (0.0, 0.184)], pal["lens_warm"], 32, (x, y, 0))
            gnkit.lathe("Rim", [(0.108, 0.205), (0.112, 0.214), (0.1, 0.214)], pal["dark_metal"], 32, (x, y, 0), caps=False)
    tube("Handle", [(-w * 0.3, h / 2 + 0.02, 0.1), (-w * 0.25, h / 2 + 0.07, 0.1), (w * 0.25, h / 2 + 0.07, 0.1),
                    (w * 0.3, h / 2 + 0.02, 0.1)], 0.01, pal["dark_metal"])
    _stirrup(w / 2 + 0.02, 0.1, pal)
    _fixed(name, label, "blinder", {"cells": cells})


def batten(name, label, length=1.0):
    """An LED batten: an aluminium extrusion with a lens cup per pixel, end
    caps, brackets."""
    gnkit.reset()
    pal = gnkit.palette()
    prof = [(0.045, 0.0), (0.045, 0.06), (0.038, 0.08), (-0.038, 0.08), (-0.045, 0.06), (-0.045, 0.0)]
    gnkit.bevel(gnkit.prism("Extrusion", [(y, z + 0.02) for y, z in prof], length, pal["alu"]), 0.004, 2)
    for k in range(6):
        box("Fin", (length - 0.02, 0.004, 0.012), (0, -0.045 + k * 0.018, 0.02), pal["dark_metal"])
    n = int(length / 0.055)
    for i in range(n):
        x = -length / 2 + 0.03 + i * 0.055
        gnkit.lathe("Cup", [(0.022, 0.1), (0.024, 0.104), (0.018, 0.104)], pal["plastic"], 16, (x, 0, 0))
        gnkit.lathe("Lens", [(0.018, 0.1), (0.012, 0.106), (0.0, 0.108)], pal["lens_warm"], 16, (x, 0, 0))
    for sd in (-1, 1):
        gnkit.bevel(box("EndCap", (0.014, 0.096, 0.088), (sd * (length / 2 + 0.007), 0, 0.016), pal["paint"]), 0.004, 2)
        box("Bracket", (0.012, 0.03, 0.08), (sd * (length / 2 - 0.08), 0, -0.06), pal["dark_metal"])
    _fixed(name, label, "batten", {"length_m": length})


def pixel_tube(name, label, length=1.0):
    """A battery LED tube, as used on stands or hung vertically."""
    gnkit.reset()
    pal = gnkit.palette()
    cylinder("Tube", 0.022, length, (0, 0, 0.02 + length / 2), pal["lens_lit"], verts=16)
    for z in (0.02, length + 0.02):
        cylinder("EndCap", 0.026, 0.04, (0, 0, z), pal["plastic"], verts=16)
    _fixed(name, label, "tube", {"length_m": length})


def followspot(name, label):
    gnkit.reset()
    pal = gnkit.palette()
    # A long body on a tall tripod stand, pointing forward (+Y).
    cylinder("Body", 0.15, 1.1, (0, 0.15, 1.55), pal["paint"], axis="Y", verts=32)
    cylinder("Lens", 0.14, 0.012, (0, 0.71, 1.55), pal["lens_lit"], axis="Y", verts=32)
    box("Handle", (0.03, 0.4, 0.03), (0.18, -0.35, 1.52), pal["plastic"])
    box("Yoke", (0.36, 0.08, 0.2), (0, 0.1, 1.28), pal["dark_metal"])
    cylinder("Post", 0.03, 1.15, (0, 0.1, 0.7), pal["dark_metal"], verts=12)
    for k in range(3):
        a = k * 2 * math.pi / 3
        tube("Leg", [(0, 0.1, 0.5), (math.cos(a) * 0.55, 0.1 + math.sin(a) * 0.55, 0.02)], 0.02, pal["dark_metal"])
        cylinder("Wheel", 0.04, 0.03, (math.cos(a) * 0.55, 0.1 + math.sin(a) * 0.55, 0.04), pal["rubber"], axis="X", verts=12)
    _fixed(name, label, "followspot")


def hazer(name, label, fogger=False):
    """A hazer or fog machine: a rounded case, carry handle, nozzle at the
    front, a status display and keys, a fan grille at the back, feet."""
    gnkit.reset()
    pal = gnkit.palette()
    w, d, h = (0.45, 0.3, 0.25) if fogger else (0.3, 0.55, 0.3)
    gnkit.bevel(box("Body", (w, d, h), (0, 0, 0.02), pal["paint"]), 0.03, 4)
    gnkit.lathe("NozzleMount", [(0.045, 0.0), (0.045, 0.02), (0.035, 0.03)], pal["dark_metal"], 24, (0, d / 2, 0.02 + h * 0.6),
                axis="Y")
    gnkit.lathe("Nozzle", [(0.022, 0.03), (0.02, 0.07), (0.012, 0.075), (0.0, 0.075)], pal["metal"], 24,
                (0, d / 2, 0.02 + h * 0.6), axis="Y")
    gnkit.picture("Display", 0.09, 0.045, (w * 0.22, -d / 2 - 0.001, 0.02 + h * 0.7), gnkit.screen_material("screen_small"), "-Y")
    for k in range(4):
        gnkit.lathe("Key", [(0.008, 0.0), (0.008, -0.005), (0.0, -0.006)], pal["key"], 12,
                    (w * 0.12 + k * 0.022, -d / 2, 0.02 + h * 0.45), axis="Y")
    gnkit.lathe("FanGrille", [(0.085, 0.0), (0.085, -0.006), (0.0, -0.006)], pal["grille"], 32, (-w * 0.18, -d / 2, 0.02 + h * 0.5),
                axis="Y")
    for sd in (-1, 1):
        box("Foot", (0.04, d - 0.06, 0.02), (sd * (w / 2 - 0.05), 0, 0), pal["rubber"])
    tube("Handle", [(-0.1, 0, 0.02 + h), (-0.08, 0, 0.06 + h), (0.08, 0, 0.06 + h), (0.1, 0, 0.02 + h)], 0.012, pal["dark_metal"])
    _fixed(name, label, "fogger" if fogger else "hazer")


def main():
    moving_head("spot_gigapointe", "Robo Gigapointe hybrid spot/beam", (0.4, 0.3, 0.14), 0.38, 0.13, 0.36, "spot")
    moving_head("spot_big_profile", "Big-Profile 1200 moving spot", (0.48, 0.36, 0.16), 0.52, 0.18, 0.5, "spot")
    moving_head("beam_sharply", "Sharply compact beam", (0.36, 0.26, 0.12), 0.3, 0.12, 0.2, "beam", lens_r=0.08)
    moving_head("wash_aurora", "Martian Aurora LED wash", (0.3, 0.24, 0.12), 0.26, 0.11, 0.14, "wash")
    moving_head("wash_impresso", "Impresso X5 big LED wash", (0.44, 0.34, 0.14), 0.4, 0.2, 0.18, "wash")
    moving_head("wash_diablito", "Diablito compact spot", (0.33, 0.25, 0.12), 0.28, 0.1, 0.26, "spot")
    par_can("par_64", "PAR 64 can")
    par_can("par_led", "LED par", led=True)
    profile_spot("profile_source_five", "Source Five ellipsoidal profile")
    fresnel("fresnel_1k", "1 kW fresnel with barn doors")
    strobe("strobe_atomik", "Atomik 3001 LED strobe")
    blinder("blinder_moley_2", "Moley 2-lite blinder", cells=2)
    blinder("blinder_moley_4", "Moley 4-lite blinder", cells=4)
    batten("batten_1m", "Stripe LED batten, 1 m", 1.0)
    pixel_tube("pixel_tube", "Astro pixel tube, 1 m", 1.0)
    followspot("followspot", "Long-throw followspot on stand")
    hazer("hazer", "Haze Station hazer")
    hazer("fogger", "Fog machine", fogger=True)


main()
