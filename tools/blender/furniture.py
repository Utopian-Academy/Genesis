"""Event furniture and props: seating, clothed tables, crowd control,
backstage cases, and the venue kit an outdoor show is built from.

Seating and tables export to genesis_assets/furniture, everything else to
genesis_assets/props. Named after the class of product each stands for,
never a real brand or model number. Seats face +Y (the way the sitter looks);
a crowd barrier's +Y is the audience side; a bar's +Y is where customers stand.

    blender --background --factory-startup --python tools/blender/furniture.py
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import gnkit  # noqa: E402
from gnkit import box, cylinder, sphere, tube  # noqa: E402

SCRIPT = "furniture.py"


def _export(category, name, label, kind, extra=None):
    gnkit.join_all(name)
    info = {"label": label, "kind": kind}
    info.update(extra or {})
    gnkit.export(category, name, SCRIPT, info)


def _mats():
    """The palette plus the finishes only event furniture needs."""
    pal = gnkit.palette()
    m = gnkit.material
    k = gnkit.kit_material
    pal.update({
        "gold": m("Gold frame", (0.83, 0.62, 0.25), 0.3, 1.0),
        "chrome": k("chrome", "Chrome"),
        "galv": k("alu_brushed", "Galvanised steel"),
        "burgundy": k("fabric_burgundy", "Burgundy fabric"),
        "velvet": k("velvet_red", "Red velvet"),
        # A white leather scan is a tinted dark one, and tinting it that far
        # turns its grain into blotches; white upholstery reads cleanly.
        "leather": k("fabric_white", "White upholstery"),
        "black_leather": k("leather_black", "Black leather"),
        "linen": k("linen", "Table linen"),
        "spandex": k("fabric_white", "White spandex"),
        "wood": k("wood_light", "Birch ply"),
        "tread": k("diamond_plate", "Tread plate"),
        "poly": k("plastic_black", "Charcoal polypropylene"),
        "counter": m("Bar top", (0.03, 0.03, 0.035), 0.25),
        "bar_front": m("Bar front", (0.92, 0.92, 0.9), 0.4),
        "led_white": m("LED strip", (0.9, 0.9, 1.0), 0.3, emission=(0.8, 0.85, 1.0), strength=3.0),
        "loo": m("Portable toilet blue", (0.05, 0.2, 0.55), 0.5),
        "loo_roof": m("Translucent roof", (0.85, 0.87, 0.85), 0.4, alpha=0.85),
        "booth": m("Booth paint", (0.9, 0.88, 0.82), 0.6),
        "awning": m("Awning red", (0.6, 0.06, 0.06), 0.8),
        "window": m("Booth glass", (0.5, 0.6, 0.65), 0.05, alpha=0.3),
        "tent": m("Stretch tent fabric", (0.82, 0.74, 0.6), 0.85),
        "rope": m("Guy rope", (0.85, 0.8, 0.65), 0.9),
        "flag": m("Flag print", (0.0, 0.55, 0.6), 0.8),
        "foam": k("rubber", "Barrier padding"),
    })
    return pal


def _cushion(obj, radius=0.035):
    """Round a cushion's edges into a seam: wide and in several segments."""
    return gnkit.bevel(obj, radius, segments=4)


def _legs(points, top, r, mat, verts=10):
    """Straight legs from each floor point (x, y) up to z=top."""
    for x, y in points:
        cylinder("Leg", r, top, (x, y, top / 2), mat, verts=verts)


def _pleat(obj, depth, folds=16, amount=0.035):
    """Ripple the hem of a cloth cone so it hangs in folds."""
    for v in obj.data.vertices:
        if v.co.z < -depth / 2 + 0.01:
            a = math.atan2(v.co.y, v.co.x)
            k = 1 + amount * math.cos(folds * a)
            v.co.x *= k
            v.co.y *= k


def _solidify(obj, thickness):
    """Give a single-sided sheet thickness so both faces render in Godot."""
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 0
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def _sheet(name, verts, faces, mat):
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in verts]
    for f in faces:
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    data = bpy.data.meshes.new(name)
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def _castors(w, d, pal, inset=0.08):
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (w / 2 - inset), sy * (d / 2 - inset)
            cylinder("Castor", 0.05, 0.035, (x, y, 0.05), pal["rubber"], axis="X", verts=12)
            box("Fork", (0.05, 0.06, 0.04), (x, y, 0.07), pal["metal"])
            box("CastorPlate", (0.1, 0.1, 0.01), (x, y, 0.11), pal["metal"])


# ---------------------------------------------------------------------------
# Seating
# ---------------------------------------------------------------------------

def banquet_chair(name, label):
    """A padded steel-framed banquet chair, the ballroom workhorse."""
    gnkit.reset()
    pal = _mats()
    seat = 0.46
    _legs([(-0.2, 0.19), (0.2, 0.19)], seat - 0.06, 0.011, pal["gold"])
    back = []
    for s in (-1, 1):
        back.append(tube("RearPost", [(s * 0.2, -0.19, 0), (s * 0.2, -0.2, seat), (s * 0.2, -0.2, 0.93)],
                         0.011, pal["gold"]))
    back.append(tube("TopRail", [(-0.2, -0.2, 0.93), (0.2, -0.2, 0.93)], 0.011, pal["gold"]))
    back.append(_cushion(box("BackPad", (0.38, 0.05, 0.34), (0, -0.19, 0.55), pal["burgundy"])))
    gnkit.rotate_about(back, "X", 7, (0, -0.2, seat))
    box("SeatFrame", (0.43, 0.42, 0.03), (0, 0, seat - 0.06), pal["gold"])
    _cushion(box("SeatPad", (0.44, 0.43, 0.07), (0, 0.005, seat - 0.035), pal["burgundy"]))
    for y in (-0.19, 0.19):
        tube("Rung", [(-0.2, y, 0.14), (0.2, y, 0.14)], 0.007, pal["gold"])
    _export("furniture", name, label, "chair", {"seat_height_m": seat})


