"""Boats and aircraft for Genesis.

Boats: hulls are swept from real cross-sections (keel, chines, topsides,
sheer) from transom to bow, painted the way boats are (antifouling below the
waterline, a boot stripe, white topsides, a teak deck), and fitted out:
consoles and windscreens, cabins, masts, sails and rigging, engines. Floors,
seats and rails are fitted to the hull's own shape, so nothing pokes through
it. A boat's origin is on its waterline: it floats on Genesis's water at
the water's height, and it can run along a moving-objects path.

Named generically, never a real brand or model.

    blender --background --factory-startup --python tools/blender/craft.py
    (GN_CRAFT=boat_yacht builds the ones whose names start with that)

Aircraft: helicopters (a light one on skids; a heavy lifter on wheels with a
cargo hook, which the flying screen hangs from), a light plane, a camera
drone, hot-air balloons and an airship with screens on its flanks. Fuselages
are lofted and glazed; rotors, wings and gear are built on.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import gnkit  # noqa: E402
from gnkit import box, tube  # noqa: E402

SCRIPT = "craft.py"

# The boot stripe: a band just above the waterline.
STRIPE_LOW, STRIPE_HIGH = -0.03, 0.07


def _export(category, name, label, kind, extra=None):
    gnkit.join_all(name)
    info = {"label": label, "kind": kind}
    info.update(extra or {})
    gnkit.export(category, name, SCRIPT, info)


def _mats():
    pal = gnkit.palette()
    pal.update({
        "hull_white": gnkit.material("Gelcoat white", (0.92, 0.92, 0.9), 0.18),
        "antifoul": gnkit.material("Antifouling", (0.35, 0.06, 0.05), 0.8),
        "antifoul_blue": gnkit.material("Antifouling blue", (0.05, 0.1, 0.25), 0.8),
        "stripe": gnkit.material("Boot stripe", (0.05, 0.12, 0.3), 0.3),
        "teak": gnkit.kit_material("wood_light", "Teak deck"),
        "cushion": gnkit.material("Marine vinyl", (0.9, 0.87, 0.8), 0.45),
        "glass": gnkit.material("Screen glass", (0.03, 0.04, 0.05), 0.03, 0.2, alpha=0.6),
        "dark_glass": gnkit.material("Cabin glass", (0.02, 0.025, 0.03), 0.04, 0.3),
        "sail": gnkit.material("Sailcloth", (0.95, 0.94, 0.9), 0.6),
        "rope": gnkit.material("Rigging", (0.2, 0.2, 0.22), 0.4, 0.8),
        "hypalon": gnkit.material("Hypalon grey", (0.28, 0.29, 0.31), 0.6),
        "wood": gnkit.material("Varnished wood", (0.5, 0.3, 0.14), 0.3),
        "engine": gnkit.material("Engine black", (0.03, 0.03, 0.035), 0.3),
    })
    return pal


# --- hulls ---------------------------------------------------------------------

def _spline(values, t):
    """Catmull-Rom through evenly spaced values, t from 0 to len-1."""
    n = len(values)
    i = min(int(t), n - 2)
    u = t - i
    p0, p1, p2, p3 = values[max(i - 1, 0)], values[i], values[i + 1], values[min(i + 2, n - 1)]
    return 0.5 * (2 * p1 + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3)


def _half_section(w, zs, zc, zk, form):
    """One side of a hull section, (x, z) from the gunwale down to the keel.
    The topsides carry points at the boot stripe's edges so the paint lines
    are crisp. "chine": a hard chine and a V bottom (planing boats);
    "round": a round bilge (sailing and displacement hulls)."""
    span = zs - zc
    # Forward, where the chine rises out of the water, the stripe's edges
    # would fall below it; keep every point between the sheer and the chine.
    z1 = STRIPE_HIGH if zc + 0.02 < STRIPE_HIGH < zs - 0.3 * span else zs - 0.6 * span
    z2 = max(STRIPE_LOW, zc + 0.1 * span)
    if z2 > z1 - 0.005:
        z2 = (z1 + zc) / 2
    top = []
    for z in (zs, (zs + z1) / 2, z1, z2):
        t = (zs - z) / span
        top.append((w * (1.0 - 0.04 * t * t), z))
    if form == "round":
        arc = [(w * math.cos(a), zc + (zk - zc) * math.sin(a)) for a in (math.radians(d) for d in (0, 20, 40, 58, 74, 87))]
        return top + arc + [(0.0, zk)]
    bottom = [(w * 0.96 * (1 - u), zc + (zk - zc) * u ** 0.85) for u in (0.0, 0.25, 0.5, 0.75)]
    return top + bottom + [(0.0, zk)]


class Hull:
    """A hull swept from stations (y, half beam, sheer height, chine height,
    keel depth), transom first, eased between them. Heights are from the
    waterline. Knows its own shape, so fittings can be sized to it."""

    def __init__(self, stations, form="chine", steps=8):
        cols = list(zip(*stations))
        self.sections = []
        n = len(stations)
        for k in range((n - 1) * steps + 1):
            t = k / steps
            # Positions go straight from station to station (eased, uneven
            # spacing would overshoot and fold the hull); the shape is eased.
            i = min(int(t), n - 2)
            y = cols[0][i] + (cols[0][i + 1] - cols[0][i]) * (t - i)
            w, zs, zc, zk = (_spline(c, t) for c in cols[1:])
            self.sections.append((y, _half_section(max(w, 0.004), zs, zc, zk, form)))

    def mesh(self, name, mats, deck=True, double_sided=False):
        """The hull itself, painted: mats has "top", "bottom", and optional
        "stripe" and "deck" materials."""
        rings = []
        for y, half in self.sections:
            ring = [(x, y, z) for x, z in half]
            rings.append(ring + [(-x, y, z) for x, y, z in reversed(ring[:-1])])
        h = gnkit.sweep_sections(name, rings, mats["top"], cap_first=True, close_top=deck)
        order = [mats["top"], mats["bottom"], mats.get("stripe") or mats["top"], mats.get("deck") or mats["top"]]

        def rule(c, n):
            if deck and abs(n.z) > 0.6 and c.z > self.sheer(c.y) - 0.03:
                return 3
            if c.z < STRIPE_LOW + 0.001:
                return 1
            if c.z < STRIPE_HIGH - 0.001:
                return 2
            return 0
        gnkit.material_by_face(h, rule, order)
        if double_sided:
            for m in h.data.materials:
                m.use_backface_culling = False
        return h

    def _x_at(self, half, z):
        if z >= half[0][1]:
            return half[0][0]
        for (x0, z0), (x1, z1) in zip(half, half[1:]):
            if z1 <= z <= z0:
                return x0 + (x1 - x0) * (z0 - z) / max(z0 - z1, 1e-6)
        return 0.0

    def beam(self, y, z):
        """The half beam inside the skin at a point along the boat and a height."""
        secs = self.sections
        if y <= secs[0][0]:
            return self._x_at(secs[0][1], z)
        for (y0, h0), (y1, h1) in zip(secs, secs[1:]):
            if y0 <= y <= y1:
                t = (y - y0) / max(y1 - y0, 1e-6)
                return self._x_at(h0, z) * (1 - t) + self._x_at(h1, z) * t
        return 0.0

    def sheer(self, y):
        secs = self.sections
        for (y0, h0), (y1, h1) in zip(secs, secs[1:]):
            if y0 <= y <= y1:
                t = (y - y0) / max(y1 - y0, 1e-6)
                return h0[0][1] * (1 - t) + h1[0][1] * t
        return secs[0][1][0][1] if y < secs[0][0] else secs[-1][1][0][1]

    def gunwale(self, inset=0.0, lift=0.0, y0=-1e9, y1=1e9, both=True):
        """The sheer line, starboard aft to bow and (both) back down to port."""
        pts = [(half[0][0] - inset, y, half[0][1] + lift) for y, half in self.sections if y0 <= y <= y1]
        pts = [p for p in pts if p[0] > 0.0] or pts[:1]
        if not both:
            return pts
        return pts + [(-x, y, z) for x, y, z in reversed(pts[:-1])]

    def floor(self, name, z, y0, y1, mat, inset=0.03, thick=0.04):
        """A flat floor at height z (its top), filling the hull between y0 and y1."""
        # Forward, the hull rises round the floor; stop where it would poke through.
        side = [(self.beam(y, z) - inset, y) for y in self._ys(y0, y1)]
        side = [(x, y) for x, y in side if x > 0.03]
        return _slab(name, side + [(-x, y) for x, y in reversed(side)], z - thick, z, mat)

    def liner(self, name, y0, y1, z, height, width, mat, side=1, inset=0.03, back=0.0):
        """A seat running along the inside of the hull between y0 and y1,
        following its curve: a bow seat, a side bench. back adds a backrest
        against the hull."""
        outer = [(min(self.beam(y, z), self.beam(y, z + height + back)) - inset, y) for y in self._ys(y0, y1)]
        inner = [(max(x - width, 0.02), y) for x, y in outer]
        plan = [(side * x, y) for x, y in outer + inner[::-1]]
        obj = gnkit.bevel(_slab(name, plan if side > 0 else plan[::-1], z, z + height, mat), min(0.06, height * 0.25), 3)
        if back:
            rim = [(max(x - 0.14, 0.02), y) for x, y in outer]
            plan = [(side * x, y) for x, y in outer + rim[::-1]]
            gnkit.bevel(_slab(name + "Back", plan if side > 0 else plan[::-1], z + height, z + height + back, mat), 0.05, 3)
        return obj

    def _ys(self, y0, y1):
        return [y0] + [y for y, _ in self.sections if y0 < y < y1] + [y1]


def _slab(name, outline, z0, z1, mat):
    """A plan outline (x, y), anticlockwise from above, extruded from z0 to z1."""
    bm = bmesh.new()
    top = [bm.verts.new((x, y, z1)) for x, y in outline]
    bot = [bm.verts.new((x, y, z0)) for x, y in outline]
    bm.faces.new(top)
    bm.faces.new(bot[::-1])
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((top[j], top[i], bot[i], bot[j]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    data = bpy.data.meshes.new(name)
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.data.materials.append(mat)
    return obj


def seat(name, x, y, z, w, d, h, mat, back=0.0):
    """An upholstered seat block (base at z) with an optional backrest behind."""
    gnkit.bevel(box(name, (w, d, h), (x, y, z), mat), min(0.08, h * 0.3), 3)
    if back:
        gnkit.bevel(box(name + "Back", (w, 0.16, back), (x, y - d / 2 + 0.08, z + h), mat), 0.06, 3)


def outboard(y, z_top, m, s=1.0):
    """An outboard motor clamped to a transom at y whose top is at z_top."""
    zc = z_top + 0.22 * s
    gnkit.loft("Cowling", [((0, y - 0.08 * s, zc), 0.15 * s, 0.2 * s, 3.0), ((0, y - 0.3 * s, zc + 0.03 * s), 0.19 * s, 0.25 * s, 3.0),
                           ((0, y - 0.62 * s, zc), 0.15 * s, 0.21 * s, 3.0), ((0, y - 0.7 * s, zc), 0.08 * s, 0.14 * s, 3.0)],
               m["engine"], ring=24, steps=3)
    gnkit.loft("Leg", [((0, y - 0.32 * s, zc - 0.15 * s), 0.08 * s, 0.16 * s), ((0, y - 0.34 * s, -0.1 * s), 0.05 * s, 0.13 * s),
                       ((0, y - 0.36 * s, -0.42 * s), 0.045 * s, 0.12 * s)], m["engine"], ring=16, steps=3, up=(0, 1, 0))
    box("Clamp", (0.16 * s, 0.1 * s, 0.22 * s), (0, y - 0.06 * s, z_top - 0.12 * s), m["engine"])
    box("CavitationPlate", (0.3 * s, 0.34 * s, 0.012 * s), (0, y - 0.36 * s, -0.3 * s), m["engine"])
    hub = Vector((0, y - 0.36 * s, -0.46 * s))
    gnkit.lathe("Gearcase", [(0.0, -0.18 * s), (0.055 * s, -0.1 * s), (0.06 * s, 0.1 * s), (0.04 * s, 0.2 * s), (0.0, 0.24 * s)],
                m["engine"], 20, hub, axis="Y")
    prop = (0, hub.y - 0.2 * s, hub.z)
    for k in range(3):
        blade = box("Blade", (0.16 * s, 0.03 * s, 0.07 * s), (0.09 * s, prop[1], hub.z - 0.035 * s), m["metal"])
        gnkit.rotate_about([blade], "Y", k * 120, prop)


def _sail(name, corners, mat, camber):
    """A sail: a triangle (tack, head, clew) bellied out to leeward (+X)."""
    a, b, c = (Vector(p) for p in corners)
    rows = 12
    bm = bmesh.new()
    grid = []
    for i in range(rows + 1):
        u = i / rows
        row = []
        for j in range(rows + 1 - i):
            v = j / rows
            p = a + (b - a) * u + (c - a) * v
            belly = camber * 6.75 * v * (1 - u - v) * (1 - u) if u + v < 1 else 0.0
            row.append(bm.verts.new(p + Vector((belly, 0, 0))))
        grid.append(row)
    for i in range(rows):
        for j in range(rows - i):
            bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j]))
            if j + 1 < len(grid[i + 1]):
                bm.faces.new((grid[i + 1][j], grid[i][j + 1], grid[i + 1][j + 1]))
    data = bpy.data.meshes.new(name)
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    mat.use_backface_culling = False
    bpy.context.view_layer.objects.active = obj
    solid = obj.modifiers.new("Thickness", "SOLIDIFY")
    solid.thickness = 0.004
    bpy.ops.object.modifier_apply(modifier=solid.name)
    return obj


def rig(m, mast_y, deck_z, mast_h, boom_len, forestay, shrouds, main_camber=0.35):
    """A sloop rig: mast, boom, mainsail, jib, forestay and shrouds."""
    top = deck_z + mast_h
    gnkit.lathe("Mast", [(0.1, 0.0), (0.09, mast_h * 0.8), (0.06, mast_h), (0.0, mast_h + 0.02)], m["alu"], 16, (0, mast_y, deck_z))
    boom_z = deck_z + 1.0
    gnkit.lathe("Boom", [(0.0, 0.1), (0.075, 0.0), (0.065, -boom_len), (0.0, -boom_len - 0.05)], m["alu"], 12,
                (0, mast_y - 0.1, boom_z), axis="Y")
    _sail("Mainsail", [(0, mast_y - 0.15, boom_z + 0.08), (0, mast_y - 0.15, top - 0.4), (0, mast_y - boom_len + 0.1, boom_z + 0.1)],
          m["sail"], main_camber)
    fy, fz = forestay[1], forestay[2]
    head = (0, mast_y + 0.05, deck_z + mast_h * 0.86)
    clew = (0, mast_y - 0.6, deck_z + 0.5)
    _sail("Jib", [(0, fy - 0.1, fz + 0.3), head, clew], m["sail"], main_camber * 0.8)
    tube("Forestay", [forestay, (0, mast_y + 0.05, top - 0.2)], 0.007, m["rope"], verts=6)
    for p in shrouds:
        tube("Shroud", [p, (0, mast_y, top - 0.3)], 0.007, m["rope"], verts=6)


# --- boats ---------------------------------------------------------------------

def speedboat(name, label, colour):
    gnkit.reset()
    m = _mats()
    stripe = gnkit.material("Hull stripe " + name, colour, 0.25)
    hull = Hull([(-3.1, 1.12, 0.8, -0.1, -0.42), (-1.5, 1.18, 0.82, -0.1, -0.46), (0.5, 1.14, 0.88, -0.08, -0.44),
                 (1.8, 0.94, 0.96, -0.02, -0.34), (2.7, 0.55, 1.02, 0.14, -0.08), (3.1, 0.22, 1.06, 0.55, 0.4),
                 (3.3, 0.02, 1.08, 0.98, 0.95)])
    hull.mesh("Hull", {"top": m["hull_white"], "bottom": m["antifoul_blue"], "stripe": stripe}, deck=False, double_sided=True)
    hull.floor("Floor", 0.3, -3.1, 2.9, m["teak"])
    tube("RubRail", hull.gunwale(inset=-0.02, lift=0.01), 0.035, stripe, verts=8)
    # Aft bench across the transom, side seats, twin consoles, bow seating.
    b = hull.beam(-2.6, 0.5)
    seat("RearBench", 0, -2.6, 0.3, 2 * b - 0.1, 0.6, 0.42, m["cushion"], back=0.45)
    for sd in (-1, 1):
        hull.liner("SideSeat", -1.9, -0.7, 0.3, 0.4, 0.5, m["cushion"], side=sd, back=0.3)
        x = sd * (hull.beam(0.4, 0.5) - 0.42)
        gnkit.bevel(box("Console", (0.72, 0.9, 0.78), (x, 0.4, 0.3), m["hull_white"]), 0.12, 4)
        seat("HelmSeat", x, -0.5, 0.3, 0.55, 0.55, 0.45, m["cushion"], back=0.4)
        hull.liner("BowSeat", 1.3, 2.75, 0.3, 0.38, 0.45, m["cushion"], side=sd, back=0.25)
    wheel_x = hull.beam(0.4, 0.5) - 0.42
    gnkit.lathe("Wheel", [(0.19, 0.0), (0.19, 0.03)], m["plastic"], 32, (wheel_x, 0.2, 1.2), axis="Y", caps=False)
    gnkit.lathe("WheelHub", [(0.04, -0.06), (0.04, 0.03)], m["plastic"], 12, (wheel_x, 0.2, 1.2), axis="Y")
    gnkit.picture("Plotter", 0.26, 0.16, (wheel_x, 0.62, 1.12), gnkit.screen_material("screen_small"), "-Y")
    # A wraparound windscreen standing on the consoles.
    ws = [(sd * (hull.beam(y, 0.9) - 0.02), y, 1.08) for sd, y in ((1, 0.6), (1, 0.85), (0, 1.0), (-1, 0.85), (-1, 0.6))]
    gnkit.loft("Windscreen", [(p, 0.005, 0.24) for p in ws], m["glass"], ring=8, steps=6, up=(0, 0, 1))
    tube("ScreenFrame", [(x, y, z + 0.24) for x, y, z in ws], 0.012, m["metal"])
    # Bow rail on stanchions.
    rail = [(x, y, z + 0.32) for x, y, z in hull.gunwale(inset=0.06, y0=1.6)]
    tube("BowRail", rail, 0.016, m["metal"])
    for x, y, z in rail[::4]:
        tube("Stanchion", [(x, y, z - 0.32), (x, y, z)], 0.014, m["metal"])
    outboard(-3.1, 0.8, m, 1.3)
    _export("boats", name, label, "boat", {"length_m": 6.6, "beam_m": 2.4, "waterline": True})


def yacht(name, label):
    gnkit.reset()
    m = _mats()
    hull = Hull([(-5.0, 1.35, 0.9, 0.05, -0.05), (-3.5, 1.68, 0.95, -0.12, -0.35), (-1.0, 1.76, 1.0, -0.2, -0.55),
                 (1.5, 1.62, 1.06, -0.2, -0.5), (3.5, 1.12, 1.16, -0.1, -0.35), (4.6, 0.42, 1.22, 0.15, -0.05),
                 (5.15, 0.02, 1.26, 1.15, 1.1)], form="round")
    hull.mesh("Hull", {"top": m["hull_white"], "bottom": m["antifoul_blue"], "stripe": m["stripe"], "deck": m["teak"]})
    # Keel fin with a bulb, and a spade rudder.
    gnkit.bevel(gnkit.prism("Keel", [(0.55, -0.4), (0.3, -1.65), (-0.4, -1.65), (-0.7, -0.4)], 0.14, m["antifoul_blue"]), 0.04, 3)
    gnkit.lathe("Bulb", [(0.0, 0.6), (0.14, 0.35), (0.17, 0.0), (0.1, -0.4), (0.0, -0.55)], m["antifoul_blue"], 20,
                (0, 0, -1.72), axis="Y")
    gnkit.bevel(gnkit.prism("Rudder", [(-3.7, -0.2), (-3.8, -1.25), (-4.1, -1.2), (-4.1, -0.2)], 0.07, m["antifoul_blue"]), 0.02, 2)
    # Coachroof with its windows; the cockpit coamings and seats; the wheel.
    gnkit.bevel(box("Coachroof", (2.1, 3.6, 0.5), (0, 0.6, 0.9), m["hull_white"]), 0.14, 4)
    for sd in (-1, 1):
        box("CabinWindow", (0.02, 2.2, 0.16), (sd * 1.05, 0.8, 1.17), m["dark_glass"])
        seat("CockpitSeat", sd * 0.95, -2.6, 0.95, 0.45, 2.3, 0.35, m["cushion"])
        box("Coaming", (0.06, 3.0, 0.35), (sd * 1.25, -2.4, 0.95), m["hull_white"])
    box("Hatch", (0.7, 0.7, 0.04), (0, 2.5, hull.sheer(2.5) - 0.02), m["dark_glass"])
    gnkit.lathe("Pedestal", [(0.07, 0.0), (0.06, 0.75)], m["metal"], 12, (0, -4.0, 0.95))
    gnkit.lathe("Wheel", [(0.42, 0.0), (0.42, 0.03)], m["metal"], 40, (0, -3.9, 1.35), axis="Y", caps=False)
    rig(m, 0.9, 1.1, 14.0, 4.3, (0, 5.05, 1.27), [(1.62, 0.7, 1.0), (-1.62, 0.7, 1.0)])
    tube("Backstay", [(0, -4.9, 0.95), (0, 0.9, 15.0)], 0.006, m["rope"], verts=6)
    # Lifelines and a top rail on stanchions.
    for lift in (0.35, 0.62):
        line = hull.gunwale(inset=0.08, lift=lift, y0=-4.8, y1=4.7)
        tube("Lifeline", line, 0.006 if lift < 0.5 else 0.009, m["rope"] if lift < 0.5 else m["metal"], verts=6)
    for x, y, z in hull.gunwale(inset=0.08, y0=-4.8, y1=4.7)[::6]:
        tube("Stanchion", [(x, y, z), (x, y, z + 0.62)], 0.013, m["metal"], verts=8)
    _export("boats", name, label, "boat", {"length_m": 10.3, "beam_m": 3.5, "mast_m": 15.4, "waterline": True})


def catamaran(name, label):
    """A cruising sailing catamaran: two slim hulls, a bridge deck with a
    glazed saloon under a hardtop, a net trampoline forward, a tall rig."""
    gnkit.reset()
    m = _mats()
    hull = Hull([(-5.9, 0.58, 1.05, 0.05, -0.15), (-4.5, 0.72, 1.08, -0.2, -0.5), (-1.0, 0.78, 1.12, -0.28, -0.66),
                 (2.5, 0.7, 1.16, -0.24, -0.58), (4.8, 0.36, 1.26, 0.0, -0.3), (5.95, 0.02, 1.32, 0.9, 0.85)], form="round")
    for sd in (-1, 1):
        h = hull.mesh("Hull", {"top": m["hull_white"], "bottom": m["antifoul"], "stripe": m["stripe"], "deck": m["teak"]})
        h.data.transform(Matrix.Translation((sd * 2.55, 0, 0)))
    # Bridge deck between the hulls, the saloon, the flybridge hardtop.
    gnkit.bevel(box("BridgeDeck", (4.4, 7.4, 0.4), (0, -1.9, 0.72), m["hull_white"]), 0.12, 3)
    box("CockpitSole", (3.6, 2.2, 0.02), (0, -4.3, 1.12), m["teak"])
    gnkit.bevel(box("Saloon", (4.4, 4.2, 1.15), (0, -0.8, 1.12), m["hull_white"]), 0.22, 5)
    box("SaloonFront", (4.0, 0.03, 0.6), (0, 1.31, 1.5), m["dark_glass"])
    for sd in (-1, 1):
        box("SideGlass", (0.02, 3.0, 0.5), (sd * 2.21, -1.0, 1.62), m["dark_glass"])
        for y in (-4.3, -3.0):
            gnkit.lathe("HardtopPost", [(0.04, 0.0), (0.04, 1.15)], m["alu"], 10, (sd * 2.0, y, 1.14))
    gnkit.bevel(box("Hardtop", (4.7, 6.2, 0.14), (0, -1.9, 2.28), m["hull_white"]), 0.06, 3)
    seat("AftBench", 0, -4.9, 1.14, 3.0, 0.55, 0.4, m["cushion"], back=0.4)
    tramp = gnkit.material("Trampoline", (0.08, 0.08, 0.09), 0.9)
    box("Trampoline", (4.4, 3.5, 0.02), (0, 3.3, 1.1), tramp)
    gnkit.lathe("Crossbeam", [(0.09, -2.4), (0.09, 2.4)], m["alu"], 12, (0, 5.0, 1.2), axis="X")
    rig(m, 1.1, 2.42, 17.0, 5.0, (0, 5.0, 1.3), [(2.6, 0.9, 1.1), (-2.6, 0.9, 1.1)], main_camber=0.45)
    _export("boats", name, label, "boat", {"length_m": 12.0, "beam_m": 6.7, "mast_m": 19.5, "waterline": True})


def dinghy(name, label):
    gnkit.reset()
    m = _mats()
    hull = Hull([(-1.65, 0.58, 0.36, 0.0, -0.1), (-0.8, 0.72, 0.37, -0.04, -0.15), (0.3, 0.7, 0.4, -0.04, -0.15),
                 (1.2, 0.46, 0.46, 0.02, -0.1), (1.75, 0.02, 0.56, 0.5, 0.45)], form="round")
    hull.mesh("Hull", {"top": m["wood"], "bottom": m["antifoul"]}, deck=False, double_sided=True)
    hull.floor("Floorboards", -0.05, -1.5, 1.3, m["wood"], inset=0.02, thick=0.02)
    for y in (-1.25, -0.1, 0.95):
        x = hull.beam(y, 0.22)
        box("Thwart", (2 * x, 0.22, 0.03), (0, y, 0.2), m["wood"])
    tube("Gunwale", hull.gunwale(lift=0.005), 0.022, m["wood"], verts=6)
    for sd in (-1, 1):
        # Oars shipped along the thwarts, blades forward.
        x = sd * 0.32
        tube("Oar", [(x, -1.4, 0.26), (x, 0.9, 0.26)], 0.018, m["wood"], verts=8)
        gnkit.bevel(box("OarBlade", (0.13, 0.5, 0.012), (x, 1.1, 0.254), m["wood"]), 0.005, 1)
        rx = sd * hull.beam(-0.2, 0.4)
        tube("Rowlock", [(rx, -0.2, 0.4), (rx, -0.2, 0.47)], 0.01, m["metal"])
    _export("boats", name, label, "boat", {"length_m": 3.4, "beam_m": 1.45, "waterline": True})


def rib(name, label):
    gnkit.reset()
    m = _mats()
    hull = Hull([(-2.6, 0.9, 0.5, -0.08, -0.33), (-1.0, 0.95, 0.52, -0.1, -0.38), (0.8, 0.9, 0.56, -0.06, -0.34),
                 (1.9, 0.58, 0.64, 0.06, -0.14), (2.6, 0.03, 0.74, 0.68, 0.65)])
    hull.mesh("Hull", {"top": m["hull_white"], "bottom": m["antifoul"]}, deck=False, double_sided=True)
    hull.floor("Deck", 0.28, -2.6, 2.3, m["teak"])
    # The inflatable tube, riding on the hull's sheer and closed round the bow.
    path = hull.gunwale(inset=-0.12, lift=0.12)
    path = [(path[0][0], path[0][1] - 0.45, path[0][2])] + path + [(path[-1][0], path[-1][1] - 0.45, path[-1][2])]
    gnkit.loft("Tube", [(p, 0.23, 0.23) for p in path], m["hypalon"], ring=20, steps=2, up=(0, 0, 1))
    gnkit.bevel(box("Console", (0.7, 0.6, 0.85), (0, 0.2, 0.28), m["hull_white"]), 0.08, 3)
    box("ConsoleScreen", (0.66, 0.02, 0.28), (0, 0.49, 1.0), m["glass"])
    gnkit.lathe("Wheel", [(0.16, 0.0), (0.16, 0.025)], m["plastic"], 28, (0, -0.12, 1.02), axis="Y", caps=False)
    seat("Jockey", 0, -0.7, 0.28, 0.5, 0.7, 0.72, m["cushion"])
    outboard(-2.6, 0.5, m, 1.15)
    _export("boats", name, label, "boat", {"length_m": 5.5, "beam_m": 2.3, "waterline": True})


def jetski(name, label, colour):
    gnkit.reset()
    m = _mats()
    body = gnkit.material("Jet ski " + name, colour, 0.25)
    hull = Hull([(-1.55, 0.48, 0.32, 0.0, -0.08), (-0.6, 0.56, 0.36, -0.02, -0.16), (0.5, 0.54, 0.42, 0.02, -0.14),
                 (1.25, 0.34, 0.5, 0.14, 0.0), (1.7, 0.03, 0.56, 0.52, 0.5)])
    hull.mesh("Hull", {"top": body, "bottom": m["plastic"], "stripe": m["hull_white"], "deck": m["deck"]})
    # The upper deck: a raised hood forward, the seat aft of it.
    gnkit.loft("Hood", [((0, 0.25, 0.45), 0.42, 0.14, 3.0), ((0, 0.8, 0.52), 0.38, 0.12, 3.0), ((0, 1.35, 0.54), 0.2, 0.06, 2.5),
                        ((0, 1.6, 0.54), 0.04, 0.02)], body, ring=24, steps=4)
    gnkit.loft("Seat", [((0, -1.35, 0.42), 0.18, 0.05), ((0, -1.1, 0.5), 0.23, 0.1, 2.5), ((0, -0.2, 0.54), 0.24, 0.12, 2.5),
                        ((0, 0.25, 0.56), 0.2, 0.1, 2.5), ((0, 0.35, 0.55), 0.08, 0.04)], m["plastic"], ring=20, steps=4)
    gnkit.loft("Pod", [((0, 0.45, 0.55), 0.14, 0.1), ((0, 0.62, 0.72), 0.12, 0.08), ((0, 0.72, 0.82), 0.1, 0.05)], body,
               ring=16, steps=3, up=(0, 1, 0))
    tube("Bars", [(-0.36, 0.62, 0.9), (-0.1, 0.72, 0.86), (0.1, 0.72, 0.86), (0.36, 0.62, 0.9)], 0.018, m["metal"])
    for sd in (-1, 1):
        tube("Grip", [(sd * 0.36, 0.62, 0.9), (sd * 0.48, 0.58, 0.91)], 0.026, m["rubber"])
    box("Nozzle", (0.18, 0.2, 0.14), (0, -1.62, -0.02), m["plastic"])
    _export("boats", name, label, "boat", {"length_m": 3.3, "waterline": True})


def tour_boat(name, label):
    """A river tour boat: long, low, a glazed saloon with rows of seats."""
    gnkit.reset()
    m = _mats()
    hull = Hull([(-10.5, 2.3, 0.95, -0.3, -0.5), (-6, 2.5, 0.98, -0.4, -0.7), (4, 2.5, 1.02, -0.4, -0.7),
                 (8.5, 1.8, 1.12, -0.2, -0.5), (10.6, 0.3, 1.3, 0.3, 0.1), (11.0, 0.02, 1.36, 1.25, 1.2)], form="round")
    hull.mesh("Hull", {"top": m["hull_white"], "bottom": m["antifoul_blue"], "stripe": m["stripe"], "deck": m["teak"]})
    gnkit.bevel(box("SaloonBase", (4.4, 13.0, 0.5), (0, -1.0, 0.98), m["hull_white"]), 0.05, 2)
    for sd in (-1, 1):
        box("SaloonGlass", (0.03, 12.6, 1.35), (sd * 2.2, -1.0, 1.48), m["dark_glass"])
        for k in range(8):
            box("Mullion", (0.06, 0.08, 1.35), (sd * 2.21, -7.3 + k * 1.8, 1.48), m["hull_white"])
    box("SaloonEndGlass", (4.3, 0.03, 1.35), (0, 5.5, 1.48), m["dark_glass"])
    gnkit.bevel(box("Roof", (4.6, 13.4, 0.12), (0, -1.0, 2.83), m["hull_white"]), 0.05, 2)
    for k in range(12):
        for sd in (-1, 1):
            seat("SeatRow", sd * 1.1, -7.0 + k * 1.05, 1.0, 1.5, 0.45, 0.45, m["stripe"], back=0.45)
    gnkit.bevel(box("Wheelhouse", (2.2, 1.8, 1.9), (0, 7.0, hull.sheer(7.0)), m["hull_white"]), 0.1, 3)
    box("WheelhouseGlass", (2.22, 0.03, 0.7), (0, 7.9, hull.sheer(7.0) + 1.05), m["dark_glass"])
    rail = hull.gunwale(inset=0.05, lift=1.0, y0=-10.4)
    tube("Rail", rail, 0.022, m["metal"])
    for x, y, z in rail[::5]:
        tube("RailPost", [(x, y, z - 1.0), (x, y, z)], 0.018, m["metal"])
    _export("boats", name, label, "boat", {"length_m": 21.5, "beam_m": 5.0, "waterline": True})


def narrowboat(name, label, colour):
    """A canal narrowboat: a black steel hull, a long painted cabin with
    portholes and a cream coachline, a tiller at the stern."""
    gnkit.reset()
    m = _mats()
    steel = gnkit.material("Blacked steel", (0.04, 0.04, 0.04), 0.5, 0.4)
    paint = gnkit.material("Cabin paint " + name, colour, 0.35)
    cream = gnkit.material("Coachline cream", (0.9, 0.85, 0.65), 0.35)
    red = gnkit.material("Oxide red", (0.4, 0.07, 0.05), 0.7)
    hull = Hull([(-10.0, 0.95, 0.52, -0.25, -0.55), (-9.0, 1.04, 0.5, -0.5, -0.62), (-4.0, 1.04, 0.5, -0.55, -0.62),
                 (5.0, 1.04, 0.5, -0.55, -0.62), (8.4, 1.0, 0.52, -0.5, -0.6), (9.6, 0.55, 0.6, -0.3, -0.5),
                 (10.2, 0.02, 0.72, 0.6, 0.55)])
    hull.mesh("Hull", {"top": steel, "bottom": red, "stripe": steel, "deck": paint})
    gnkit.bevel(box("Cabin", (1.9, 15.5, 1.1), (0, -1.0, 0.5), paint), 0.03, 2)
    box("Coachline", (1.92, 15.4, 0.05), (0, -1.0, 1.35), cream)
    gnkit.bevel(box("Roof", (1.96, 15.6, 0.08), (0, -1.0, 1.58), paint), 0.03, 2)
    for k in range(14):
        y = -8.0 + k * 1.05
        for sd in (-1, 1):
            if k % 3 == 1:
                box("Window", (0.02, 0.6, 0.4), (sd * 0.955, y, 0.9), m["dark_glass"])
            else:
                gnkit.lathe("Porthole", [(0.11, 0.0), (0.11, 0.02), (0.08, 0.02)], m["alu"], 20, (sd * 0.94, y, 1.1), axis="X")
                gnkit.lathe("PortGlass", [(0.08, 0.0), (0.0, 0.004)], m["dark_glass"], 20, (sd * 0.955, y, 1.1), axis="X")
    tube("Tiller", [(0, -9.9, 0.55), (0, -10.3, 1.05), (0, -9.8, 1.12)], 0.02, m["metal"])
    gnkit.lathe("Chimney", [(0.07, 0.0), (0.07, 0.35), (0.09, 0.37), (0.09, 0.42)], steel, 16, (0.4, 4.5, 1.66))
    gnkit.lathe("Tub", [(0.2, 0.0), (0.24, 0.25)], cream, 20, (-0.4, 3.0, 1.66))
    _export("boats", name, label, "boat", {"length_m": 20.1, "beam_m": 2.08, "waterline": True})


def pontoon(name, label):
    """A party pontoon: twin tubes, a flat deck with seating, a canopy."""
    gnkit.reset()
    m = _mats()
    for sd in (-1, 1):
        gnkit.lathe("PontoonTube", [(0.0, -3.9), (0.25, -3.8), (0.32, -3.5), (0.32, 3.2), (0.26, 3.7), (0.1, 4.0), (0.0, 4.02)],
                    m["alu"], 24, (sd * 1.0, 0, 0.02), axis="Y")
    gnkit.bevel(box("Deck", (2.6, 7.6, 0.08), (0, 0.0, 0.34), m["teak"]), 0.02, 2)
    box("Skirt", (2.64, 7.64, 0.2), (0, 0.0, 0.2), m["alu"])
    for sd in (-1, 1):
        seat("Bench", sd * 0.98, -0.5, 0.42, 0.55, 5.0, 0.42, m["cushion"])
        gnkit.bevel(box("BenchBack", (0.15, 5.0, 0.42), (sd * 1.2, -0.5, 0.84), m["cushion"]), 0.06, 2)
        for y in (-2.8, 2.2):
            tube("CanopyPost", [(sd * 1.25, y, 0.42), (sd * 1.25, y, 2.32)], 0.02, m["metal"])
    canopy = gnkit.material("Canopy", (0.15, 0.25, 0.45), 0.8)
    box("Canopy", (2.6, 5.6, 0.04), (0, -0.3, 2.32), canopy)
    tube("Rail", [(1.28, -3.7, 1.2), (1.28, 3.7, 1.2), (-1.28, 3.7, 1.2), (-1.28, -3.7, 1.2), (1.28, -3.7, 1.2)], 0.02, m["metal"])
    outboard(-3.8, 0.42, m, 1.1)
    _export("boats", name, label, "boat", {"length_m": 8.0, "beam_m": 2.6, "waterline": True})


# --- aircraft ------------------------------------------------------------------
# Their origin is where they stand on the ground; a flying one is simply
# placed up in the air. Rotors and propellers are still: a render freezes
# them anyway, and a blur disc reads wrong from most angles.

def _air_mats(colour, name):
    m = _mats()
    m.update({
        "body": gnkit.material("Paint " + name, colour, 0.22, 0.1),
        "canopy": gnkit.material("Canopy glass", (0.03, 0.05, 0.07), 0.03, 0.4),
        "blade": gnkit.material("Rotor blade", (0.08, 0.08, 0.09), 0.4),
        "tip": gnkit.material("Blade tip", (0.9, 0.75, 0.1), 0.5),
    })
    return m


def _glazed(obj, paint, glass, is_glass):
    """Paints a fuselage: glass where is_glass(centre, normal), paint elsewhere."""
    gnkit.material_by_face(obj, lambda c, n: 1 if is_glass(c, n) else 0, [paint, glass])


def _blades(name, hub, radius, chord, count, m, axis="Z", start=0.0, droop=0.0, thick=0.03):
    """Rotor or propeller blades radiating from hub, round an axis."""
    made = []
    for k in range(count):
        blade = box(name, (radius, chord, thick), (radius / 2 + 0.1 * chord, 0, -thick / 2), m["blade"])
        tip = box(name + "Tip", (0.25 * min(1.0, radius / 2), chord * 1.01, thick * 1.1),
                  (radius - 0.12 * min(1.0, radius / 2) + 0.1 * chord, 0, -thick * 0.55), m["tip"])
        for part in (blade, tip):
            mat = Matrix.Rotation(math.radians(droop), 4, "Y")
            mat = Matrix.Rotation(math.radians(start + k * 360.0 / count), 4, "Z") @ mat
            if axis == "Y":
                mat = Matrix.Rotation(math.radians(-90), 4, "X") @ mat
            elif axis == "X":
                mat = Matrix.Rotation(math.radians(90), 4, "Y") @ mat
            part.data.transform(Matrix.Translation(hub) @ mat)
            made.append(part)
    return made


def _wheel(name, centre, r, width, m):
    gnkit.lathe(name, [(r * 0.5, -width / 2), (r * 0.9, -width / 2), (r, -width * 0.3), (r, width * 0.3), (r * 0.9, width / 2),
                       (r * 0.5, width / 2)], m["rubber"], 24, centre, axis="X")
    gnkit.lathe(name + "Hub", [(r * 0.52, -width * 0.4), (r * 0.52, width * 0.4)], m["metal"], 16, centre, axis="X")


def helicopter(name, label, colour):
    """A light single-engine helicopter on skids: a bubble cabin, a slim
    tail boom, a two-blade tail rotor and a three-blade main rotor."""
    gnkit.reset()
    m = _air_mats(colour, name)
    body = gnkit.loft("Fuselage", [
        ((0, 2.05, 1.12), 0.06, 0.08), ((0, 1.8, 1.15), 0.48, 0.5, 2.2), ((0, 1.25, 1.25), 0.74, 0.72, 2.4),
        ((0, 0.3, 1.32), 0.8, 0.8, 2.6), ((0, -0.7, 1.38), 0.76, 0.78, 2.7), ((0, -1.5, 1.5), 0.5, 0.56, 2.4),
        ((0, -2.3, 1.68), 0.2, 0.25), ((0, -3.2, 1.78), 0.13, 0.15), ((0, -6.6, 1.9), 0.08, 0.09),
        ((0, -6.95, 1.92), 0.04, 0.05)], m["body"], ring=32, steps=5)
    _glazed(body, m["body"], m["canopy"], lambda c, n: (c.y > 0.55 and c.z > 0.95 and n.y > -0.2)
            or (-0.85 < c.y < 0.55 and 1.3 < c.z < 1.95 and abs(n.x) > 0.75))
    gnkit.loft("Cowling", [((0, 0.5, 2.0), 0.05, 0.04), ((0, 0.3, 2.05), 0.4, 0.22, 2.6), ((0, -1.3, 2.05), 0.42, 0.25, 2.6),
                           ((0, -2.1, 1.95), 0.12, 0.1)], m["body"], ring=24, steps=4)
    box("Exhaust", (0.16, 0.3, 0.16), (0, -2.05, 1.93), m["dark_metal"])
    # Tail: fin, tail rotor on the left, a horizontal stabiliser.
    gnkit.bevel(gnkit.prism("Fin", [(-6.3, 1.85), (-6.95, 2.95), (-7.25, 2.95), (-7.0, 1.95), (-6.95, 1.55), (-6.5, 1.6)], 0.06,
                            m["body"]), 0.02, 2)
    gnkit.bevel(box("Stabiliser", (1.9, 0.4, 0.05), (0, -5.8, 1.85), m["body"]), 0.02, 2)
    gnkit.lathe("TailHub", [(0.07, 0.0), (0.07, 0.14), (0.0, 0.2)], m["metal"], 12, (-0.04, -7.0, 2.45), axis="X")
    _blades("TailBlade", Vector((-0.2, -7.0, 2.45)), 0.75, 0.13, 2, m, axis="X", start=30, thick=0.025)
    # Mast, hub and main rotor.
    gnkit.lathe("Mast", [(0.1, 0.0), (0.08, 0.5), (0.18, 0.55), (0.18, 0.7), (0.0, 0.78)], m["metal"], 16, (0, -0.25, 2.28))
    _blades("Blade", Vector((0, -0.25, 2.95)), 5.2, 0.28, 3, m, start=15, droop=1.5)
    # Skids on curved cross tubes.
    for sd in (-1, 1):
        tube("Skid", [(sd * 1.1, -1.7, 0.06), (sd * 1.1, 1.3, 0.06), (sd * 1.1, 1.65, 0.2), (sd * 1.08, 1.75, 0.38)], 0.045,
             m["metal"], verts=10)
        for y in (0.85, -0.95):
            tube("CrossTube", [(sd * 1.1, y, 0.06), (sd * 1.05, y, 0.45), (sd * 0.8, y, 0.62), (sd * 0.45, y, 0.68)], 0.04,
                 m["metal"], verts=10)
    for y in (0.85, -0.95):
        tube("CrossTube", [(-0.45, y, 0.68), (0.45, y, 0.68)], 0.04, m["metal"], verts=10)
    box("Step", (0.08, 0.5, 0.03), (1.1, 0.0, 0.3), m["metal"])
    _export("aircraft", name, label, "helicopter", {"rotor_m": 10.6, "length_m": 9.6})


def heavy_helicopter(name, label, colour):
    """A twin-engine utility helicopter on wheels, built to lift: a big
    cabin, sliding doors, a five-blade rotor and a cargo hook under the
    belly (the flying screen hangs from it)."""
    gnkit.reset()
    m = _air_mats(colour, name)
    body = gnkit.loft("Fuselage", [
        ((0, 3.6, 1.35), 0.08, 0.1), ((0, 3.3, 1.35), 0.7, 0.62, 2.2), ((0, 2.5, 1.55), 1.05, 0.95, 2.8),
        ((0, 1.2, 1.7), 1.2, 1.1, 3.2), ((0, -1.5, 1.75), 1.2, 1.12, 3.4), ((0, -2.9, 1.95), 0.85, 0.85, 2.8),
        ((0, -4.0, 2.25), 0.35, 0.4), ((0, -5.2, 2.4), 0.24, 0.26), ((0, -9.8, 2.6), 0.16, 0.18),
        ((0, -10.3, 2.65), 0.08, 0.1)], m["body"], ring=36, steps=5)
    _glazed(body, m["body"], m["canopy"], lambda c, n: (c.y > 2.0 and c.z > 1.45 and n.y > -0.2)
            or (-1.3 < c.y < 1.7 and 1.95 < c.z < 2.45 and abs(n.x) > 0.8))
    gnkit.loft("EngineDeck", [((0, 1.6, 2.72), 0.1, 0.05), ((0, 1.2, 2.85), 0.85, 0.35, 2.8), ((0, -2.4, 2.9), 0.9, 0.38, 2.8),
                              ((0, -3.6, 2.7), 0.3, 0.2)], m["body"], ring=28, steps=4)
    for sd in (-1, 1):
        gnkit.lathe("Intake", [(0.22, 0.0), (0.18, -0.08), (0.14, -0.05)], m["dark_metal"], 20, (sd * 0.48, 1.25, 3.0), axis="Y")
        box("DoorRail", (0.03, 3.0, 0.05), (sd * 1.21, -0.2, 2.6), m["metal"])
    # Sponsons carry the main wheels; a nose wheel forward.
    for sd in (-1, 1):
        gnkit.loft("Sponson", [((sd * 1.25, 0.2, 0.95), 0.08, 0.1), ((sd * 1.35, -0.4, 0.95), 0.35, 0.28, 2.6),
                               ((sd * 1.35, -1.6, 0.95), 0.35, 0.28, 2.6), ((sd * 1.25, -2.2, 1.0), 0.1, 0.1)],
                   m["body"], ring=20, steps=3)
        _wheel("MainWheel", (sd * 1.55, -1.0, 0.36), 0.36, 0.22, m)
        tube("Strut", [(sd * 1.45, -1.0, 0.4), (sd * 1.35, -1.0, 0.8)], 0.05, m["metal"])
    _wheel("NoseWheel", (0, 2.7, 0.27), 0.27, 0.16, m)
    tube("NoseStrut", [(0, 2.7, 0.3), (0, 2.65, 0.8)], 0.05, m["metal"])
    # Tail: a canted fin with the tail rotor, a stabiliser.
    gnkit.bevel(gnkit.prism("Fin", [(-9.3, 2.5), (-10.2, 4.1), (-10.7, 4.1), (-10.4, 2.6), (-10.3, 2.2), (-9.6, 2.3)], 0.1,
                            m["body"]), 0.03, 2)
    gnkit.bevel(box("Stabiliser", (2.8, 0.6, 0.07), (0, -8.8, 2.55), m["body"]), 0.03, 2)
    gnkit.lathe("TailHub", [(0.1, 0.0), (0.1, 0.2), (0.0, 0.28)], m["metal"], 12, (-0.05, -10.3, 3.4), axis="X")
    _blades("TailBlade", Vector((-0.28, -10.3, 3.4)), 1.25, 0.2, 4, m, axis="X", start=20, thick=0.03)
    gnkit.lathe("Mast", [(0.16, 0.0), (0.13, 0.4), (0.3, 0.45), (0.3, 0.62), (0.0, 0.72)], m["metal"], 16, (0, -0.4, 3.2))
    _blades("Blade", Vector((0, -0.4, 3.8)), 7.0, 0.5, 5, m, start=10, droop=1.5, thick=0.05)
    # The cargo hook, on its swivel under the belly.
    gnkit.lathe("HookMount", [(0.18, 0.0), (0.18, -0.08), (0.06, -0.1)], m["dark_metal"], 16, (0, -0.4, 0.66))
    tube("Hook", [(0, -0.4, 0.56), (0, -0.4, 0.42), (0.08, -0.4, 0.36), (0.1, -0.4, 0.44)], 0.025, m["yellow"])
    # glTF is Y up and faces -Z: the hook sits at (0, 0.36, 0.4) in Godot.
    _export("aircraft", name, label, "helicopter", {"rotor_m": 14.0, "length_m": 14.6, "hook": [0.0, 0.36, 0.4],
                                                                "hook_limit_kg": 4000})


def light_plane(name, label, colour):
    """A four-seat high-wing single-engine plane on a fixed tricycle gear."""
    gnkit.reset()
    m = _air_mats(colour, name)
    white = m["hull_white"]
    body = gnkit.loft("Fuselage", [
        ((0, 2.55, 1.35), 0.12, 0.12), ((0, 2.35, 1.35), 0.4, 0.4, 2.4), ((0, 1.6, 1.4), 0.55, 0.55, 2.8),
        ((0, 0.8, 1.6), 0.58, 0.75, 3.0), ((0, -0.4, 1.62), 0.56, 0.72, 3.0), ((0, -1.6, 1.62), 0.4, 0.5, 2.6),
        ((0, -4.3, 1.75), 0.14, 0.22), ((0, -4.7, 1.8), 0.06, 0.12)], white, ring=28, steps=5)
    painted = m["body"]

    def livery(c, n):
        if (0.35 < c.y < 1.35 and c.z > 1.75 and n.y > 0.2) or (-0.9 < c.y < 1.0 and 1.7 < c.z < 2.2 and abs(n.x) > 0.8):
            return 1
        # A cheat line down each flank, rising with the fuselage towards the tail.
        mid = 1.45 + max(0.0, -c.y - 1.0) * 0.08
        return 2 if abs(c.z - mid) < 0.05 and abs(n.x) > 0.5 and c.y < 1.6 else 0
    gnkit.material_by_face(body, livery, [white, m["canopy"], painted])
    gnkit.lathe("Spinner", [(0.18, 0.0), (0.14, 0.2), (0.0, 0.32)], painted, 20, (0, 2.55, 1.35), axis="Y")
    _blades("Prop", Vector((0, 2.65, 1.35)), 0.95, 0.12, 2, m, axis="Y", start=70, thick=0.03)
    # High wing: an airfoil section run out along the span, on struts.
    foil = [(0.75, 0.0), (0.7, 0.05), (0.45, 0.1), (0.0, 0.1), (-0.55, 0.05), (-0.8, 0.0), (-0.55, -0.02), (0.0, -0.03),
            (0.5, -0.02)]
    wing = gnkit.prism("Wing", [(y + 0.5, z + 2.28) for y, z in foil], 11.0, white)
    gnkit.material_by_face(wing, lambda c, n: 1 if abs(c.x) > 5.2 else 0, [white, painted])
    for sd in (-1, 1):
        tube("Strut", [(sd * 0.55, 0.6, 1.1), (sd * 2.6, 0.6, 2.26)], 0.035, m["metal"])
    tail = [(0.3, 0.0), (0.2, 0.03), (0.0, 0.035), (-0.4, 0.0), (0.0, -0.03), (0.2, -0.03)]
    gnkit.prism("Tailplane", [(y - 4.2, z + 1.78) for y, z in tail], 3.4, white)
    gnkit.bevel(gnkit.prism("Fin", [(-3.5, 1.9), (-4.4, 3.05), (-4.8, 3.05), (-4.75, 1.8)], 0.06, painted), 0.02, 2)
    # Tricycle gear with spats.
    _wheel("NoseWheel", (0, 1.9, 0.2), 0.2, 0.12, m)
    tube("NoseStrut", [(0, 1.9, 0.22), (0, 2.1, 0.95)], 0.04, m["metal"])
    for sd in (-1, 1):
        _wheel("MainWheel", (sd * 1.25, 0.05, 0.22), 0.22, 0.14, m)
        gnkit.loft("Spat", [((sd * 1.25, 0.45, 0.25), 0.03, 0.03), ((sd * 1.25, 0.2, 0.28), 0.1, 0.2), ((sd * 1.25, -0.2, 0.3), 0.09, 0.18),
                            ((sd * 1.25, -0.45, 0.33), 0.02, 0.04)], painted, ring=16, steps=3)
        tube("GearLeg", [(sd * 1.2, 0.05, 0.3), (sd * 0.45, 0.05, 1.05)], 0.04, m["metal"])
    _export("aircraft", name, label, "plane", {"span_m": 11.0, "length_m": 7.3})


def drone(name, label):
    """A camera drone: an X frame, four motors and props, a gimbal camera
    slung below, landing legs. Its origin is on the ground under it."""
    gnkit.reset()
    m = _air_mats((0.35, 0.36, 0.38), name)
    body = m["body"]
    gnkit.loft("Body", [((0, 0.2, 0.16), 0.03, 0.02), ((0, 0.15, 0.17), 0.07, 0.04, 3.0), ((0, -0.1, 0.17), 0.08, 0.045, 3.0),
                        ((0, -0.2, 0.17), 0.04, 0.03)], body, ring=20, steps=3)
    for a in (45, 135, 225, 315):
        d = Vector((math.sin(math.radians(a)), math.cos(math.radians(a)), 0))
        end = Vector((0, 0, 0.18)) + d * 0.27
        tube("Arm", [(0, 0, 0.18), tuple(end)], 0.012, body)
        gnkit.lathe("Motor", [(0.025, 0.0), (0.025, 0.03), (0.0, 0.034)], m["dark_metal"], 16, tuple(end))
        _blades("Prop", end + Vector((0, 0, 0.038)), 0.12, 0.022, 2, m, start=a * 0.7, thick=0.004)
        led = m["led_red"] if 90 < a < 270 else m["led_green"]
        gnkit.lathe("Led", [(0.008, 0.0), (0.0, 0.006)], led, 8, tuple(end + Vector((0, 0, -0.008))))
    for sd in (-1, 1):
        tube("Leg", [(sd * 0.05, 0.02, 0.15), (sd * 0.1, 0.02, 0.005)], 0.006, m["plastic"])
        tube("Foot", [(sd * 0.1, -0.08, 0.005), (sd * 0.1, 0.12, 0.005)], 0.006, m["plastic"])
    # Gimbal and camera.
    box("GimbalYoke", (0.05, 0.02, 0.04), (0, 0.13, 0.1), m["plastic"])
    gnkit.bevel(box("Camera", (0.045, 0.045, 0.04), (0, 0.14, 0.065), m["plastic"]), 0.006, 2)
    gnkit.lathe("CameraLens", [(0.012, 0.0), (0.012, 0.012)], m["lens_glass"], 16, (0, 0.162, 0.085), axis="Y")
    _export("aircraft", name, label, "drone", {"span_m": 0.62})


def balloon(name, label, colours):
    """A hot-air balloon: a gored envelope, the burner frame, a wicker
    basket, the load cables. Its origin is under the basket."""
    gnkit.reset()
    m = _mats()
    gores = [gnkit.material("Envelope %d %s" % (i, name), c, 0.7) for i, c in enumerate(colours)]
    profile = [(1.4, 4.2), (2.8, 5.8), (5.2, 8.4), (7.3, 11.6), (8.4, 14.8), (8.6, 17.0), (8.1, 19.8), (6.6, 22.4),
               (4.2, 24.2), (1.8, 25.0), (0.0, 25.2)]
    env = gnkit.lathe("Envelope", profile, gores[0], 24, (0, 0, 0), caps=False)
    gnkit.subdivide(env, 1)
    n = len(colours)
    gnkit.material_by_face(env, lambda c, nrm: int(((math.atan2(c.y, c.x) / (2 * math.pi)) % 1.0) * 24) % n, gores)
    for mat in gores:
        mat.use_backface_culling = False
    wicker = gnkit.material("Wicker", (0.45, 0.32, 0.17), 0.85)
    gnkit.bevel(box("Basket", (1.5, 1.2, 1.1), (0, 0, 0), wicker), 0.06, 3)
    gnkit.bevel(box("BasketRim", (1.56, 1.26, 0.08), (0, 0, 1.08), m["rubber"]), 0.03, 2)
    box("BurnerFrame", (1.1, 1.1, 0.05), (0, 0, 2.55), m["metal"])
    for sd in (-1, 1):
        gnkit.lathe("Burner", [(0.14, 0.0), (0.16, 0.2), (0.12, 0.35), (0.0, 0.36)], m["metal"], 16, (sd * 0.22, 0, 2.6))
    for sx in (-1, 1):
        for sy in (-1, 1):
            tube("Pole", [(sx * 0.7, sy * 0.55, 1.1), (sx * 0.52, sy * 0.52, 2.55)], 0.018, m["dark_metal"])
            tube("Cable", [(sx * 0.52, sy * 0.52, 2.6), (sx * 1.0, sy * 1.0, 4.2)], 0.008, m["rope"], verts=6)
    _export("aircraft", name, label, "balloon", {"height_m": 25.2, "diameter_m": 17.2})


def _flank_screen(name, profile, z, y0, y1, height, side, mat, rows=8, cols=32):
    """A screen wrapped onto an airship's flank between y0 and y1, height
    metres tall round the curve, reading the right way from that side."""
    def radius(y):
        for (r0, h0), (r1, h1) in zip(profile, profile[1:]):
            if h1 <= y <= h0:
                return r0 + (r1 - r0) * (h0 - y) / (h0 - h1)
        return 0.0
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")  # the name every other part uses, so a join keeps one map
    grid = []
    for i in range(cols + 1):
        u = i / cols
        y = y0 + (y1 - y0) * (u if side > 0 else 1 - u)
        r = radius(y) + 0.03
        row = []
        for j in range(rows + 1):
            v = j / rows
            a = (v - 0.5) * height / r
            row.append((bm.verts.new((side * r * math.cos(a), y, z + r * math.sin(a))), u, v))
        grid.append(row)
    for i in range(cols):
        for j in range(rows):
            quad = (grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
            f = bm.faces.new([q[0] for q in quad])
            for loop, q in zip(f.loops, quad):
                loop[uv].uv = (q[1], q[2])
    bm.normal_update()
    bm.faces.ensure_lookup_table()
    if bm.faces[0].normal.x * side < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    data = bpy.data.meshes.new(name)
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def blimp(name, label):
    """An airship: a long envelope with four tail fins, a gondola beneath,
    and a screen on each flank, the way event and sports blimps carry them.
    Its origin is under the gondola."""
    gnkit.reset()
    m = _air_mats((0.85, 0.86, 0.88), name)
    skin = gnkit.material("Blimp skin", (0.85, 0.86, 0.88), 0.5)
    length, radius, z = 40.0, 5.6, 8.2
    profile = [(0.0, 20.0), (2.0, 19.4), (3.9, 17.6), (5.2, 14.0), (5.6, 8.0), (5.5, 0.0), (4.8, -8.0), (3.4, -14.0), (1.6, -18.5),
               (0.0, -20.0)]
    gnkit.lathe("Envelope", profile, skin, 40, (0, 0, z), axis="Y")
    for k in range(4):
        fin = gnkit.prism("Fin", [(-12.5, 0.0), (-19.0, 0.0), (-19.5, 4.2), (-16.0, 4.0)], 0.2, skin)
        fin.data.transform(Matrix.Translation((0, 0, z)) @ Matrix.Rotation(math.radians(45 + 90 * k), 4, "Y")
                           @ Matrix.Translation((0, 0, 2.6)))
        gnkit.bevel(fin, 0.05, 2)
    gnkit.bevel(box("Gondola", (2.2, 8.0, 1.9), (0, 3.0, 0.9), skin), 0.4, 4)
    box("GondolaGlass", (2.22, 5.0, 0.6), (0, 3.4, 1.9), m["dark_glass"])
    gnkit.loft("GondolaNose", [((0, 7.0, 1.85), 1.1, 0.95, 3.0), ((0, 7.8, 1.9), 0.7, 0.6, 2.4), ((0, 8.2, 1.95), 0.1, 0.1)],
               m["dark_glass"], ring=20, steps=3)
    _wheel("Wheel", (0, 0.5, 0.35), 0.35, 0.2, m)
    tube("WheelStrut", [(0, 0.5, 0.4), (0, 0.8, 0.95)], 0.06, m["metal"])
    for sd in (-1, 1):
        gnkit.lathe("Engine", [(0.0, 0.8), (0.45, 0.5), (0.5, -0.6), (0.3, -1.0), (0.0, -1.1)], m["dark_metal"], 20,
                    (sd * 2.3, 1.0, 2.8), axis="Y")
        tube("Pylon", [(sd * 1.1, 1.0, 2.4), (sd * 2.2, 1.0, 2.8)], 0.08, m["metal"])
        _blades("Prop", Vector((sd * 2.3, -0.15, 2.8)), 1.1, 0.2, 3, m, axis="Y", start=20 * sd, thick=0.04)
        _flank_screen("Screen", profile, z, -9.0, 7.0, 4.2, sd, gnkit.screen_material("screen_banner", 1.2))
    _export("aircraft", name, label, "airship", {"length_m": length, "diameter_m": 2 * radius})


JOBS = [
    (speedboat, ("boat_speedboat_navy", "Bowrider speedboat, navy", (0.06, 0.12, 0.3))),
    (speedboat, ("boat_speedboat_red", "Bowrider speedboat, red", (0.6, 0.08, 0.08))),
    (yacht, ("boat_yacht", "Sailing yacht, 10 m")),
    (catamaran, ("boat_catamaran", "Sailing catamaran, 12 m")),
    (dinghy, ("boat_dinghy", "Rowing dinghy")),
    (rib, ("boat_rib", "RIB, 5.5 m")),
    (jetski, ("boat_jetski", "Jet ski", (0.1, 0.4, 0.8))),
    (tour_boat, ("boat_tour", "River tour boat, 21 m")),
    (narrowboat, ("boat_narrowboat_green", "Canal narrowboat, green", (0.1, 0.28, 0.15))),
    (narrowboat, ("boat_narrowboat_red", "Canal narrowboat, red", (0.45, 0.07, 0.07))),
    (pontoon, ("boat_pontoon", "Party pontoon")),
    (helicopter, ("heli_light_red", "Light helicopter, red", (0.55, 0.05, 0.05))),
    (helicopter, ("heli_light_white", "Light helicopter, white", (0.85, 0.86, 0.88))),
    (heavy_helicopter, ("heli_heavy_yellow", "Heavy-lift helicopter, yellow", (0.85, 0.6, 0.05))),
    (heavy_helicopter, ("heli_heavy_blue", "Heavy-lift helicopter, blue", (0.05, 0.12, 0.35))),
    (light_plane, ("plane_light", "Light plane, high wing", (0.6, 0.08, 0.06))),
    (drone, ("drone_camera", "Camera drone")),
    (balloon, ("balloon_rainbow", "Hot-air balloon, rainbow",
               [(0.8, 0.1, 0.1), (0.95, 0.5, 0.05), (0.95, 0.85, 0.1), (0.15, 0.6, 0.2), (0.1, 0.3, 0.75), (0.45, 0.15, 0.6)])),
    (balloon, ("balloon_stripes", "Hot-air balloon, stripes", [(0.9, 0.9, 0.88), (0.05, 0.15, 0.45)])),
    (blimp, ("blimp_screen", "Airship with screens")),
]


def main():
    only = os.environ.get("GN_CRAFT", "")
    for fn, args in JOBS:
        if not only or args[0].startswith(only):
            fn(*args)


main()
