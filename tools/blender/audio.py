"""Sound reinforcement kit: line array elements, subs, tops, wedges, stands,
amp racks.

Every model is sized like the class of product it stands for, and named
after it the way a nickname would be: close enough to recognise, never a
real brand or model number. Line array elements are single boxes; the
LineArray node in Godot hangs them in a column with the splay you give it.

    blender --background --factory-startup --python tools/blender/audio.py
"""

import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import gnkit  # noqa: E402
from gnkit import box, cylinder, prism, tube  # noqa: E402

SCRIPT = "audio.py"
CATEGORY = "audio"


def _grille_on(p1, p2, width, mat, margin=0.012, thick=0.012):
    """A grille slab over the cabinet face between side-profile points p1 and
    p2 (y, z), proud of it by `thick`."""
    a, b = Vector(p1), Vector(p2)
    along = (b - a).normalized()
    n = Vector((along.y, -along.x))  # outward, for a profile walked clockwise
    a, b = a + along * margin, b - along * margin
    pts = [a, b, b + n * thick, a + n * thick]
    return prism("Grille", [tuple(p) for p in pts], width - 2 * margin, mat)


def _handles(w, h, d, pal, z=None):
    z = h * 0.6 if z is None else z
    for s in (-1, 1):
        tube("Handle", [(s * (w / 2 + 0.001), -d * 0.2, z), (s * (w / 2 + 0.03), -d * 0.15, z),
                        (s * (w / 2 + 0.03), d * 0.05, z), (s * (w / 2 + 0.001), d * 0.1, z)], 0.008, pal["dark_metal"])


def _front(w, h, y, z0, pal, panels=1, border=0.022, horn=False):
    """A speaker front: a bezel frame proud of the cabinet, the perforated
    grille set just behind it, split into panels by thin bars, and the
    waveguide showing through as a darker slot."""
    gnkit.frame("Bezel", w, h, (0, y, z0), 0.012, border, pal["paint"])
    gw, gh = w - 2 * border, h - 2 * border
    box("Grille", (gw, 0.006, gh), (0, y - 0.004, z0 + border), pal["grille"])
    for k in range(1, panels):
        x = -gw / 2 + gw * k / panels
        box("GrilleBar", (0.012, 0.01, gh), (x, y - 0.002, z0 + border), pal["paint"])
    if horn:
        box("Waveguide", (gw * 0.07, 0.004, gh * 0.96), (0, y - 0.007, z0 + border + gh * 0.02), pal["plastic"])
    # A blank badge plate where the maker's name would be.
    box("Badge", (min(0.09, w * 0.18), 0.004, min(0.022, border * 0.8)),
        (w / 2 - border - min(0.07, w * 0.14), y + 0.012, z0 + border * 0.1), pal["metal"])


def _rigging(w, hf, hb, d, lift, pal):
    """Line array rigging: a steel link plate at each front corner with its
    pin, and at the back an angle bar with a row of splay holes."""
    for s in (-1, 1):
        x = s * (w / 2 + 0.005)
        box("FrontLink", (0.01, 0.07, hf + 0.03), (x, d / 2 - 0.05, -0.015), pal["dark_metal"])
        for z in (0.03, hf - 0.03):
            cylinder("FrontPin", 0.009, 0.034, (x + s * 0.01, d / 2 - 0.015, z), pal["metal"], axis="X", verts=12)
            cylinder("PinRing", 0.016, 0.006, (x + s * 0.028, d / 2 - 0.015, z), pal["metal"], axis="X", verts=12)
        box("RearBar", (0.012, 0.16, hb * 0.6), (x, -d / 2 + 0.03, lift + hb * 0.2), pal["dark_metal"])
        for k in range(6):
            cylinder("SplayHole", 0.006, 0.016, (x + s * 0.004, -d / 2 + 0.06 + k * 0.022, lift + hb * 0.5), pal["plastic"],
                     axis="X", verts=10)
        cylinder("RearPin", 0.009, 0.034, (x + s * 0.01, -d / 2 + 0.08, lift + hb * 0.35), pal["metal"], axis="X", verts=12)


def _connectors(w, y, z, pal, count=2):
    """A rear connector plate with round speaker connectors."""
    box("ConnectorPlate", (0.16, 0.006, 0.08), (w * 0.25, y, z), pal["dark_metal"])
    for k in range(count):
        cylinder("Connector", 0.017, 0.02, (w * 0.25 - 0.035 + k * 0.07, y - 0.008, z + 0.04), pal["plastic"],
                 axis="Y", verts=16)
        cylinder("ConnectorRing", 0.021, 0.008, (w * 0.25 - 0.035 + k * 0.07, y - 0.004, z + 0.04), pal["metal"],
                 axis="Y", verts=16)