def chiavari_chair(name, label):
    """The spindle-backed wedding chair, with its seat cushion."""
    gnkit.reset()
    pal = _mats()
    seat = 0.45
    for s in (-1, 1):
        tube("FrontLeg", [(s * 0.2, 0.2, 0), (s * 0.185, 0.18, seat)], 0.013, pal["gold"])
        tube("RearPost", [(s * 0.2, -0.22, 0), (s * 0.185, -0.18, seat), (s * 0.175, -0.21, 0.92)], 0.013, pal["gold"])
    for z in (0.18, 0.3):
        tube("SideRung", [(-0.195, 0.19, z), (-0.195, -0.2, z)], 0.007, pal["gold"])
        tube("SideRung", [(0.195, 0.19, z), (0.195, -0.2, z)], 0.007, pal["gold"])
    tube("FrontRung", [(-0.19, 0.19, 0.18), (0.19, 0.19, 0.18)], 0.007, pal["gold"])
    box("SeatRail", (0.39, 0.38, 0.04), (0, 0, seat - 0.04), pal["gold"])
    _cushion(box("Cushion", (0.37, 0.36, 0.045), (0, 0, seat), pal["white_fabric"]))
    for z in (0.62, 0.78, 0.9):
        tube("BackRail", [(-0.18, -0.195, z), (0.18, -0.195, z)], 0.01 if z < 0.9 else 0.014, pal["gold"])
    for k in range(5):
        x = -0.12 + k * 0.06
        tube("Spindle", [(x, -0.19, seat + 0.02), (x, -0.2, 0.62)], 0.006, pal["gold"])
    _export("furniture", name, label, "chair", {"seat_height_m": seat})


def stacking_chair(name, label):
    """A stacking conference chair: plastic shell on a chrome four-leg frame."""
    gnkit.reset()
    pal = _mats()
    seat = 0.45
    for s in (-1, 1):
        tube("SideFrame", [(s * 0.21, 0.21, 0), (s * 0.2, 0.18, seat - 0.02), (s * 0.2, -0.18, seat - 0.02),
                           (s * 0.21, -0.23, 0)], 0.01, pal["chrome"])
        tube("BackUpright", [(s * 0.2, -0.18, seat - 0.02), (s * 0.2, -0.22, 0.84)], 0.01, pal["chrome"])
    gnkit.bevel(box("SeatShell", (0.45, 0.43, 0.025), (0, 0, seat - 0.01), pal["poly"]), 0.01)
    box("FrontLip", (0.45, 0.03, 0.03), (0, 0.2, seat - 0.03), pal["poly"])
    back = gnkit.bevel(box("BackShell", (0.44, 0.02, 0.3), (0, -0.215, 0.53), pal["poly"]), 0.01)
    gnkit.rotate_about([back], "X", 8, (0, -0.2, seat))
    tube("Brace", [(-0.2, 0.0, seat - 0.03), (0.2, 0.0, seat - 0.03)], 0.007, pal["chrome"])
    _export("furniture", name, label, "chair", {"seat_height_m": seat})


def theatre_seats(name, label):
    """Two fixed theatre seats between standards, seats down."""
    gnkit.reset()
    pal = _mats()
    for x in (-0.53, 0.0, 0.53):
        gnkit.bevel(box("Standard", (0.05, 0.58, 0.62), (x, -0.02, 0), pal["paint"]), 0.01)
        gnkit.bevel(box("Armrest", (0.07, 0.5, 0.04), (x, 0.0, 0.62), pal["wood"]), 0.012)
    for x in (-0.265, 0.265):
        _cushion(box("Seat", (0.46, 0.44, 0.1), (x, 0.06, 0.38), pal["velvet"]))
        box("SeatPan", (0.46, 0.42, 0.02), (x, 0.06, 0.36), pal["paint"])
        back = _cushion(box("Back", (0.47, 0.1, 0.52), (x, -0.22, 0.44), pal["velvet"]))
        shell = box("BackShell", (0.47, 0.02, 0.52), (x, -0.28, 0.44), pal["paint"])
        gnkit.rotate_about([back, shell], "X", 12, (x, -0.22, 0.44))
    _export("furniture", name, label, "theatre_seating", {"seats": 2, "seat_pitch_m": 0.53})


def bar_stool(name, label):
    gnkit.reset()
    pal = _mats()
    seat = 0.76
    cylinder("Base", 0.22, 0.02, (0, 0, 0.01), pal["chrome"], verts=32)
    cylinder("Column", 0.025, seat - 0.12, (0, 0, (seat - 0.12) / 2 + 0.02), pal["chrome"], verts=16)
    cylinder("GasLift", 0.035, 0.18, (0, 0, seat - 0.19), pal["plastic"], verts=16)
    ring = [(0.19 * math.cos(a * math.pi / 12), 0.19 * math.sin(a * math.pi / 12), 0.3) for a in range(25)]
    tube("FootRing", ring, 0.009, pal["chrome"])
    for k in range(3):
        a = k * 2 * math.pi / 3
        tube("Spoke", [(0, 0, 0.3), (0.19 * math.cos(a), 0.19 * math.sin(a), 0.3)], 0.008, pal["chrome"])
    gnkit.bevel(cylinder("Seat", 0.19, 0.07, (0, 0, seat - 0.035), pal["black_leather"], verts=32), 0.02)
    _export("furniture", name, label, "stool", {"seat_height_m": seat})