def line_element(name, w, hf, hb, d, label, horn=True):
    """A trapezoidal line array box: taller at the front than the back, so the
    boxes can splay; a bezelled grille in front, rigging down both sides,
    recessed handles, connectors at the back."""
    gnkit.reset()
    pal = gnkit.palette()
    lift = (hf - hb) / 2
    profile = [(d / 2, 0), (d / 2, hf), (-d / 2, hf - lift), (-d / 2, lift)]
    gnkit.bevel(prism("Cabinet", profile, w, pal["paint"]), 0.01, 3)
    _front(w, hf, d / 2 + 0.012, 0.0, pal, panels=3 if w > 1.0 else 2, border=min(0.025, hf * 0.08), horn=horn)
    _rigging(w, hf, hb, d, lift, pal)
    for s in (-1, 1):
        gnkit.side_handle(s * w / 2, -d * 0.12, hf * 0.3, d * 0.3, hf * 0.4, s, pal["plastic"], pal["dark_metal"])
    _connectors(w, -d / 2 - 0.003, lift + hb * 0.3, pal)
    gnkit.join_all(name)
    gnkit.export(CATEGORY, name, SCRIPT, {"label": label, "kind": "line_array_element",
                                          "front_height_m": hf, "back_height_m": hb, "depth_m": d})


def bumper(name, w, d, label):
    """The flying frame a line array hangs from."""
    gnkit.reset()
    pal = gnkit.palette()
    for s in (-1, 1):
        box("Rail", (0.05, d + 0.3, 0.08), (s * (w / 2 - 0.025), -0.05, 0), pal["dark_metal"])
    for y in (-d / 2 - 0.1, 0.0, d / 2):
        box("Cross", (w, 0.05, 0.06), (0, y, 0.01), pal["dark_metal"])
    for k in range(6):
        y = -d / 2 - 0.15 + k * (d + 0.2) / 5
        cylinder("PickupHole", 0.012, 0.09, (0, y, 0.06), pal["metal"], verts=8)
    box("Pickup", (0.04, d + 0.2, 0.1), (0, -0.05, 0.06), pal["dark_metal"])
    gnkit.join_all(name)
    gnkit.export(CATEGORY, name, SCRIPT, {"label": label, "kind": "bumper"})


def sub(name, w, h, d, label, drivers=2, cardioid=False):
    gnkit.reset()
    pal = gnkit.palette()
    gnkit.bevel(box("Cabinet", (w, d, h), (0, 0, 0.025), pal["paint"]), 0.014, 3)
    _front(w, h, d / 2 + 0.012, 0.025, pal, panels=drivers if drivers > 1 else 1)
    if cardioid:
        _front(w * 0.55, h * 0.8, -d / 2 - 0.004, 0.025 + h * 0.1, pal)
    # Skids underneath, the way subs sit on stage, and castor pockets.
    for s in (-1, 1):
        box("Skid", (0.07, d - 0.06, 0.025), (s * (w / 2 - 0.07), 0, 0), pal["rubber"])
        for y in (-1, 1):
            gnkit.side_handle(s * w / 2, y * d * 0.22, h * 0.45, d * 0.24, h * 0.3, s, pal["plastic"], pal["dark_metal"])
        box("SideRigging", (0.01, 0.08, h * 0.9), (s * (w / 2 + 0.004), d / 2 - 0.07, 0.03 + h * 0.05), pal["dark_metal"])
    _connectors(w, -d / 2 - 0.003, h * 0.7, pal)
    gnkit.join_all(name)
    gnkit.export(CATEGORY, name, SCRIPT, {"label": label, "kind": "subwoofer", "drivers": drivers})