def lounge_sofa(name, label):
    """A three-seat event lounge sofa in white leather."""
    gnkit.reset()
    pal = _mats()
    w, d = 2.0, 0.85
    gnkit.bevel(box("Plinth", (w, d, 0.24), (0, 0, 0.06), pal["leather"]), 0.02)
    for k in (-1, 0, 1):
        _cushion(box("SeatCushion", (0.6, 0.62, 0.13), (k * 0.6, 0.1, 0.3), pal["leather"]))
        cushion = _cushion(box("BackCushion", (0.58, 0.16, 0.36), (k * 0.6, -0.24, 0.43), pal["leather"]))
        gnkit.rotate_about([cushion], "X", 10, (k * 0.6, -0.24, 0.43))
    _cushion(box("Back", (w, 0.18, 0.5), (0, -d / 2 + 0.09, 0.3), pal["leather"]))
    for s in (-1, 1):
        gnkit.bevel(box("Arm", (0.2, d, 0.32), (s * (w / 2 - 0.1), 0, 0.3), pal["leather"]), 0.04)
        for y in (-1, 1):
            cylinder("Foot", 0.025, 0.06, (s * (w / 2 - 0.08), y * (d / 2 - 0.08), 0.03), pal["chrome"], verts=10)
    _export("furniture", name, label, "sofa", {"seats": 3, "seat_height_m": 0.43})


def ottoman(name, label):
    gnkit.reset()
    pal = _mats()
    _cushion(box("Body", (0.5, 0.5, 0.38), (0, 0, 0.05), pal["leather"]))
    for x in (-0.19, 0.19):
        for y in (-0.19, 0.19):
            cylinder("Foot", 0.02, 0.05, (x, y, 0.025), pal["chrome"], verts=10)
    _export("furniture", name, label, "ottoman", {"seat_height_m": 0.43})


# ---------------------------------------------------------------------------
# Tables
# ---------------------------------------------------------------------------

def _drape(r, top, folds, amount, mat, overhang=0.012, hem=0.06):
    """A round cloth: over the top, a rolled edge, and a skirt whose folds
    are nothing at the table edge and deepest at the hem."""
    profile = [(0.0, top + 0.006), (r + overhang, top + 0.006), (r + overhang + 0.012, top - 0.01)]
    steps = 12
    for i in range(1, steps + 1):
        f = i / steps
        profile.append((r + overhang + 0.012 + (hem - overhang - 0.012) * f ** 1.6, (top - 0.01) * (1 - f) + 0.004))
    cloth = gnkit.lathe("Cloth", profile, mat, segments=120)
    for v in cloth.data.vertices:
        depth = (top - v.co.z) / top
        if depth <= 0.02:
            continue
        a = math.atan2(v.co.y, v.co.x)
        wave = math.cos(folds * a) + 0.35 * math.cos(2.3 * folds * a + 1.1)
        k = 1 + amount * wave * depth ** 1.3
        v.co.x *= k
        v.co.y *= k
    gnkit.smooth(cloth, 60)
    return cloth


def round_table(name, label, diameter):
    """A round banquet table under a floor-length cloth."""
    gnkit.reset()
    pal = _mats()
    r, top = diameter / 2, 0.76
    _drape(r, top, 14, 0.03, pal["linen"])
    _export("furniture", name, label, "table", {"diameter_m": diameter, "height_m": top, "seats": 8 if diameter < 1.7 else 10})


def cocktail_table(name, label):
    """A poseur table with a stretch spandex cover pulled down its column."""
    gnkit.reset()
    pal = _mats()
    top, r = 1.1, 0.3
    cylinder("Top", r + 0.005, 0.03, (0, 0, top - 0.015), pal["spandex"], verts=40)
    cylinder("UpperCover", r, 0.3, (0, 0, top - 0.18), pal["spandex"], verts=40, radius2=0.04)
    gnkit.smooth(bpy.context.active_object)
    cylinder("ColumnCover", 0.04, 0.72, (0, 0, 0.51), pal["spandex"], verts=20)
    cylinder("BaseCover", 0.3, 0.15, (0, 0, 0.075), pal["spandex"], verts=40, radius2=0.04)
    gnkit.smooth(bpy.context.active_object)
    _export("furniture", name, label, "table", {"diameter_m": 0.6, "height_m": top})


def trestle_table(name, label):
    """A 6 ft trestle under a white cloth that falls to the floor all round."""
    gnkit.reset()
    pal = _mats()
    w, d, top = 1.83, 0.76, 0.74
    gnkit.bevel(box("Cloth", (w + 0.03, d + 0.03, top), (0, 0, 0), pal["linen"]), 0.01)
    box("ClothTop", (w + 0.02, d + 0.02, 0.01), (0, 0, top), pal["linen"])
    _export("furniture", name, label, "table", {"width_m": w, "depth_m": d, "height_m": top})


def bar_counter(name, label):
    """A 2 m bar: customers at +Y, staff at -Y with a back shelf."""
    gnkit.reset()
    pal = _mats()
    w, h = 2.0, 1.1
    gnkit.bevel(box("Front", (w, 0.5, h - 0.04), (0, 0, 0.06), pal["bar_front"]), 0.01)
    box("Plinth", (w - 0.04, 0.46, 0.06), (0, -0.01, 0), pal["paint"])
    box("LedStrip", (w - 0.06, 0.01, 0.015), (0, 0.235, 0.07), pal["led_white"])
    gnkit.bevel(box("Top", (w + 0.1, 0.72, 0.04), (0, 0.05, h - 0.04), pal["counter"]), 0.006)
    box("ServiceShelf", (w - 0.04, 0.32, 0.03), (0, -0.4, 0.88), pal["counter"])
    for s in (-1, 1):
        box("ShelfBracket", (0.03, 0.3, 0.88), (s * (w / 2 - 0.03), -0.4, 0), pal["dark_metal"])
    _export("furniture", name, label, "bar", {"width_m": w, "height_m": h})


# ---------------------------------------------------------------------------
# Crowd control
# ---------------------------------------------------------------------------

def crowd_barrier(name, label):
    """One 1 m front-of-stage barrier section. The audience stands on the
    footplate at +Y, which is what holds it down; security gets a step at -Y."""
    gnkit.reset()
    pal = _mats()
    w, h = 1.0, 1.2
    oy = -0.225                      # centres the -0.55..+1.0 footprint
    box("Footplate", (w, 1.0, 0.015), (0, 0.5 + oy, 0), pal["tread"])
    for s in (-1, 1):
        x = s * (w / 2 - 0.02)
        gnkit.prism("SideFrame", [(0.06 + oy, 0), (0.02 + oy, h), (-0.1 + oy, h), (-0.55 + oy, 0.02),
                                  (-0.55 + oy, 0)], 0.03, pal["alu"], x=x)
    box("Face", (w, 0.012, h - 0.06), (0, 0.035 + oy, 0.02), pal["alu"])
    for z in (0.3, 0.7):
        box("FaceRib", (w, 0.02, 0.03), (0, 0.05 + oy, z), pal["alu"])
    cylinder("TopPad", 0.05, w, (0, -0.04 + oy, h), pal["foam"], axis="X", verts=16)
    box("Step", (w - 0.04, 0.34, 0.03), (0, -0.32 + oy, 0.34), pal["tread"])
    for s in (-1, 1):
        box("StepLeg", (0.03, 0.03, 0.34), (s * (w / 2 - 0.06), -0.45 + oy, 0), pal["alu"])
    for s in (-1, 1):
        box("Coupler", (0.02, 0.06, 0.08), (s * (w / 2 + 0.01), -0.02 + oy, 0.9), pal["dark_metal"])
    _export("props", name, label, "crowd_barrier",
            {"section_width_m": w, "height_m": h, "audience_side": "+Y"})


def bike_rack(name, label):
    """A 2.3 m galvanised crowd-control barrier on bridge feet."""
    gnkit.reset()
    pal = _mats()
    w, h = 2.3, 1.1
    tube("Frame", [(-w / 2, 0, 0.1), (-w / 2, 0, h), (w / 2, 0, h), (w / 2, 0, 0.1)], 0.02, pal["galv"])
    tube("BottomRail", [(-w / 2, 0, 0.14), (w / 2, 0, 0.14)], 0.016, pal["galv"])
    n = 18
    for k in range(1, n):
        x = -w / 2 + k * w / n
        tube("Bar", [(x, 0, 0.14), (x, 0, h)], 0.008, pal["galv"])
    for s in (-1, 1):
        x = s * (w / 2 - 0.05)
        tube("Foot", [(x, -0.33, 0.02), (x, -0.3, 0.1), (x, 0.3, 0.1), (x, 0.33, 0.02)], 0.012, pal["galv"])
        tube("FootPost", [(x, 0, 0.1), (s * w / 2, 0, 0.14)], 0.014, pal["galv"])
    for z in (0.3, 0.9):
        tube("Hook", [(w / 2, 0, z), (w / 2 + 0.05, 0, z), (w / 2 + 0.05, 0, z - 0.04)], 0.007, pal["galv"])
        tube("Loop", [(-w / 2, 0, z + 0.02), (-w / 2 - 0.03, 0, z + 0.02), (-w / 2 - 0.03, 0, z - 0.04),
                      (-w / 2, 0, z - 0.04)], 0.007, pal["galv"])
    _export("props", name, label, "crowd_barrier", {"section_width_m": w, "height_m": h})


def stanchions(name, label):
    """Two chrome posts 1.5 m apart with a velvet rope sagging between them."""
    gnkit.reset()
    pal = _mats()
    gap, h = 1.5, 0.95
    for s in (-1, 1):
        x = s * gap / 2
        cylinder("Base", 0.16, 0.025, (x, 0, 0.0125), pal["chrome"], verts=32)
        cylinder("Dome", 0.14, 0.04, (x, 0, 0.045), pal["chrome"], verts=32, radius2=0.03)
        cylinder("Post", 0.025, h - 0.07, (x, 0, 0.065 + (h - 0.07) / 2), pal["chrome"], verts=16)
        sphere("Finial", 0.04, (x, 0, h + 0.02), pal["chrome"])
        box("RopeHook", (0.04, 0.02, 0.03), (x - s * 0.035, 0, h - 0.08), pal["chrome"])
    z, sag = h - 0.07, 0.25
    pts = []
    for k in range(17):
        t = -1 + 2 * k / 16
        pts.append((t * (gap / 2 - 0.06), 0, z - sag * (1 - t * t)))
    tube("Rope", pts, 0.018, pal["velvet"], verts=10)
    for s in (-1, 1):
        cylinder("RopeEnd", 0.022, 0.05, (s * (gap / 2 - 0.06), 0, z), pal["chrome"], axis="X", verts=12)
    _export("props", name, label, "stanchion", {"post_spacing_m": gap})


# ---------------------------------------------------------------------------
# Backstage
# ---------------------------------------------------------------------------

def _road_case_body(w, d, h, z0, pal, lid=0.8):
    """Laminated box with aluminium edge extrusion, ball corners, latches, dish handles."""
    gnkit.bevel(box("Case", (w, d, h), (0, 0, z0), pal["case"]), 0.004)
    e = 0.022
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("EdgeV", (e, e, h), (sx * (w / 2 - e / 2 + 0.002), sy * (d / 2 - e / 2 + 0.002), z0), pal["alu"])
    for z in (z0, z0 + h - e, z0 + h * lid):
        for sy in (-1, 1):
            box("EdgeX", (w, e, e), (0, sy * (d / 2 - e / 2 + 0.002), z), pal["alu"])
        for sx in (-1, 1):
            box("EdgeY", (e, d, e), (sx * (w / 2 - e / 2 + 0.002), 0, z), pal["alu"])
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z in (z0 + 0.012, z0 + h - 0.012):
                sphere("BallCorner", 0.024, (sx * w / 2, sy * d / 2, z), pal["metal"], segments=8)
    for sy in (-1, 1):
        for sx in (-1, 1):
            box("Latch", (0.07, 0.012, 0.05), (sx * w * 0.28, sy * (d / 2 + 0.006), z0 + h * lid - 0.025), pal["metal"])
    for sx in (-1, 1):
        box("Handle", (0.012, 0.13, 0.07), (sx * (w / 2 + 0.004), 0, z0 + h * 0.55), pal["metal"])