def top(name, w, h, d, label, taper=0.7, pole=True):
    """A point-source top: a trapezoid seen from above, grille on the front."""
    gnkit.reset()
    pal = gnkit.palette()
    import bmesh
    import bpy
    bm = bmesh.new()
    front, back = w / 2, w / 2 * taper
    pts = [(-front, d / 2), (front, d / 2), (back, -d / 2), (-back, -d / 2)]
    lower = [bm.verts.new((x, y, 0)) for x, y in pts]
    upper = [bm.verts.new((x, y, h)) for x, y in pts]
    bm.faces.new(lower[::-1])
    bm.faces.new(upper)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    data = bpy.data.meshes.new("Cabinet")
    bm.to_mesh(data)
    bm.free()
    cab = bpy.data.objects.new("Cabinet", data)
    bpy.context.collection.objects.link(cab)
    cab.data.materials.append(pal["paint"])
    gnkit.bevel(cab, 0.022, 4)
    _front(w - 0.01, h - 0.01, d / 2 + 0.006, 0.005, pal, border=0.02)
    # A recessed top handle and fly points.
    box("HandlePocket", (0.2, 0.07, 0.004), (0, -d * 0.1, h - 0.002), pal["plastic"])
    tube("Handle", [(-0.08, -d * 0.1, h), (-0.06, -d * 0.1, h + 0.025), (0.06, -d * 0.1, h + 0.025), (0.08, -d * 0.1, h)],
         0.011, pal["dark_metal"])
    for x in (-w * 0.3, w * 0.3):
        cylinder("FlyPoint", 0.012, 0.01, (x, -d * 0.3, h + 0.003), pal["metal"], verts=12)
    for sd in (-1, 1):
        gnkit.side_handle(sd * (w / 2 + (w / 2 * taper - w / 2) * 0.5), -d * 0.05, h * 0.55, d * 0.35, h * 0.2, sd,
                          pal["plastic"], pal["dark_metal"])
    _connectors(w * 0.5 * taper, -d / 2 - 0.003, h * 0.2, pal)
    if pole:
        cylinder("PoleCup", 0.024, 0.08, (0, 0, 0.04), pal["dark_metal"], verts=16)
    for x in (-w * 0.35, w * 0.35):
        for y in (-d * 0.35, d * 0.35):
            cylinder("Foot", 0.018, 0.008, (x, y, 0.0), pal["rubber"], verts=12)
    gnkit.join_all(name)
    gnkit.export(CATEGORY, name, SCRIPT, {"label": label, "kind": "point_source"})


def wedge(name, w, label, low=0.14, high=0.4, d=0.5):
    """A floor monitor: its face tilted up at the performer (who stands at +Y)."""
    gnkit.reset()
    pal = gnkit.palette()
    profile = [(d / 2, 0), (d / 2, low), (-d / 2 + 0.08, high), (-d / 2, high), (-d / 2, 0)]
    gnkit.bevel(prism("Cabinet", profile, w, pal["paint"]), 0.014, 3)
    _grille_on((d / 2, low), (-d / 2 + 0.08, high), w, pal["grille"], margin=0.02, thick=0.008)
    for s in (-1, 1):
        box("Foot", (0.05, d - 0.08, 0.012), (s * (w / 2 - 0.07), 0, -0.012), pal["rubber"])
        gnkit.side_handle(s * w / 2, -d * 0.18, high * 0.3, d * 0.3, high * 0.4, s, pal["plastic"], pal["dark_metal"])
    _connectors(w, -d / 2 - 0.003, high * 0.3, pal)
    gnkit.join_all(name)
    gnkit.export(CATEGORY, name, SCRIPT, {"label": label, "kind": "monitor"})


def tripod(name, height, label, with_top=None):
    """A speaker stand, optionally with a top on it."""
    gnkit.reset()
    pal = gnkit.palette()
    hub = 0.62
    cylinder("Tube", 0.019, hub + 0.05, (0, 0, (hub + 0.05) / 2 + 0.05), pal["dark_metal"], verts=12)
    cylinder("Mast", 0.0175, height - hub, (0, 0, hub + (height - hub) / 2), pal["dark_metal"], verts=12)
    cylinder("Clamp", 0.028, 0.05, (0, 0, hub + 0.05), pal["plastic"], verts=12)
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 2
        foot = (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.0)
        tube("Leg", [(0, 0, hub - 0.05), foot], 0.013, pal["dark_metal"])
        cylinder("FootCap", 0.02, 0.02, (foot[0], foot[1], 0.01), pal["rubber"], verts=8)
        mid = (math.cos(a) * 0.25, math.sin(a) * 0.25, hub - 0.3)
        tube("Brace", [(0, 0, 0.2), mid], 0.007, pal["dark_metal"])
    if with_top:
        w, h, d = with_top
        gnkit.bevel(box("Cabinet", (w, d, h), (0, 0, height), pal["paint"]), 0.01)
        box("Grille", (w - 0.03, 0.012, h - 0.03), (0, d / 2, height + 0.015), pal["grille"])
    gnkit.join_all(name)
    gnkit.export(CATEGORY, name, SCRIPT, {"label": label, "kind": "stand"})