def road_case(name, label, w, d, h, castors=True):
    gnkit.reset()
    pal = _mats()
    z0 = 0.115 if castors else 0.012
    if castors:
        _castors(w, d, pal)
    else:
        for sx in (-1, 1):
            for sy in (-1, 1):
                box("Foot", (0.05, 0.05, 0.012), (sx * (w / 2 - 0.05), sy * (d / 2 - 0.05), 0), pal["rubber"])
    _road_case_body(w, d, h, z0, pal)
    _export("props", name, label, "road_case", {"size_m": [w, d, round(h + z0, 3)]})


def cable_trunk(name, label):
    """A big cable trunk on castors, with a yellow stripe so it is found in the dark."""
    gnkit.reset()
    pal = _mats()
    w, d, h = 1.2, 0.6, 0.62
    _castors(w, d, pal)
    _road_case_body(w, d, h, 0.115, pal, lid=0.85)
    for sy in (-1, 1):
        box("Stripe", (w - 0.06, 0.004, 0.06), (0, sy * (d / 2 + 0.002), 0.115 + h * 0.35), pal["yellow"])
    _export("props", name, label, "cable_trunk", {"size_m": [w, d, h + 0.115]})


def cable_ramp(name, label, channels=5):
    """A five-channel cable protector section. Cables run along X; people
    and forklifts cross along Y. Black ramps, yellow hinged lid."""
    gnkit.reset()
    pal = _mats()
    length, width, h = 0.9, 0.52, 0.075
    base = gnkit.prism("Base", [(-width / 2, 0), (width / 2, 0), (0.14, h), (-0.14, h)], length, pal["rubber"])
    gnkit.bevel(base, 0.004)
    box("Lid", (length, 0.26, 0.008), (0, 0, h), pal["yellow"])
    for k in range(channels + 1):
        y = -0.13 + k * 0.26 / channels
        box("LidGroove", (length, 0.004, 0.003), (0, y, h + 0.008), pal["rubber"])
    for k in range(9):
        x = -length / 2 + 0.05 + k * 0.1
        for s in (-1, 1):
            gnkit.prism("Tread", [(s * 0.2, 0.024), (s * 0.19, 0.028), (s * 0.15, 0.064), (s * 0.16, 0.06)],
                        0.03, pal["rubber"], x=x)
    box("Connector", (0.03, 0.1, 0.05), (length / 2 + 0.015, 0.16, 0), pal["rubber"])
    _export("props", name, label, "cable_ramp", {"length_m": length, "channels": channels})


# ---------------------------------------------------------------------------
# Venue
# ---------------------------------------------------------------------------

def gazebo(name, label, size=3.0):
    """A pop-up gazebo: four legs, scissor frame, a pyramid canopy and valance."""
    gnkit.reset()
    pal = _mats()
    half, eave, peak = size / 2, 2.05, 3.0
    corners = [(-half, -half), (half, -half), (half, half), (-half, half)]
    for x, y in corners:
        box("Leg", (0.04, 0.04, eave), (x * 0.98, y * 0.98, 0), pal["alu"])
        box("FootPlate", (0.14, 0.14, 0.008), (x * 0.98, y * 0.98, 0), pal["dark_metal"])
    for i in range(4):
        (ax, ay), (bx, by) = corners[i], corners[(i + 1) % 4]
        a, b = (ax * 0.98, ay * 0.98), (bx * 0.98, by * 0.98)
        m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        for p, q in ((a, m), (m, b)):
            tube("Scissor", [(p[0], p[1], eave - 0.3), (q[0], q[1], eave)], 0.012, pal["alu"])
            tube("Scissor", [(p[0], p[1], eave), (q[0], q[1], eave - 0.3)], 0.012, pal["alu"])
        tube("Eave", [(a[0], a[1], eave), (b[0], b[1], eave)], 0.012, pal["alu"])
    for x, y in corners:
        tube("Rafter", [(x * 0.98, y * 0.98, eave), (0, 0, peak - 0.05)], 0.012, pal["alu"])
    canopy = _sheet("Canopy", [(x, y, eave + 0.05) for x, y in corners] + [(0, 0, peak)],
                    [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], pal["white_fabric"])
    _solidify(canopy, 0.01)
    for i in range(4):
        (ax, ay), (bx, by) = corners[i], corners[(i + 1) % 4]
        if ax == bx:
            box("Valance", (0.01, size, 0.25), (ax, 0, eave - 0.2), pal["white_fabric"])
        else:
            box("Valance", (size, 0.01, 0.25), (0, ay, eave - 0.2), pal["white_fabric"])
    _export("props", name, label, "gazebo", {"size_m": [size, size], "eave_height_m": eave, "peak_height_m": peak})


def _chain(x, y, z_bottom, z_top, pal, pitch=0.03):
    """Real links, alternating planes, from z_bottom up to z_top."""
    n = int((z_top - z_bottom) / pitch)
    for k in range(n):
        z = z_bottom + (k + 0.5) * pitch
        # Shaped at the origin and moved last: transform_apply also bakes in
        # the location, and a stretch applied after that would scale from the
        # world origin instead of the link's centre.
        bpy.ops.mesh.primitive_torus_add(major_radius=0.011, minor_radius=0.0035, major_segments=10,
                                         minor_segments=5, rotation=(math.pi / 2, 0, (k % 2) * math.pi / 2))
        link = bpy.context.active_object
        link.scale = (1, 1, 1.5)
        bpy.ops.object.transform_apply(rotation=True, scale=True)
        link.location = (x, y, z)
        link.data.materials.append(pal["dark_metal"])
    return n


def _hook(z, pal, down=True):
    """A forged hook with its safety latch: opening down (load hook) or up (suspension)."""
    s = -1 if down else 1
    pts = [(0, 0, z)]
    for k in range(10):
        a = math.pi * k / 9
        pts.append((0.035 - 0.035 * math.cos(a), 0, z + s * (0.06 + 0.035 * math.sin(a))))
    tube("Hook", pts, 0.009, pal["metal"])
    tube("Latch", [(0, 0, z + s * 0.03), (0.07, 0, z + s * 0.06)], 0.003, pal["metal"])
    cylinder("Swivel", 0.02, 0.04, (0, 0, z - s * 0.02), pal["metal"], verts=12)


def chain_hoist(name, label, chain=1.85):
    """A one-tonne electric chain hoist as rigged: suspension hook up top,
    body, the load chain running down to the load hook, and the chain bag."""
    gnkit.reset()
    pal = _mats()
    hoist_blue = gnkit.material("Hoist blue", (0.05, 0.12, 0.35), 0.5)
    _hook(0.14, pal, down=True)
    links = _chain(0, 0, 0.16, 0.16 + chain, pal)
    zb = 0.16 + chain
    gnkit.bevel(box("Body", (0.26, 0.24, 0.34), (0, 0, zb), hoist_blue), 0.02)
    cylinder("Motor", 0.1, 0.22, (0.24, 0, zb + 0.2), hoist_blue, axis="X", verts=20)
    cylinder("Brake", 0.08, 0.08, (0.39, 0, zb + 0.2), pal["dark_metal"], axis="X", verts=20)
    cylinder("Gearbox", 0.09, 0.08, (-0.17, 0, zb + 0.2), hoist_blue, axis="X", verts=20)
    box("Plate", (0.2, 0.004, 0.08), (0, 0.122, zb + 0.08), pal["alu"])
    cylinder("Handle", 0.012, 0.3, (0, 0, zb + 0.36), pal["dark_metal"], axis="X", verts=8)
    _hook(zb + 0.42, pal, down=False)
    cylinder("ChainBag", 0.1, 0.36, (-0.02, -0.2, zb - 0.1), pal["fabric"], verts=16)
    tube("BagStrap", [(-0.02, -0.12, zb + 0.06), (-0.02, -0.2, zb + 0.08)], 0.01, pal["fabric"])
    _export("props", name, label, "chain_hoist", {"capacity_kg": 1000, "chain_m": chain, "links": links})


def windup_stand(name, label, tbar=False):
    """A wind-up lighting stand, fully extended, on its tripod base."""
    gnkit.reset()
    pal = _mats()
    top = 4.2
    box("Sleeve", (0.09, 0.09, 1.3), (0, 0, 0.3), pal["dark_metal"])
    box("Mast2", (0.07, 0.07, 1.4), (0, 0, 1.55), pal["alu"])
    box("Mast3", (0.055, 0.055, 1.4), (0, 0, 2.85), pal["alu"])
    box("Mast4", (0.042, 0.042, top - 4.2 + 0.05 + 1.1), (0, 0, top - 1.1), pal["alu"])
    for z in (1.6, 2.9):
        box("Collar", (0.1, 0.1, 0.05), (0, 0, z - 0.05), pal["dark_metal"])
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 2
        foot = (math.cos(a) * 1.0, math.sin(a) * 1.0, 0.04)
        tube("Leg", [(0, 0, 0.55), foot], 0.022, pal["dark_metal"])
        tube("Brace", [(0, 0, 0.32), (foot[0] * 0.55, foot[1] * 0.55, 0.3)], 0.014, pal["dark_metal"])
        cylinder("Jack", 0.03, 0.04, (foot[0], foot[1], 0.02), pal["rubber"], verts=10)
    box("Winch", (0.12, 0.14, 0.18), (0.1, 0, 0.9), pal["dark_metal"])
    tube("Crank", [(0.16, 0, 0.99), (0.22, 0, 0.99), (0.22, 0.12, 0.99), (0.22, 0.12, 1.05)], 0.008, pal["dark_metal"])
    if tbar:
        cylinder("TBar", 0.025, 1.5, (0, 0, top + 0.03), pal["dark_metal"], axis="X", verts=12)
        box("TBarClamp", (0.08, 0.08, 0.1), (0, 0, top - 0.05), pal["dark_metal"])
        for x in (-0.6, -0.2, 0.2, 0.6):
            cylinder("Spigot", 0.014, 0.1, (x, 0, top + 0.1), pal["metal"], verts=10)
    else:
        cylinder("Spigot", 0.014, 0.1, (0, 0, top + 0.05), pal["metal"], verts=10)
    _export("props", name, label, "lighting_stand", {"max_height_m": top, "t_bar": tbar})


def truss_base_plate(name, label):
    """A steel base plate with fork couplers for 290 mm box truss."""
    gnkit.reset()
    pal = _mats()
    box("Plate", (0.8, 0.8, 0.012), (0, 0, 0), pal["dark_metal"])
    box("Boss", (0.34, 0.34, 0.04), (0, 0, 0.012), pal["dark_metal"])
    for x in (-0.145, 0.145):
        for y in (-0.145, 0.145):
            cylinder("Receiver", 0.032, 0.1, (x, y, 0.1), pal["alu"], verts=16, radius2=0.025)
            cylinder("Pin", 0.006, 0.08, (x, y, 0.12), pal["metal"], axis="X", verts=8)
    for x in (-0.36, 0.36):
        for y in (-0.36, 0.36):
            cylinder("Leveller", 0.012, 0.04, (x, y, 0.02), pal["metal"], verts=8)
    _export("props", name, label, "truss_base", {"truss": "290 box", "size_m": [0.8, 0.8]})