def amp_rack(name, label, units=3):
    """A touring amp rack: a road case, lid off, amplifiers glowing."""
    gnkit.reset()
    pal = gnkit.palette()
    w, d, h = 0.62, 0.75, 0.2 + units * 0.2
    gnkit.bevel(box("Case", (w, d, h), (0, 0, 0.12), pal["case"]), 0.006)
    for s in (-1, 1):
        for y in (-1, 1):
            box("Corner", (0.05, 0.05, 0.05), (s * (w / 2 - 0.02), y * (d / 2 - 0.02), h + 0.12 - 0.05), pal["metal"])
            cylinder("Castor", 0.05, 0.035, (s * (w / 2 - 0.08), y * (d / 2 - 0.08), 0.05), pal["rubber"], axis="X", verts=12)
            box("CastorPlate", (0.08, 0.08, 0.02), (s * (w / 2 - 0.08), y * (d / 2 - 0.08), 0.1), pal["metal"])
    for u in range(units):
        z = 0.2 + u * 0.2
        box("AmpFace", (w - 0.06, 0.01, 0.17), (0, d / 2, z), pal["dark_metal"])
        gnkit.picture("AmpScreen", 0.12, 0.06, (-0.14, d / 2 + 0.0105, z + 0.09), gnkit.screen_material("screen_small"), "+Y")
        for k in range(8):
            box("Led", (0.01, 0.004, 0.01), (0.02 + k * 0.022, d / 2 + 0.01, z + 0.11),
                pal["led_green"] if k % 4 else pal["led_blue"])
        gnkit.grid("Vent", 10, 3, (0.018, 0.008), 0.006, (-0.1, d / 2 + 0.006, z + 0.02), pal["plastic"], 0.004, axis="Y")
    gnkit.join_all(name)
    gnkit.export(CATEGORY, name, SCRIPT, {"label": label, "kind": "rack"})


def main():
    # Large format.
    line_element("line_array_kilo2", 1.34, 0.36, 0.3, 0.5, "Kilo-2 large-format line array element")
    line_element("line_array_jay8", 1.12, 0.37, 0.3, 0.52, "Jay-Ate large line array element")
    line_element("line_array_puma", 1.35, 0.4, 0.34, 0.57, "Puma large line array element")
    # Mid and compact.
    line_element("line_array_kora", 0.73, 0.25, 0.2, 0.48, "Kora compact line array element")
    line_element("line_array_why", 0.8, 0.24, 0.19, 0.44, "Why-Series compact line array element")
    line_element("line_array_mini", 0.52, 0.14, 0.12, 0.3, "Mini line array element", horn=False)
    bumper("bumper_large", 1.3, 0.5, "Flying frame for large arrays")
    bumper("bumper_compact", 0.72, 0.46, "Flying frame for compact arrays")
    # Subs.
    sub("sub_kay_ess_29", 1.34, 0.55, 0.92, "Kay-Ess 29 twin-18 subwoofer")
    sub("sub_sl_cardio", 1.2, 0.95, 0.95, "El-Ess cardioid 21-inch subwoofer", drivers=3, cardioid=True)
    sub("sub_single_18", 0.6, 0.72, 0.8, "Single-18 subwoofer", drivers=1)
    # Point source.
    top("top_13xt", 0.4, 0.62, 0.36, "Thirteen-XT coaxial top")
    top("top_ex16", 0.48, 0.72, 0.4, "Ex-16 point source top")
    top("top_qsk_13", 0.38, 0.62, 0.34, "Queue-Ess Kay 13 powered speaker")
    wedge("wedge_ex_16", 0.6, "Ex-16 low-profile wedge")
    wedge("wedge_em_3", 0.72, "Em-3 stage monitor", low=0.16, high=0.44, d=0.56)
    wedge("wedge_compact", 0.45, "Compact wedge", low=0.12, high=0.32, d=0.4)
    tripod("speaker_stand", 1.8, "Speaker stand")
    tripod("pa_on_stand", 1.7, "Powered speaker on a stand", with_top=(0.38, 0.62, 0.34))
    amp_rack("amp_rack", "Touring amp rack (La-Rak style)")


main()