def portable_toilet(name, label):
    gnkit.reset()
    pal = _mats()
    w, d, h = 1.1, 1.2, 2.2
    box("Skid", (w + 0.04, d + 0.04, 0.1), (0, 0, 0), pal["paint"])
    gnkit.bevel(box("Body", (w, d, h), (0, 0, 0.1), pal["loo"]), 0.02)
    roof = cylinder("Roof", 0.83, 0.18, (0, 0, h + 0.19), pal["loo_roof"], verts=4, radius2=0.55)
    roof.rotation_euler = (0, 0, math.pi / 4)
    bpy.ops.object.transform_apply(rotation=True)
    gnkit.bevel(box("Door", (0.74, 0.03, 1.95), (0, d / 2, 0.2), pal["loo"]), 0.01)
    box("DoorHandle", (0.03, 0.04, 0.15), (0.3, d / 2 + 0.03, 1.0), pal["dark_metal"])
    box("Indicator", (0.1, 0.01, 0.03), (0.3, d / 2 + 0.035, 1.25), pal["led_green"])
    for s in (-1, 1):
        gnkit.grid("Vent", 1, 5, (0.4, 0.015), 0.02, (-0.2, s * (d / 2 + 0.002), h - 0.2), pal["paint"], 0.004, axis="Y")
        box("Stack", (0.08, 0.08, 0.3), (0.4 * s, -d / 2 + 0.08, h + 0.05), pal["loo"])
    _export("props", name, label, "toilet", {"size_m": [w, d, h + 0.28]})


def ticket_booth(name, label):
    """A box office kiosk: serving window and counter at +Y, awning, lit sign."""
    gnkit.reset()
    pal = _mats()
    w, d, h = 1.6, 1.4, 2.3
    gnkit.bevel(box("Walls", (w, d, h), (0, 0, 0), pal["booth"]), 0.01)
    box("Window", (1.2, 0.01, 0.8), (0, d / 2 + 0.002, 1.05), pal["window"])
    box("WindowFrame", (1.26, 0.02, 0.04), (0, d / 2 + 0.005, 1.85), pal["dark_metal"])
    box("Counter", (1.3, 0.3, 0.04), (0, d / 2 + 0.15, 1.02), pal["counter"])
    for s in (-1, 1):
        box("Bracket", (0.03, 0.25, 0.12), (s * 0.55, d / 2 + 0.125, 0.9), pal["dark_metal"])
    box("Roof", (w + 0.3, d + 0.3, 0.1), (0, 0, h), pal["dark_metal"])
    gnkit.prism("Awning", [(d / 2, 2.0), (d / 2, 2.22), (d / 2 + 0.6, 1.95), (d / 2 + 0.6, 1.85)], w + 0.1, pal["awning"])
    box("Sign", (1.3, 0.06, 0.32), (0, d / 2 - 0.05, h + 0.1), pal["dark_metal"])
    box("SignFace", (1.24, 0.01, 0.26), (0, d / 2 - 0.015, h + 0.13), pal["lens_lit"])
    box("Door", (0.02, 0.8, 2.0), (-w / 2 - 0.01, 0, 0.02), pal["dark_metal"])
    _export("props", name, label, "booth", {"size_m": [w, d, h]})


def stretch_tent(name, label, length=15.0, width=10.0):
    """A tensile stretch tent. The fabric is solved, not sculpted: a grid is
    relaxed towards a minimal surface held up by two king poles and pulled
    to the edge ties (poles lift some sides open, pegs pull others low)."""
    gnkit.reset()
    pal = _mats()
    nx, ny = 61, 41
    xs = np.linspace(-length / 2, length / 2, nx)
    ys = np.linspace(-width / 2, width / 2, ny)
    X, Y = np.meshgrid(xs, ys)
    Z = np.zeros((ny, nx))
    fixed = np.zeros((ny, nx), bool)

    masts = [(-length * 0.23, 0.0, 5.5), (length * 0.23, 0.0, 5.5)]
    for mx, my, mh in masts:
        disc = (X - mx) ** 2 + (Y - my) ** 2 < 0.35 ** 2
        Z[disc], fixed[disc] = mh, True

    # The edge, walked round in order, and the ties along it: poles at 2.6 m
    # open the front, a pole each end, pegs everywhere else.
    ring = ([(0, i) for i in range(nx)] + [(j, nx - 1) for j in range(1, ny)] +
            [(ny - 1, i) for i in range(nx - 2, -1, -1)] + [(j, 0) for j in range(ny - 2, 0, -1)])
    hw, hl = width / 2, length / 2
    ties = [(-hl, -hw, 0.3), (-5, -hw, 0.5), (0, -hw, 2.2), (5, -hw, 0.5), (hl, -hw, 0.3),
            (hl, 0, 2.4), (hl, hw, 0.3), (5, hw, 2.6), (0, hw, 2.6), (-5, hw, 2.6), (-hl, hw, 0.3),
            (-hl, 0, 2.4)]

    def ring_index(x, y):
        return min(range(len(ring)), key=lambda k: (xs[ring[k][1]] - x) ** 2 + (ys[ring[k][0]] - y) ** 2)

    tie_at = sorted((ring_index(x, y), h, (x, y)) for x, y, h in ties)
    for n, (k0, h0, _) in enumerate(tie_at):
        k1, h1, _ = tie_at[(n + 1) % len(tie_at)]
        span = (k1 - k0) % len(ring)
        for step in range(span + 1):
            t = step / span
            j, i = ring[(k0 + step) % len(ring)]
            # Between ties the free edge lifts in a shallow arc, as tensioned fabric does.
            lift = 0.06 * span * 0.25 * math.sin(math.pi * t)
            Z[j, i] = h0 + (h1 - h0) * (0.5 - 0.5 * math.cos(math.pi * t)) + lift
            fixed[j, i] = True

    free = ~fixed
    for _ in range(6000):
        avg = 0.25 * (np.roll(Z, 1, 0) + np.roll(Z, -1, 0) + np.roll(Z, 1, 1) + np.roll(Z, -1, 1))
        Z[free] = avg[free]

    verts = [(float(X[j, i]), float(Y[j, i]), float(Z[j, i])) for j in range(ny) for i in range(nx)]
    faces = [(j * nx + i, j * nx + i + 1, (j + 1) * nx + i + 1, (j + 1) * nx + i)
             for j in range(ny - 1) for i in range(nx - 1)]
    fabric = _sheet("Fabric", verts, faces, pal["tent"])
    _solidify(fabric, 0.02)
    gnkit.smooth(fabric, 60)

    for mx, my, mh in masts:
        cylinder("KingPole", 0.07, mh, (mx, my, mh / 2), pal["alu"], verts=16)
        box("PoleFoot", (0.3, 0.3, 0.02), (mx, my, 0), pal["dark_metal"])
    for x, y, h in ties:
        out = (x / hl if abs(x) == hl else 0, y / hw if abs(y) == hw else 0)
        if h > 1.0:
            cylinder("EdgePole", 0.04, h, (x, y, h / 2), pal["alu"], verts=12)
            peg = (x + out[0] * 1.8, y + out[1] * 1.8, 0.0)
            tube("GuyRope", [(x, y, h), peg], 0.006, pal["rope"], verts=6)
        else:
            peg = (x + out[0] * 0.8, y + out[1] * 0.8, 0.0)
            tube("Strap", [(x, y, h), peg], 0.01, pal["yellow"], verts=6)
        cylinder("Peg", 0.012, 0.12, (peg[0], peg[1], 0.06), pal["metal"], verts=6)
    _export("props", name, label, "tent", {"size_m": [length, width], "king_pole_m": 5.5})


def feather_flag(name, label):
    """A feather flag: bent pole, printed sail, cross base with a water weight."""
    gnkit.reset()
    pal = _mats()
    bend, r, rise = 2.5, 0.9, 70
    pole = [(0, 0, 0.05), (0, 0, bend)]
    for k in range(1, 9):
        a = math.radians(rise * k / 8)
        pole.append((r - r * math.cos(a), 0, bend + r * math.sin(a)))
    tube("Pole", pole, 0.012, pal["dark_metal"], verts=8)
    outline = ([(0, 0.8)] + [(p[0], p[2]) for p in pole[1:]] +
               [(0.66, 3.0), (0.72, 2.4), (0.7, 1.7), (0.6, 1.15), (0.35, 0.86)])
    sail = _sheet("Sail", [(x, 0.015, z) for x, z in outline], [tuple(range(len(outline)))], pal["flag"])
    bpy.context.view_layer.objects.active = sail
    bm = bmesh.new()
    bm.from_mesh(sail.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(sail.data)
    bm.free()
    _solidify(sail, 0.004)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        tube("BaseLeg", [(0, 0, 0.05), (0.45 * math.cos(a), 0.45 * math.sin(a), 0.01)], 0.012, pal["dark_metal"])
    cylinder("WaterWeight", 0.25, 0.1, (0, 0, 0.05), pal["fabric"], verts=24)
    _export("props", name, label, "flag", {"height_m": round(pole[-1][2], 2)})


def main():
    # Seating.
    banquet_chair("chair_banquet", "Banquet chair")
    chiavari_chair("chair_chiavari", "Chiavari chair")
    stacking_chair("chair_stacking", "Stacking conference chair")
    theatre_seats("theatre_seats_pair", "Theatre seats, pair")
    bar_stool("bar_stool", "Bar stool")
    lounge_sofa("sofa_lounge", "Lounge sofa, three-seat")
    ottoman("ottoman", "Ottoman")
    # Tables.
    round_table("table_round_5ft", "5 ft round banquet table, clothed", 1.52)
    round_table("table_round_6ft", "6 ft round banquet table, clothed", 1.83)
    cocktail_table("table_cocktail", "Cocktail table with stretch cover")
    trestle_table("table_trestle_6ft", "6 ft trestle table, clothed")
    bar_counter("bar_counter", "Bar counter, 2 m")
    # Crowd control.
    crowd_barrier("barrier_crowd", "Mojito crowd barrier")
    bike_rack("barrier_bike_rack", "Bike-rack barrier")
    stanchions("stanchion_rope", "Stanchion posts with velvet rope")
    # Backstage.
    road_case("road_case_small", "Road case, small", 0.6, 0.45, 0.45, castors=False)
    road_case("road_case_medium", "Road case, medium", 0.8, 0.6, 0.7)
    road_case("road_case_large", "Road case, large (work box)", 1.2, 0.75, 1.0)
    cable_trunk("cable_trunk", "Cable trunk")
    cable_ramp("cable_ramp", "Yellow Blazer cable ramp")
    # Venue.
    gazebo("gazebo_3x3", "Pop-up gazebo 3 × 3 m")
    chain_hoist("chain_hoist_1t", "One-tonne chain hoist")
    windup_stand("lighting_stand_windup", "Wind-up lighting stand")
    windup_stand("lighting_stand_windup_tbar", "Wind-up lighting stand with T-bar", tbar=True)
    truss_base_plate("truss_base_plate", "Truss base plate")
    portable_toilet("portable_toilet", "Portable toilet")
    ticket_booth("ticket_booth", "Ticket booth")
    stretch_tent("stretch_tent_10x15", "Stretch tent 10 × 15 m")
    feather_flag("flag_feather", "Feather flag banner")


main()
