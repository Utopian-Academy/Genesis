"""Vehicles: everyday traffic, and the fleet that builds a show.

Bodies are side profiles extruded to width, with the wheel arches cut into
the profile itself, so every body sits on its wheels the way a real one does.
Glass is its own material (dark, glossy), head and tail lights glow, and each
vehicle is written once per body colour: hatchback_red, hatchback_silver...

Front faces +Y. Origin on the ground, centred on the footprint. Generic names
only: no makes, no liveries.

    blender --background --factory-startup --python tools/blender/vehicles.py
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(__file__))
import gnkit  # noqa: E402
from gnkit import box, cylinder, prism, tube  # noqa: E402

SCRIPT = "vehicles.py"
CATEGORY = "vehicles"

PAINT = {
    "red": (0.55, 0.03, 0.04), "silver": (0.62, 0.63, 0.65), "white": (0.9, 0.9, 0.88),
    "blue": (0.04, 0.1, 0.3), "black": (0.02, 0.02, 0.025), "grey": (0.22, 0.23, 0.24),
    "yellow": (0.95, 0.72, 0.05), "orange": (0.95, 0.38, 0.03), "green": (0.05, 0.25, 0.12),
    "cream": (0.85, 0.8, 0.66), "mint": (0.55, 0.8, 0.7),
}
CARS = ("red", "silver", "white", "blue")


def _paint(colour):
    """Car paint: a plain glossy base under a clear coat, not a scan."""
    mat = gnkit.material("Paint " + colour, PAINT[colour], 0.28, 0.6 if colour in ("silver", "grey") else 0.25)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Coat Weight"].default_value = 1.0
    bsdf.inputs["Coat Roughness"].default_value = 0.04
    return mat


def _glass(name, colour, alpha):
    """Car glass is dark and reflective, not milky: near-black, mirror-smooth,
    strong specular, and only partly see-through."""
    mat = gnkit.material(name, colour, 0.03, alpha=alpha)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Specular IOR Level"].default_value = 0.9
    bsdf.inputs["IOR"].default_value = 1.52
    return mat


def _mats(colour):
    pal = gnkit.palette()
    m = gnkit.material
    k = gnkit.kit_material
    pal.update({
        "body": _paint(colour),
        # Cars have cabins you can see into; big vehicles have solid bodies
        # behind their glass, so theirs stays opaque.
        "car_glass": _glass("Car glass", (0.02, 0.025, 0.03), 0.7),
        "rear_glass": _glass("Rear privacy glass", (0.012, 0.014, 0.017), 0.88),
        "coach_glass": m("Coach glass", (0.03, 0.045, 0.06), 0.05),
        "blackout": m("Blacked-out glass", (0.006, 0.006, 0.008), 0.05),
        "lens": m("Lamp lens", (0.85, 0.87, 0.9), 0.02, alpha=0.25),
        "tyre": k("rubber", "Tyre"),
        "rim": k("alu_satin", "Wheel rim"),
        "disc": k("alu_brushed", "Brake disc"),
        "trim": k("plastic_black", "Black trim"),
        "grille_mesh": k("grille", "Grille mesh"),
        "tread": k("diamond_plate", "Tread plate"),
        "head": m("Headlight", (0.9, 0.9, 0.85), 0.1, emission=(1.0, 0.97, 0.9), strength=2.5),
        "reflector": k("chrome", "Reflector"),
        "tail": m("Taillight", (0.6, 0.02, 0.02), 0.2, emission=(1.0, 0.05, 0.03), strength=2.0),
        "amber": m("Indicator amber", (0.9, 0.45, 0.02), 0.2, emission=(1.0, 0.5, 0.05), strength=1.5),
        "display": m("Destination display", (0.05, 0.04, 0.0), 0.3, emission=(1.0, 0.6, 0.05), strength=2.0),
        "chassis": k("powder_black", "Chassis"),
        "curtain": k("fabric_white", "Curtain side"),
        "canopy": k("fabric_white", "Canopy"),
        "seat": k("fabric_black", "Seat"),
        "plate": k("powder_white", "Number plate"),
        "caliper": m("Brake caliper", (0.45, 0.04, 0.03), 0.4),
        "dash": k("plastic_black", "Dashboard"),
    })
    return pal


def _export(name, label, kind, length, wheelbase, colour, extra=None):
    gnkit.join_all(name)
    info = {"label": label, "kind": kind, "colour": colour,
            "length_m": round(length, 2), "wheelbase_m": round(wheelbase, 2)}
    info.update(extra or {})
    gnkit.export(CATEGORY, name, SCRIPT, info)


def wheel(x, y, r, width, pal, outward):
    """A wheel on the axis X; `outward` (+1 or -1) is the side the rim faces.

    The tyre is lathed from a sidewall profile (bead, bulge, shoulder, tread),
    the rim is a dish with depth, five spokes stand proud of it, and a brake
    disc and caliper sit behind the spokes where they show through."""
    w = width / 2
    s = outward
    rim_r = r * 0.64
    tyre = [(rim_r, -w * 0.92), (r * 0.8, -w * 1.02), (r * 0.94, -w * 0.98), (r, -w * 0.8),
            (r, w * 0.8), (r * 0.94, w * 0.98), (r * 0.8, w * 1.02), (rim_r, w * 0.92)]
    tyre_obj = gnkit.lathe("Tyre", [(rr, x + s * h) for rr, h in tyre], pal["tyre"], segments=40,
                           centre=(0, y, r), axis="X")
    # lathe() caps any end short of the axis; a tyre's bead must stay open
    # or the cap covers the rim.
    _drop_ngons(tyre_obj)
    face = x + s * w * 0.9
    # The dish: lip at the tyre's face, falling inward to the hub mounting.
    dish = [(rim_r, 0.0), (rim_r * 0.94, -0.012), (rim_r * 0.8, -w * 0.9), (r * 0.2, -w * 1.0), (0.0, -w * 1.0)]
    gnkit.lathe("Rim", [(rr, face + s * h) for rr, h in dish], pal["rim"], segments=40,
                centre=(0, y, r), axis="X")
    cylinder("Disc", rim_r * 0.78, 0.022, (face - s * w * 1.35, y, r), pal["disc"], axis="X", verts=32)
    box("Caliper", (0.05, r * 0.28, r * 0.2), (face - s * w * 1.2, y - rim_r * 0.55, r + rim_r * 0.3), pal["caliper"])
    for k in range(5):
        a = k * 2 * math.pi / 5 + math.pi / 10
        spoke = box("Spoke", (0.022, r * 0.1, rim_r * 0.82), (0, 0, 0), pal["rim"])
        spoke.data.transform(Matrix.Rotation(-a, 4, "X"))
        spoke.data.transform(Matrix.Translation((face - s * 0.02, y, r)))
    cylinder("Hub", r * 0.12, 0.03, (face - s * 0.005, y, r), pal["rim"], axis="X", verts=16)


def _drop_ngons(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if len(f.verts) > 4], context="FACES_ONLY")
    bm.to_mesh(obj.data)
    bm.free()


def axle_pair(y, r, track, width, pal):
    for s in (-1, 1):
        wheel(s * (track / 2), y, r, width, pal, s)


def side_profile(length, clearance, axles, arch_r, wheel_r, top):
    """A body side as a polygon (y, z): bumpers, a sill with an arch cut over
    every axle, then `top` (points from the nose back to the tail)."""
    front, rear = length / 2, -length / 2
    pts = [(rear, clearance + 0.12), (rear + 0.05, clearance)]
    for ya in sorted(axles):
        t0 = math.asin(max(-1.0, min(1.0, (clearance - wheel_r) / arch_r)))
        for k in range(13):
            th = (math.pi - t0) + (t0 - (math.pi - t0)) * k / 12
            pts.append((ya + arch_r * math.cos(th), wheel_r + arch_r * math.sin(th)))
    pts += [(front - 0.05, clearance), (front, clearance + 0.12)]
    return pts + list(top)


def _from_nose(length, points):
    """Author profiles as (distance back from the nose, height)."""
    return [(length / 2 - d, z) for d, z in points]


def _shrink(points, sy, sz, floor):
    cy = sum(p[0] for p in points) / len(points)
    cz = sum(p[1] for p in points) / len(points)
    return [(cy + (y - cy) * sy, max(floor, cz + (z - cz) * sz)) for y, z in points]


# ---------------------------------------------------------------------------
# Cars
# ---------------------------------------------------------------------------

CAR_SPECS = {
    # length, width, wheel radius, wheelbase, front overhang, clearance,
    # lower body (from nose), glasshouse (from nose), doors per side
    "hatchback": dict(L=4.05, W=1.76, r=0.31, wb=2.56, fo=0.82, c=0.15,
                      body=[(0, 0.5), (0.06, 0.7), (0.85, 0.88), (3.95, 0.95), (4.05, 0.8)],
                      cabin=[(0.85, 0.88), (1.6, 1.44), (3.6, 1.42), (3.98, 0.95)], doors=2,
                      label="Hatchback"),
    "saloon": dict(L=4.78, W=1.83, r=0.32, wb=2.85, fo=0.9, c=0.15,
                   body=[(0, 0.5), (0.06, 0.72), (1.05, 0.9), (4.1, 0.99), (4.72, 0.93), (4.78, 0.76)],
                   cabin=[(1.05, 0.9), (1.85, 1.44), (3.35, 1.43), (4.08, 0.99)], doors=2,
                   label="Saloon"),
    "estate": dict(L=4.85, W=1.83, r=0.32, wb=2.85, fo=0.9, c=0.15,
                   body=[(0, 0.5), (0.06, 0.72), (1.05, 0.9), (4.75, 0.98), (4.85, 0.8)],
                   cabin=[(1.05, 0.9), (1.85, 1.46), (4.55, 1.45), (4.78, 0.98)], doors=2,
                   label="Estate car"),
    "suv": dict(L=4.7, W=1.9, r=0.37, wb=2.8, fo=0.92, c=0.22,
                body=[(0, 0.62), (0.06, 0.92), (1.0, 1.08), (4.6, 1.12), (4.7, 0.95)],
                cabin=[(1.0, 1.08), (1.7, 1.72), (4.4, 1.7), (4.64, 1.12)], doors=2,
                label="SUV"),
    "minivan": dict(L=5.0, W=1.96, r=0.34, wb=3.0, fo=0.95, c=0.17,
                    body=[(0, 0.55), (0.06, 0.8), (0.9, 1.0), (4.9, 1.05), (5.0, 0.85)],
                    cabin=[(0.9, 1.0), (1.75, 1.8), (4.85, 1.8), (4.96, 1.05)], doors=2,
                    label="Minivan"),
}


def _interp(points, d):
    """Height at distance d along a (distance, height) polyline."""
    for (d0, z0), (d1, z1) in zip(points, points[1:]):
        if d0 <= d <= d1:
            return z0 + (z1 - z0) * (d - d0) / max(d1 - d0, 1e-6)
    return points[0][1] if d < points[0][0] else points[-1][1]


def _loft(name, rings, mat):
    """Bridge a list of rings (each a closed list of (x, y, z), all the same
    length) into a shell, capped at both ends."""
    bm = bmesh.new()
    loops = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for a, b in zip(loops, loops[1:]):
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    bm.faces.new(loops[0][::-1])
    bm.faces.new(loops[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    data = bpy.data.meshes.new(name)
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def _apply(obj, kind, **props):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    mod = obj.modifiers.new(kind, kind)
    for k, v in props.items():
        setattr(mod, k, v)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def _side_x(obj, y, z, tol=0.06):
    """How far out the body's side is at (y, z): subdivision pulls a shape
    in, so details are placed on the surface as built, not as specified."""
    xs = [v.co.x for v in obj.data.vertices if abs(v.co.y - y) < tol and abs(v.co.z - z) < tol]
    return max(xs) if xs else 0.0


def _end_y(obj, z, front=True, tol=0.06, x=None):
    """Where the nose (or tail) actually is at height z: near the centreline,
    or near `x` for something off to the side, where the plan taper matters."""
    ys = [v.co.y for v in obj.data.vertices if abs(v.co.z - z) < tol
          and (abs(v.co.x) < 0.5 if x is None else abs(v.co.x - x) < 0.08)]
    if not ys:
        return 0.0
    return max(ys) if front else min(ys)


def _gaps(obj, pal, ys, belt, sill):
    """Panel gaps drawn in the paint: the side faces in a narrow band at each
    door edge take the trim material."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for y in ys:
        for edge in (y - 0.004, y + 0.004):
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, edge, 0), plane_no=(0, 1, 0))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.materials.append(pal["trim"])
    slot = len(obj.data.materials) - 1
    for poly in obj.data.polygons:
        c = poly.center
        if abs(poly.normal.x) < 0.55 or not (sill < c.z < belt):
            continue
        if any(abs(c.y - y) < 0.004 for y in ys):
            poly.material_index = slot


def _body_ring(y, half, bottom, top):
    """One cross-section of the lower body: a flat floor, the sill turning
    up, a side that bulges at the waist and draws in (tumblehome) to a
    rounded shoulder, and a gently crowned top. Mirrored, 14 points."""
    h = top - bottom
    right = [(half * 0.86, bottom), (half * 0.98, bottom + 0.05), (half, bottom + h * 0.45),
             (half * 0.985, bottom + h * 0.8), (half * 0.93, top - 0.025), (half * 0.78, top - 0.004),
             (half * 0.4, top + 0.008)]
    left = [(-x, z) for x, z in reversed(right)]
    return [(x, y, z) for x, z in right + left]


def _green_ring(y, half_bottom, half_top, bottom, top):
    """A greenhouse cross-section: glass sides leaning in to a crowned roof."""
    right = [(half_bottom, bottom), (half_bottom * 0.97, bottom + (top - bottom) * 0.5),
             (half_top, top - 0.035), (half_top * 0.8, top), (half_top * 0.35, top + 0.012)]
    left = [(-x, z) for x, z in reversed(right)]
    return [(x, y, z) for x, z in right + left]


def _shell_body(s, pal, L, W, c, yf, yr, r):
    """The lower body, lofted from nose to tail and subdivided, with the
    wheel arches cut out."""
    top_line = s["body"]
    stations = sorted(set([0.0, 0.03, 0.12, 0.35] + [d for d, _ in top_line] +
                          [L * k / 12 for k in range(1, 12)] + [L - 0.12, L - 0.03, L]))
    rings = []
    for d in stations:
        y = L / 2 - d
        end = min(d, L - d) / (L * 0.18)
        taper = 0.84 + 0.16 * min(1.0, end) ** 0.5
        bottom = c + 0.1 * max(0.0, 1 - end * 3)
        top = _interp(top_line, d)
        rings.append(_body_ring(y, W / 2 * taper, bottom, max(top, bottom + 0.12)))
    body = _loft("Body", rings, pal["body"])
    _apply(body, "SUBSURF", levels=2)
    for ya in (yf, yr):
        cut = cylinder("ArchCut", r + 0.05, W + 0.4, (0, ya, r), None, axis="X", verts=48)
        _apply(body, "BOOLEAN", object=cut, operation="DIFFERENCE", solver="EXACT")
        bpy.data.objects.remove(cut, do_unlink=True)
    gnkit.smooth(body, 40)
    return body


def _greenhouse(cabin, W, pal, top_line):
    """The cabin above the belt as a lofted shell: tinted glass where the
    windows are, body paint on the roof and the pillars, subdivided so the
    roof crowns and the glass leans in. Returns (mid, roof height).

    A ring sits on every pillar edge, and faces are coloured BEFORE
    subdividing: the colour boundaries then run along ring lines and
    subdivide into clean curves. Coloured after, they come out as stairs."""
    (ya, za), (yb, zb), (yc, zc), (yd, zd) = cabin
    half = W * 0.44
    mid = (yb + yc) / 2
    band = 0.05
    c_strip = min(0.14, (yc - yd) * 0.5)
    keys_top = [(ya, za + 0.03), (yb, zb), (mid, (zb + zc) / 2 + 0.01), (yc, zc), (yd, zd + 0.03)]
    keys_bottom = [(ya, za), (yd, zd)]

    def along(keys, y):
        pts = sorted(keys)
        for (y0, z0), (y1, z1) in zip(pts, pts[1:]):
            if y0 <= y <= y1:
                return z0 + (z1 - z0) * (y - y0) / max(y1 - y0, 1e-6)
        return pts[0][1] if y < pts[0][0] else pts[-1][1]

    ys = sorted({ya, (ya + yb) / 2, yb, mid + band, mid, mid - band, yc, yc - c_strip, yd}, reverse=True)
    rings = [_green_ring(y, half, half * 0.8, along(keys_bottom, y) - 0.04, along(keys_top, y)) for y in ys]
    shell = _loft("Greenhouse", rings, pal["car_glass"])
    shell.data.materials.append(pal["body"])
    shell.data.materials.append(pal["rear_glass"])
    for poly in shell.data.polygons:
        cy = poly.center.y
        side = abs(poly.normal.x) > 0.5
        roof = poly.normal.z > 0.75 and yc - 0.02 <= cy <= yb + 0.02
        pillar = side and (cy > yb or abs(cy - mid) < band or yc - c_strip < cy < yc)
        if roof or pillar:
            poly.material_index = 1
        elif side and cy < mid:
            poly.material_index = 2
    _apply(shell, "SUBSURF", levels=2)
    gnkit.smooth(shell, 50)
    return mid, max(zb, zc)


def _glasshouse(cabin, W, pal, width=0.84, rows=2):
    """The cabin above the belt: a see-through glass volume under a body-colour
    roof and A, B and C pillars, with seats, a dashboard and a steering wheel
    inside, so the windows show a car and not a black box.
    `cabin` is (screen base, screen top, roof rear, rear base), as (y, z)."""
    (ya, za), (yb, zb), (yc, zc), (yd, zd) = cabin
    gw = W * width
    prism("Glass", cabin, gw, pal["car_glass"])
    roof = [(yb - 0.02, zb + 0.004), (yb - 0.02, zb - 0.05), (yc + 0.02, zc - 0.05), (yc + 0.02, zc + 0.004)]
    gnkit.bevel(prism("Roof", roof, gw + 0.012, pal["body"]), 0.015)
    mid = (yb + yc) / 2
    roof_mid = zb + (zc - zb) * (mid - yb) / (yc - yb)
    for s in (-1, 1):
        x = s * (gw / 2 - 0.028)
        prism("APillar", [(ya, za), (yb, zb), (yb - 0.07, zb), (ya - 0.07, za)], 0.06, pal["body"], x=x)
        prism("CPillar", [(yd, zd), (yc, zc), (yc + 0.16, zc), (yd + 0.18, zd)], 0.06, pal["body"], x=x)
        box("BPillar", (0.06, 0.09, roof_mid - za), (x, mid, za), pal["body"])
    _cabin_inside(cabin, gw, pal, rows)
    return mid, max(zb, zc)


def _cabin_inside(cabin, gw, pal, rows=2):
    """Seats, dashboard, steering wheel and wipers for a cabin."""
    (ya, za), (yb, zb), (yc, zc), (yd, zd) = cabin
    floor = za - 0.42
    front = ya - 0.95
    for s in (-1, 1):
        gnkit.bevel(box("Seat", (0.5, 0.5, 0.13), (s * gw * 0.24, front, floor), pal["seat"]), 0.03)
        back = gnkit.bevel(box("SeatBack", (0.5, 0.12, 0.62), (s * gw * 0.24, front - 0.28, floor + 0.1),
                               pal["seat"]), 0.03)
        gnkit.rotate_about([back], "X", 12, (0, front - 0.28, floor + 0.1))
        box("Headrest", (0.26, 0.1, 0.16), (s * gw * 0.24, front - 0.37, floor + 0.74), pal["seat"])
    if rows > 1 and front - 1.0 > yd:
        gnkit.bevel(box("RearBench", (gw - 0.12, 0.5, 0.13), (0, front - 0.95, floor), pal["seat"]), 0.03)
        back = gnkit.bevel(box("RearBack", (gw - 0.12, 0.12, 0.58), (0, front - 1.22, floor + 0.1), pal["seat"]), 0.03)
        gnkit.rotate_about([back], "X", 14, (0, front - 1.22, floor + 0.1))
    gnkit.bevel(box("Dashboard", (gw - 0.04, 0.4, 0.2), (0, ya - 0.22, za - 0.2), pal["dash"]), 0.03)
    # Steering wheel on the left (-X): a ring tilted towards the driver.
    cx, cy, cz = -gw * 0.24, ya - 0.5, za + 0.02
    ring = []
    for k in range(25):
        a = 2 * math.pi * k / 24
        ring.append((cx + 0.18 * math.cos(a), cy + 0.18 * math.sin(a) * 0.45, cz + 0.18 * math.sin(a) * 0.89))
    tube("SteeringWheel", ring, 0.016, pal["dash"])
    tube("Column", [(cx, cy, cz), (cx, ya - 0.3, za - 0.08)], 0.025, pal["dash"])
    # Wipers parked along the bottom of the screen.
    for x0 in (-0.08, gw * 0.42):
        tube("Wiper", [(x0, ya + 0.01, za + 0.03), (x0 - gw * 0.36, ya - 0.05, za + 0.08)], 0.007, pal["trim"])


def _inset_lamp(body, x, y, z, w, h, facing, lit, pal, depth=0.05):
    """A lamp in a pocket: cut into the body, reflector behind, lens flush.
    `y` is where the surface is; `facing` +1 for the nose, -1 for the tail."""
    cut = box("LampCut", (w, depth * 2, h), (x, y, z - h / 2), None)
    _apply(body, "BOOLEAN", object=cut, operation="DIFFERENCE", solver="EXACT")
    bpy.data.objects.remove(cut, do_unlink=True)
    back = y - facing * depth
    box("Reflector", (w * 0.96, 0.01, h * 0.94), (x, back + facing * 0.005, z - h * 0.47), pal["reflector"])
    cylinder("Bulb", min(w, h) * 0.22, 0.03, (x, back + facing * 0.02, z), lit, axis="Y", verts=12)
    box("Lens", (w, 0.008, h), (x, y - facing * 0.006, z - h / 2), pal["lens"])


def _lamps(W, nose, tail, z_front, z_rear, pal, spread=0.33):
    """Headlights as a lens over a chrome reflector with a lit bulb; tail and
    indicator lamps."""
    for s in (-1, 1):
        x = s * W * spread
        box("Reflector", (W * 0.2, 0.03, 0.11), (x, nose - 0.1, z_front - 0.14), pal["reflector"])
        cylinder("Bulb", 0.022, 0.03, (x, nose - 0.075, z_front - 0.085), pal["head"], axis="Y", verts=12)
        box("Lens", (W * 0.21, 0.012, 0.12), (x, nose - 0.058, z_front - 0.145), pal["lens"])
        box("Indicator", (0.08, 0.035, 0.04), (s * W * 0.45, nose - 0.08, z_front - 0.19), pal["amber"])
        box("Taillight", (W * 0.18, 0.04, 0.1), (s * W * 0.36, tail + 0.03, z_rear - 0.18), pal["tail"])


def _plates(W, nose, tail, zf, zr, pal):
    """Blank plates in a recess, front and back."""
    for y, z, d in ((nose, zf, 1), (tail, zr, -1)):
        box("PlateRecess", (0.56, 0.02, 0.15), (0, y - d * 0.01, z - 0.02), pal["trim"])
        box("Plate", (0.52, 0.012, 0.11), (0, y + d * 0.002, z), pal["plate"])


def car(kind, colour, taxi=False):
    s = CAR_SPECS[kind]
    L, W, r, wb, fo, c = s["L"], s["W"], s["r"], s["wb"], s["fo"], s["c"]
    gnkit.reset()
    pal = _mats(colour)
    yf = L / 2 - fo
    yr = yf - wb
    body = _shell_body(s, pal, L, W, c, yf, yr, r)
    cabin = _from_nose(L, s["cabin"])
    belt = min(z for _, z in cabin)
    mid, roof = _greenhouse(cabin, W, pal, s["body"])
    _cabin_inside(cabin, W * 0.84, pal)
    ya, za = cabin[0]
    yc = cabin[2][0]
    _gaps(body, pal, (ya - 0.02, mid + 0.02, yc - 0.1), belt - 0.03, c + 0.14)
    for x in (-1, 1):
        for y in (mid + 0.35, mid - 0.45):
            side = _side_x(body, y, belt - 0.1)
            box("Handle", (0.012, 0.13, 0.028), (x * (side + 0.004), y, belt - 0.114), pal["trim"])
        side = _side_x(body, ya - 0.1, za - 0.04)
        box("MirrorArm", (0.1, 0.03, 0.03), (x * (side + 0.03), ya - 0.1, za), pal["trim"])
        gnkit.bevel(box("Mirror", (0.12, 0.08, 0.09), (x * (side + 0.12), ya - 0.1, za - 0.01), pal["body"]), 0.02)
    zf = s["body"][1][1]
    zt = s["body"][-2][1]
    zh = zf - 0.09
    zr = zt - 0.13
    for s_ in (-1, 1):
        _inset_lamp(body, s_ * W * 0.32, _end_y(body, zh, True, x=s_ * W * 0.32), zh, W * 0.2, 0.1, 1, pal["head"], pal)
        _inset_lamp(body, s_ * W * 0.35, _end_y(body, zr, False, x=s_ * W * 0.35), zr, W * 0.18, 0.09, -1, pal["tail"], pal)
        box("Indicator", (0.07, 0.02, 0.035), (s_ * W * 0.44, _end_y(body, zh - 0.1, True, x=s_ * W * 0.44) - 0.012, zh - 0.1),
            pal["amber"])
    grille_y = _end_y(body, c + 0.29, front=True)
    box("Grille", (W * 0.38, 0.03, 0.14), (0, grille_y - 0.01, c + 0.22), pal["grille_mesh"])
    box("GrilleFrame", (W * 0.4, 0.02, 0.16), (0, grille_y - 0.025, c + 0.21), pal["trim"])
    for y, front in ((_end_y(body, c + 0.08, True), True), (_end_y(body, c + 0.08, False), False)):
        gnkit.bevel(box("Bumper", (W * 0.9, 0.08, 0.12), (0, y - (0.03 if front else -0.03), c + 0.02),
                        pal["trim"]), 0.02)
    _plates(W, _end_y(body, c + 0.1, True) + 0.035, _end_y(body, c + 0.3, False) - 0.01, c + 0.05, c + 0.25, pal)
    axle_pair(yf, r, W - 0.24, 0.22, pal)
    axle_pair(yr, r, W - 0.24, 0.22, pal)
    name = "%s_%s" % ("taxi" if taxi else kind, colour)
    label = "%s, %s" % ("Taxi" if taxi else s["label"], colour)
    if taxi:
        # A chequer band along each side and a lit roof sign; no real livery.
        for x in (-1, 1):
            for k in range(26):
                for row in (0, 1):
                    square = pal["paint"] if (k + row) % 2 == 0 else pal["white_fabric"]
                    y = L / 2 - 1.1 - k * 0.08
                    box("Checker", (0.003, 0.08, 0.04),
                        (x * (_side_x(body, y, belt - 0.18) + 0.002), y, belt - 0.2 + row * 0.04), square)
        box("RoofSign", (0.5, 0.18, 0.13), (0, mid, roof), pal["amber"])
    _export(name, label, "taxi" if taxi else "car", L, wb, colour)


def pickup(colour):
    """A single cab and an OPEN bed: a floor below the rails, side walls, a
    tailgate, and the arches humping up inside."""
    L, W, r, wb, fo, c = 5.35, 1.92, 0.38, 3.25, 0.95, 0.25
    gnkit.reset()
    pal = _mats(colour)
    yf, yr = L / 2 - fo, L / 2 - fo - wb
    bed_floor, rail = 0.8, 1.16
    body = side_profile(L, c, (yr, yf), r + 0.05, r,
                        _from_nose(L, [(0, 0.72), (0.06, 1.02), (1.4, rail), (3.12, rail), (3.14, bed_floor),
                                       (5.35, bed_floor)]))
    gnkit.bevel(prism("Body", body, W, pal["body"]), 0.02)
    cabin = _from_nose(L, [(1.4, rail), (2.0, 1.86), (3.0, 1.86), (3.1, rail)])
    _glasshouse(cabin, W, pal, width=0.9, rows=1)
    bed_front, bed_back = L / 2 - 3.14, -L / 2
    blen = bed_front - bed_back
    for s in (-1, 1):
        gnkit.bevel(box("BedSide", (0.06, blen, rail - bed_floor),
                        (s * (W / 2 - 0.03), (bed_front + bed_back) / 2, bed_floor), pal["body"]), 0.01)
        box("RailCap", (0.08, blen, 0.02), (s * (W / 2 - 0.04), (bed_front + bed_back) / 2, rail), pal["trim"])
        gnkit.bevel(box("ArchHump", (0.3, 2 * (r + 0.05), 0.3), (s * (W / 2 - 0.2), yr, bed_floor), pal["body"]), 0.03)
        box("Mirror", (0.14, 0.08, 0.1), (s * (W * 0.45 + 0.08), cabin[0][0] - 0.1, 1.22), pal["trim"])
        box("Step", (0.14, 1.4, 0.04), (s * (W / 2 + 0.04), L / 2 - 2.3, c + 0.12), pal["tread"])
    gnkit.bevel(box("Tailgate", (W - 0.02, 0.06, rail - bed_floor), (0, bed_back + 0.03, bed_floor), pal["body"]), 0.01)
    box("BedLiner", (W - 0.12, blen - 0.08, 0.012), (0, (bed_front + bed_back) / 2, bed_floor), pal["rubber"])
    _lamps(W, L / 2, -L / 2, 1.0, 1.1, pal)
    box("Grille", (W * 0.6, 0.03, 0.28), (0, L / 2 - 0.02, 0.62), pal["grille_mesh"])
    box("Bumper", (W, 0.1, 0.18), (0, L / 2 - 0.04, c + 0.1), pal["alu"])
    box("RearBumper", (W, 0.1, 0.14), (0, -L / 2 + 0.04, c + 0.12), pal["alu"])
    _plates(W, L / 2 + 0.05, -L / 2 - 0.05, c + 0.3, c + 0.2, pal)
    axle_pair(yf, r, W - 0.26, 0.26, pal)
    axle_pair(yr, r, W - 0.26, 0.26, pal)
    _export("pickup_" + colour, "Pickup truck, " + colour, "car", L, wb, colour)


def scooter(colour):
    gnkit.reset()
    pal = _mats(colour)
    L, r, wb = 1.85, 0.28, 1.32
    yf, yr = wb / 2, -wb / 2
    for y in (yf, yr):
        cylinder("Tyre", r, 0.11, (0, y, r), pal["tyre"], axis="X", verts=24)
        cylinder("Rim", r * 0.62, 0.12, (0, y, r), pal["rim"], axis="X", verts=20)
    prism("Body", [(-0.85, 0.35), (-0.9, 0.6), (-0.3, 0.72), (0.1, 0.38), (0.35, 0.38), (0.45, 0.95),
                   (0.6, 1.0), (0.55, 0.4), (0.3, 0.3), (-0.4, 0.3)], 0.34, pal["body"])
    gnkit.bevel(box("Seat", (0.3, 0.62, 0.1), (0, -0.45, 0.72), pal["seat"]), 0.03)
    tube("Fork", [(0, yf, r), (0, 0.55, 0.95)], 0.025, pal["dark_metal"])
    tube("Bars", [(-0.35, 0.53, 1.12), (0, 0.55, 1.08), (0.35, 0.53, 1.12)], 0.016, pal["dark_metal"])
    for x in (-1, 1):
        cylinder("Grip", 0.02, 0.1, (x * 0.36, 0.53, 1.12), pal["rubber"], axis="X", verts=8)
        box("Mirror", (0.06, 0.02, 0.08), (x * 0.3, 0.5, 1.3), pal["trim"])
    box("Headlight", (0.16, 0.04, 0.1), (0, 0.62, 0.95), pal["head"])
    box("Taillight", (0.14, 0.03, 0.05), (0, -0.9, 0.62), pal["tail"])
    tube("Stand", [(0.05, -0.15, 0.3), (0.2, -0.2, 0.0)], 0.012, pal["dark_metal"])
    _export("scooter_" + colour, "Scooter, " + colour, "motorbike", L, wb, colour)


# ---------------------------------------------------------------------------
# Buses and coaches
# ---------------------------------------------------------------------------

def _round_plan_corners(obj, W, L, front_depth, front_radius, rear_radius):
    """Round a box body's corners in PLAN: bevel only the corner edges that
    run up the front and back, where a real bus is moulded round."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)

    def corner(e, front):
        a, b = e.verts
        on_sides = abs(abs(a.co.x) - W / 2) < 0.002 and abs(abs(b.co.x) - W / 2) < 0.002 and a.co.x * b.co.x > 0
        if not on_sides:
            return False
        if front:
            return a.co.y > L / 2 - front_depth and b.co.y > L / 2 - front_depth
        return a.co.y < -L / 2 + 0.2 and b.co.y < -L / 2 + 0.2

    for front, radius in ((True, front_radius), (False, rear_radius)):
        edges = [e for e in bm.edges if corner(e, front)]
        if edges:
            bmesh.ops.bevel(bm, geom=edges, offset=radius, segments=6, affect="EDGES", profile=0.5)
    bm.to_mesh(obj.data)
    bm.free()


def _cut_box(obj, size, base):
    """Cut a box (size and base as gnkit.box) out of obj."""
    cut = box("Cut", size, base, None)
    _apply(obj, "BOOLEAN", object=cut, operation="DIFFERENCE", solver="EXACT")
    bpy.data.objects.remove(cut, do_unlink=True)


def _nose_glass(shell, region_size, region_base, mat):
    """The part of the shell inside a box, made glass: it keeps the shell's
    own curves, so a screen cut this way follows the rake and wraps round the
    rounded corners on to the sides, flush, the way a coach is glazed."""
    glass = shell.copy()
    glass.data = shell.data.copy()
    shell.users_collection[0].objects.link(glass)
    region = box("Region", region_size, region_base, None)
    _apply(glass, "BOOLEAN", object=region, operation="INTERSECT", solver="EXACT")
    _apply(shell, "BOOLEAN", object=region, operation="DIFFERENCE", solver="EXACT")
    bpy.data.objects.remove(region, do_unlink=True)
    glass.data.materials.clear()
    glass.data.materials.append(mat)
    glass.name = "Windscreen"
    return glass


# How far the side glass sits back from the paint.
RECESS = 0.035


def _coach_body(L, W, H, r, c, axles, pal, win_lo, win_hi, glass, front_rake=0.25, wrap=0.5, doors=()):
    """`doors` are (y centre, length, z bottom, z top) on the kerb side (+X);
    `wrap` is how far the windscreen runs back along each side."""
    # A raked front: most of the lean in the screen, the rest in the dome.
    screen_top = H - 0.2
    body = side_profile(L, c, axles, r + 0.08, r,
                        [(L / 2, 1.0), (L / 2 - front_rake * 0.6, screen_top), (L / 2 - front_rake, H),
                         (-L / 2 + 0.1, H), (-L / 2, H - 0.15)])
    shell = prism("Body", body, W, pal["body"])
    _round_plan_corners(shell, W, L, front_rake + 0.05, 0.3, 0.15)
    gnkit.bevel(shell, 0.04)
    # A continuous band of glass down each side, set back into the body and
    # cut into panes by pillars that come out flush with the paint.
    band_len, band_y = L - 1.2, -0.2
    for x in (-1, 1):
        _cut_box(shell, (0.2, band_len, win_hi - win_lo), (x * (W / 2 + 0.1 - RECESS), band_y, win_lo))
        box("WindowBand", (0.01, band_len, win_hi - win_lo), (x * (W / 2 - RECESS + 0.005), band_y, win_lo), pal[glass])
        n = int(band_len / 1.4)
        for k in range(n + 1):
            y = band_y - band_len / 2 + k * band_len / n
            if x > 0 and any(abs(y - dy) < dl / 2 + 0.05 for dy, dl, _, _ in doors):
                continue
            box("Pillar", (RECESS, 0.09, win_hi - win_lo), (x * (W / 2 - RECESS / 2), y, win_lo), pal["trim"])
    # Doors: glass in their own recess, a little proud of the window band.
    door_glass = "blackout" if glass == "blackout" else "coach_glass"
    for dy, dl, z0, z1 in doors:
        _cut_box(shell, (0.2, dl, z1 - z0), (W / 2 + 0.1 - RECESS, dy, z0))
        box("Door", (0.01, dl, z1 - z0), (W / 2 - RECESS + 0.007, dy, z0), pal[door_glass])
        box("DoorSplit", (0.03, 0.03, z1 - z0), (W / 2 - RECESS + 0.015, dy, z0), pal["trim"])
    # The screen: the nose between the bumper line and the destination
    # display, following the rake and wrapping round the corners.
    def front_y(z):
        return L / 2 - front_rake * 0.6 * (z - 1.0) / (screen_top - 1.0)
    z0, z1 = 1.1, screen_top - 0.12
    _nose_glass(shell, (W + 1.0, wrap + 2.0, z1 - z0), (0, L / 2 - wrap + (wrap + 2.0) / 2, z0), pal[glass])
    box("RearWindow", (W - 0.3, 0.02, 0.7), (0, -L / 2 - 0.004, H - 1.0), pal[glass])
    box("Display", (W - 0.9, 0.03, 0.2), (0, front_y(screen_top - 0.08) - 0.01, screen_top - 0.1), pal["display"])
    for x in (-1, 1):
        box("Headlight", (0.3, 0.04, 0.12), (x * (W / 2 - 0.45), L / 2 + 0.005, 0.55), pal["head"])
        box("Taillight", (0.1, 0.04, 0.45), (x * (W / 2 - 0.1), -L / 2 - 0.01, 0.9), pal["tail"])
        box("Mirror", (0.08, 0.35, 0.28), (x * (W / 2 + 0.18), L / 2 + 0.05, H - 0.9), pal["trim"])
        tube("MirrorArm", [(x * (W / 2 - 0.05), L / 2 - 0.1, H - 0.4), (x * (W / 2 + 0.18), L / 2 + 0.2, H - 0.45),
                           (x * (W / 2 + 0.18), L / 2 + 0.2, H - 0.62)], 0.015, pal["trim"])
    box("Bumper", (W, 0.1, 0.35), (0, L / 2 - 0.02, c), pal["trim"])
    box("RearBumper", (W, 0.1, 0.3), (0, -L / 2 + 0.02, c), pal["trim"])
    for y in axles:
        axle_pair(y, r, W - 0.35, 0.3, pal)


def city_bus(colour):
    L, W, H, r, c = 12.0, 2.55, 3.05, 0.5, 0.3
    gnkit.reset()
    pal = _mats(colour)
    yf = L / 2 - 2.65
    yr = yf - 5.95
    # Doors on the kerb side (+X): glass, full height, front and middle.
    _coach_body(L, W, H, r, c, (yr, yf), pal, 1.15, 2.65, "coach_glass", front_rake=0.3, wrap=0.4,
                doors=[(y, 1.2, 0.35, 2.75) for y in (L / 2 - 1.1, 0.2)])
    _export("bus_city_" + colour, "City bus, " + colour, "bus", L, yf - yr, colour)


def coach(colour, tour=False):
    L, W, H, r, c = (13.7, 2.55, 3.95, 0.52, 0.32) if tour else (12.2, 2.55, 3.6, 0.52, 0.32)
    gnkit.reset()
    pal = _mats(colour)
    yf = L / 2 - 2.7
    yd = yf - (7.0 if tour else 6.1)
    axles = (yd - 1.35, yd, yf)
    door = [(L / 2 - 1.25, 1.0, 0.4, 2.9)]
    if tour:
        # A sleeper: the whole upper deck blacked out, a lower window strip too.
        _coach_body(L, W, H, r, c, axles, pal, 1.6, H - 0.2, "blackout", front_rake=0.45, doors=door)
    else:
        _coach_body(L, W, H, r, c, axles, pal, 1.9, 3.3, "coach_glass", front_rake=0.6, doors=door)
    for x in (-1, 1):
        # Luggage bays under the floor.
        for k in range(3):
            y = yd + 1.0 + k * 1.6
            box("BaySeam", (0.006, 1.5, 0.006), (x * (W / 2 + 0.002), y, 1.45), pal["trim"])
            box("BaySeam", (0.006, 0.006, 0.9), (x * (W / 2 + 0.002), y - 0.75, 0.55), pal["trim"])
    if tour:
        box("RoofAC", (1.6, 2.4, 0.2), (0, 0.5, H), pal["body"])
        name, label, kind = "bus_tour_" + colour, "Tour bus (sleeper coach), " + colour, "tour_bus"
    else:
        name, label, kind = "coach_" + colour, "Coach, " + colour, "coach"
    _export(name, label, kind, L, yf - yd, colour)


# ---------------------------------------------------------------------------
# Trucks
# ---------------------------------------------------------------------------

def _cab(y_front, W, H, depth, floor, pal, sleeper=False):
    """A cab-over truck cab: the front at y_front, `depth` long."""
    back = y_front - depth
    gnkit.bevel(box("Cab", (W, depth, H - floor), (0, y_front - depth / 2, floor), pal["body"]), 0.05)
    box("Windscreen", (W - 0.2, 0.02, (H - floor) * 0.4), (0, y_front + 0.004, floor + (H - floor) * 0.45), pal["coach_glass"])
    for x in (-1, 1):
        box("SideWindow", (0.02, depth * 0.45, (H - floor) * 0.33),
            (x * (W / 2 + 0.004), y_front - depth * 0.3, floor + (H - floor) * 0.5), pal["coach_glass"])
        box("Headlight", (0.3, 0.04, 0.12), (x * (W / 2 - 0.3), y_front + 0.005, floor + 0.1), pal["head"])
        box("Mirror", (0.08, 0.2, 0.35), (x * (W / 2 + 0.22), y_front + 0.05, floor + (H - floor) * 0.55), pal["trim"])
        tube("MirrorArm", [(x * (W / 2), y_front - 0.1, floor + (H - floor) * 0.75),
                           (x * (W / 2 + 0.22), y_front + 0.05, floor + (H - floor) * 0.75)], 0.015, pal["trim"])
        box("Step", (0.3, 0.4, 0.04), (x * (W / 2 - 0.1), y_front - 0.45, floor - 0.45), pal["alu"])
    box("Grille", (W * 0.7, 0.02, (H - floor) * 0.25), (0, y_front + 0.004, floor + 0.2), pal["trim"])
    box("Bumper", (W, 0.15, 0.35), (0, y_front, floor - 0.35), pal["trim"])
    if sleeper:
        box("RoofFairing", (W - 0.2, depth * 0.7, 0.6), (0, back + depth * 0.4, H), pal["body"])
    return back


def box_truck(colour):
    L, W, r, wb = 8.4, 2.45, 0.45, 4.3
    gnkit.reset()
    pal = _mats(colour)
    front = L / 2
    yf = front - 1.2
    yr = yf - wb
    back = _cab(front, W - 0.1, 2.75, 1.7, 1.05, pal)
    box("Chassis", (0.9, L - 0.6, 0.25), (0, -0.2, 0.75), pal["chassis"])
    body_len = back - 0.1 - (-L / 2)
    gnkit.bevel(box("Box", (W, body_len, 2.5), (0, -L / 2 + body_len / 2, 1.1), pal["white_fabric"]), 0.02)
    box("RearDoorSeam", (0.01, 0.02, 2.4), (0, -L / 2 - 0.005, 1.15), pal["trim"])
    for x in (-1, 1):
        box("Taillight", (0.2, 0.04, 0.1), (x * (W / 2 - 0.2), -L / 2 - 0.01, 0.95), pal["tail"])
        box("SideGuard", (0.03, yf - yr - 1.5, 0.25), (x * (W / 2 - 0.1), (yf + yr) / 2, 0.45), pal["alu"])
    box("TailLift", (W - 0.1, 0.12, 0.35), (0, -L / 2 - 0.06, 0.6), pal["dark_metal"])
    axle_pair(yf, r, W - 0.3, 0.3, pal)
    axle_pair(yr, r, W - 0.5, 0.55, pal)
    _export("truck_box_7t5_" + colour, "7.5 t box truck, " + colour, "truck", L, wb, colour)


def articulated(colour):
    """Tractor unit coupled to a 13.6 m curtain-side trailer."""
    gnkit.reset()
    pal = _mats(colour)
    W, r = 2.5, 0.5
    trailer_len, tractor_len = 13.6, 6.0
    L = 16.5
    front = L / 2
    t_yf = front - 1.35
    t_yr1, t_yr2 = t_yf - 3.6, t_yf - 4.95
    _cab(front, W, 3.8, 2.3, 1.3, pal, sleeper=True)
    box("Chassis", (0.9, tractor_len - 0.5, 0.3), (0, front - tractor_len / 2 - 0.1, 0.8), pal["chassis"])
    box("FifthWheel", (1.2, 1.0, 0.12), (0, t_yr1 - 0.55, 1.1), pal["dark_metal"])
    for x in (-1, 1):
        cylinder("FuelTank", 0.3, 1.2, (x * (W / 2 - 0.35), t_yf - 2.0, 0.75), pal["alu"], axis="Y", verts=16)
        tube("Exhaust", [(x * 0.95, front - 2.35, 1.4), (x * 0.95, front - 2.35, 4.0)], 0.07, pal["alu"])
    for y in (t_yf, t_yr1, t_yr2):
        axle_pair(y, r, W - 0.35, 0.3 if y == t_yf else 0.55, pal)
    # The trailer: its kingpin sits over the fifth wheel, ~1.6 m back from its nose.
    tf = t_yr1 - 0.55 + 1.6
    tb = tf - trailer_len
    gnkit.bevel(box("Trailer", (W + 0.05, trailer_len, 2.75), (0, (tf + tb) / 2, 1.25), pal["curtain"]), 0.02)
    box("TrailerRoof", (W + 0.07, trailer_len + 0.02, 0.06), (0, (tf + tb) / 2, 4.0), pal["alu"])
    box("TrailerFloor", (W + 0.07, trailer_len + 0.02, 0.15), (0, (tf + tb) / 2, 1.1), pal["alu"])
    for x in (-1, 1):
        for k in range(1, 28):
            box("Strap", (0.006, 0.05, 2.6), (x * (W / 2 + 0.03), tb + k * trailer_len / 28, 1.3), pal["trim"])
        box("Taillight", (0.3, 0.04, 0.12), (x * (W / 2 - 0.25), tb - 0.01, 0.95), pal["tail"])
        box("LandingLeg", (0.12, 0.12, 0.95), (x * 0.9, tf - 2.5, 0.15), pal["dark_metal"])
        box("LegFoot", (0.25, 0.25, 0.04), (x * 0.9, tf - 2.5, 0.12), pal["dark_metal"])
    for k in range(3):
        axle_pair(tb + 1.3 + k * 1.31, r, W - 0.35, 0.55, pal)
    box("RearBar", (W, 0.1, 0.12), (0, tb - 0.1, 0.55), pal["dark_metal"])
    _export("truck_artic_" + colour, "Articulated truck with 13.6 m trailer, " + colour, "truck",
            front - tb + 0.1, t_yf - t_yr1, colour)


def ob_van(colour):
    """A production (OB) truck: windowless body, roof platform and dish, side door and steps."""
    L, W, r, wb = 9.2, 2.5, 0.48, 5.0
    gnkit.reset()
    pal = _mats(colour)
    front = L / 2
    yf = front - 1.3
    yr = yf - wb
    back = _cab(front, W - 0.05, 2.9, 1.8, 1.1, pal)
    box("Chassis", (0.9, L - 0.6, 0.25), (0, -0.2, 0.75), pal["chassis"])
    body_len = back - 0.05 + L / 2
    gnkit.bevel(box("Body", (W, body_len, 2.75), (0, -L / 2 + body_len / 2, 1.05), pal["body"]), 0.03)
    top = 3.8
    for x in (-1, 1):
        tube("RoofRail", [(x * (W / 2 - 0.05), -L / 2 + 0.2, top + 0.4), (x * (W / 2 - 0.05), back - 0.2, top + 0.4)],
             0.02, pal["alu"])
        for k in range(6):
            y = -L / 2 + 0.2 + k * (body_len - 0.4) / 5
            tube("RailPost", [(x * (W / 2 - 0.05), y, top), (x * (W / 2 - 0.05), y, top + 0.4)], 0.015, pal["alu"])
    box("RoofDeck", (W - 0.1, body_len - 0.2, 0.03), (0, -L / 2 + body_len / 2, top), pal["deck"])
    dish = cylinder("Dish", 0.6, 0.12, (0, 0, 0), pal["white_fabric"], verts=32, radius2=0.1)
    gnkit.rotate_about([dish], "X", 60, (0, 0, 0))
    dish.data.transform(Matrix.Translation((0, -L / 2 + 1.2, top + 1.0)))
    cylinder("DishMount", 0.06, 0.8, (0, -L / 2 + 1.2, top + 0.4), pal["dark_metal"], verts=10)
    for k in range(2):
        box("AirCon", (0.9, 0.7, 0.35), (0, back - 0.8 - k * 1.0, top + 0.03), pal["dark_metal"])
    box("SideDoor", (0.02, 0.9, 2.0), (W / 2 + 0.01, -0.5, 1.2), pal["trim"])
    for k in range(3):
        box("Step", (0.4, 0.8, 0.03), (W / 2 + 0.22 + k * 0.0, -0.5, 0.95 - k * 0.3), pal["alu"])
    box("CableHatch", (0.02, 0.6, 0.4), (W / 2 + 0.01, -L / 2 + 0.8, 1.3), pal["dark_metal"])
    for x in (-1, 1):
        box("Taillight", (0.2, 0.04, 0.1), (x * (W / 2 - 0.2), -L / 2 - 0.01, 0.95), pal["tail"])
        box("Stabiliser", (0.1, 0.1, 0.75), (x * (W / 2 - 0.3), -L / 2 + 0.4, 0.0), pal["yellow"])
    axle_pair(yf, r, W - 0.3, 0.3, pal)
    axle_pair(yr, r, W - 0.5, 0.55, pal)
    _export("ob_van_" + colour, "Production (OB) truck, " + colour, "ob_van", L, wb, colour)


def generator(colour):
    """A containerised 500 kVA-class generator on a tandem-axle trailer."""
    gnkit.reset()
    pal = _mats(colour)
    L, W, r = 6.6, 2.3, 0.36
    cont_len, cont_w, cont_h = 4.6, 2.2, 2.3
    back = -L / 2
    deck = 0.75
    box("Chassis", (1.5, cont_len + 0.2, 0.2), (0, back + cont_len / 2 + 0.1, deck - 0.2), pal["chassis"])
    gnkit.bevel(box("Container", (cont_w, cont_len, cont_h), (0, back + cont_len / 2 + 0.1, deck), pal["body"]), 0.02)
    for x in (-1, 1):
        gnkit.grid("Louvre", 1, 10, (1.0, 0.03), 0.04, (x * (cont_w / 2 + 0.005), back + 0.7, deck + 0.4),
                   pal["trim"], 0.01, axis="Y")
        gnkit.grid("Louvre", 1, 10, (1.0, 0.03), 0.04, (x * (cont_w / 2 + 0.005), back + 3.7, deck + 0.4),
                   pal["trim"], 0.01, axis="Y")
        for y in (back + 1.9, back + 3.1):
            box("DoorSeam", (0.006, 0.006, cont_h - 0.2), (x * (cont_w / 2 + 0.003), y, deck + 0.1), pal["trim"])
        box("Taillight", (0.18, 0.04, 0.08), (x * (W / 2 - 0.15), back - 0.01, deck - 0.1), pal["tail"])
        box("Mudguard", (0.3, 1.9, 0.06), (x * (W / 2 - 0.15), back + 1.8, 0.8), pal["dark_metal"])
    cylinder("Exhaust", 0.1, 0.9, (0.5, back + 1.0, deck + cont_h + 0.45), pal["metal"], verts=16)
    box("ControlPanel", (0.6, 0.02, 0.5), (0.4, back + 0.1 - 0.012, deck + 1.0), pal["screen"])
    front = back + cont_len + 0.2
    tube("Drawbar", [(-0.7, front, deck - 0.15), (0, L / 2 - 0.2, deck - 0.2), (0.7, front, deck - 0.15)], 0.05,
         pal["chassis"])
    box("Hitch", (0.14, 0.3, 0.12), (0, L / 2 - 0.15, deck - 0.26), pal["dark_metal"])
    cylinder("JockeyWheel", 0.1, 0.07, (0, L / 2 - 0.6, 0.1), pal["tyre"], axis="X", verts=12)
    tube("JockeyPost", [(0, L / 2 - 0.6, 0.1), (0, L / 2 - 0.6, deck - 0.2)], 0.03, pal["dark_metal"])
    y1, y2 = back + 1.4, back + 2.2
    for y in (y1, y2):
        axle_pair(y, r, W - 0.25, 0.2, pal)
    _export("generator_trailer_" + colour, "Generator trailer, 500 kVA, " + colour, "generator", L, y2 - y1, colour)


# ---------------------------------------------------------------------------
# Site vehicles
# ---------------------------------------------------------------------------

def scissor_lift(colour, height=4.0):
    """A slab scissor lift with its platform raised to `height`."""
    gnkit.reset()
    pal = _mats(colour)
    L, W, r = 2.5, 1.2, 0.2
    gnkit.bevel(box("Chassis", (W, L, 0.5), (0, 0, 0.1), pal["body"]), 0.02)
    for x in (-1, 1):
        box("Pothole", (0.04, L - 0.7, 0.06), (x * (W / 2 + 0.02), 0, 0.12), pal["dark_metal"])
    levels = 4
    step = (height - 0.7) / levels
    for x in (-1, 1):
        for k in range(levels):
            z0 = 0.62 + k * step
            tube("Scissor", [(x * 0.48, -1.0, z0), (x * 0.48, 1.0, z0 + step)], 0.035, pal["body"])
            tube("Scissor", [(x * 0.52, -1.0, z0 + step), (x * 0.52, 1.0, z0)], 0.035, pal["body"])
    box("Platform", (W + 0.05, L + 0.1, 0.12), (0, 0, height), pal["deck"])
    rails = [(-W / 2, -L / 2), (W / 2, -L / 2), (W / 2, L / 2), (-W / 2, L / 2)]
    for (xa, ya) in rails:
        tube("Post", [(xa, ya, height + 0.12), (xa, ya, height + 1.22)], 0.02, pal["yellow"])
    for z in (height + 0.62, height + 1.22):
        tube("Rail", [(x, y, z) for x, y in rails + rails[:1]], 0.02, pal["yellow"])
    box("ControlBox", (0.35, 0.12, 0.25), (0, L / 2 - 0.1, height + 0.95), pal["dark_metal"])
    for y in (-0.8, 0.8):
        axle_pair(y, r, W - 0.1, 0.14, pal)
    _export("lift_scissor_" + colour, "Scissor lift, " + colour, "mewp", L, 1.6, colour,
            {"platform_height_m": height})


def boom_lift(colour):
    """A telescopic boom lift, boom raised, basket at the tip."""
    gnkit.reset()
    pal = _mats(colour)
    L, W, r = 3.0, 2.3, 0.42
    gnkit.bevel(box("Chassis", (W - 0.2, L, 0.5), (0, 0, 0.35), pal["body"]), 0.03)
    cylinder("Turntable", 0.8, 0.12, (0, -0.2, 0.9), pal["dark_metal"], verts=24)
    gnkit.bevel(box("Turret", (1.4, 1.8, 0.9), (0, -0.4, 0.96), pal["body"]), 0.04)
    box("Counterweight", (1.5, 0.5, 0.8), (0, -1.3, 1.0), pal["dark_metal"])
    # Three telescoping sections, each built along +Y, tilted up about the
    # pivot and moved there: rotate_about pivots on an explicit point, so
    # nothing depends on where an object's origin was left.
    pivot = (0.0, -0.2, 1.9)
    angle = 50
    length = 9.0
    along = (0.0, math.cos(math.radians(angle)), math.sin(math.radians(angle)))
    start = 0.0
    for w, frac, mat in ((0.42, 0.36, pal["body"]), (0.34, 0.33, pal["alu"]), (0.27, 0.31, pal["alu"])):
        seg_len = length * (frac + 0.04)
        seg = box("Boom", (w, seg_len, w), (0, seg_len / 2, -w / 2), mat)
        gnkit.rotate_about([seg], "X", angle, (0, 0, 0))
        seg.data.transform(Matrix.Translation(tuple(pivot[i] + along[i] * length * start for i in range(3))))
        start += frac
    tip = tuple(pivot[i] + along[i] * length for i in range(3))
    tube("Jib", [tip, (0, tip[1] + 0.6, tip[2] - 0.2)], 0.06, pal["dark_metal"])
    bx, by, bz = 0, tip[1] + 0.9, tip[2] - 1.2
    box("Basket", (1.8, 0.8, 0.12), (bx, by, bz), pal["dark_metal"])
    corners = [(-0.9, -0.4), (0.9, -0.4), (0.9, 0.4), (-0.9, 0.4)]
    for x, y in corners:
        tube("Post", [(x, by + y, bz + 0.12), (x, by + y, bz + 1.22)], 0.02, pal["yellow"])
    for z in (bz + 0.62, bz + 1.22):
        tube("Rail", [(x, by + y, z) for x, y in corners + corners[:1]], 0.02, pal["yellow"])
    for y in (-0.95, 0.95):
        axle_pair(y, r, W - 0.3, 0.3, pal)
    _export("lift_boom_" + colour, "Boom lift, " + colour, "mewp", L, 1.9, colour,
            {"platform_height_m": round(bz, 1)})


def forklift(colour):
    gnkit.reset()
    pal = _mats(colour)
    L, W = 2.4, 1.15
    gnkit.bevel(box("Body", (W, 1.6, 0.9), (0, -0.25, 0.2), pal["body"]), 0.04)
    gnkit.bevel(box("Counterweight", (W, 0.5, 0.85), (0, -0.95, 0.15), pal["dark_metal"]), 0.06)
    box("Seat", (0.5, 0.45, 0.35), (0, -0.4, 1.1), pal["seat"])
    guard = [(-0.5, -0.75), (0.5, -0.75), (0.5, 0.35), (-0.5, 0.35)]
    for x, y in guard:
        tube("GuardPost", [(x, y, 1.0), (x, y, 2.15)], 0.03, pal["dark_metal"])
    box("GuardRoof", (1.05, 1.15, 0.05), (0, -0.2, 2.15), pal["dark_metal"])
    for k in range(5):
        box("GuardSlat", (1.0, 0.03, 0.03), (0, -0.7 + k * 0.25, 2.2), pal["dark_metal"])
    tube("Steering", [(0, 0.2, 1.1), (0, 0.05, 1.45)], 0.02, pal["dark_metal"])
    cylinder("Wheel", 0.17, 0.03, (0, 0.03, 1.47), pal["rubber"], verts=16)
    for x in (-0.35, 0.35):
        box("Mast", (0.08, 0.12, 2.3), (x, 0.65, 0.1), pal["dark_metal"])
    box("Carriage", (0.9, 0.06, 0.45), (0, 0.74, 0.15), pal["dark_metal"])
    for x in (-0.25, 0.25):
        box("Fork", (0.1, 1.1, 0.04), (x, 1.3, 0.08), pal["dark_metal"])
        box("ForkHeel", (0.1, 0.05, 0.4), (x, 0.77, 0.08), pal["dark_metal"])
    box("Taillight", (0.1, 0.03, 0.06), (0.4, -1.21, 0.85), pal["tail"])
    box("Beacon", (0.1, 0.1, 0.08), (0, -0.7, 2.2), pal["amber"])
    for x in (-1, 1):
        wheel(x * 0.47, 0.35, 0.3, 0.22, pal, x)
        wheel(x * 0.44, -0.75, 0.24, 0.18, pal, x)
    _export("forklift_" + colour, "Forklift, " + colour, "forklift", L, 1.1, colour)


def golf_buggy(colour):
    gnkit.reset()
    pal = _mats(colour)
    L, W, r, wb = 2.4, 1.2, 0.22, 1.65
    prism("Body", [(1.2, 0.3), (1.2, 0.55), (0.95, 0.75), (0.55, 0.78), (0.45, 0.35), (-1.2, 0.35),
                   (-1.2, 0.6), (-0.9, 0.62), (-0.85, 0.3)], W, pal["body"])
    box("Floor", (W - 0.1, 1.5, 0.05), (0, -0.1, 0.28), pal["rubber"])
    gnkit.bevel(box("SeatBase", (W - 0.1, 0.55, 0.35), (0, -0.45, 0.33), pal["body"]), 0.03)
    gnkit.bevel(box("Seat", (W - 0.15, 0.5, 0.1), (0, -0.45, 0.68), pal["seat"]), 0.03)
    back = gnkit.bevel(box("Backrest", (W - 0.15, 0.1, 0.4), (0, -0.72, 0.78), pal["seat"]), 0.03)
    gnkit.rotate_about([back], "X", 12, (0, -0.72, 0.78))
    for x in (-1, 1):
        tube("CanopyPost", [(x * 0.55, 0.55, 0.75), (x * 0.52, 0.45, 1.85)], 0.02, pal["dark_metal"])
        tube("CanopyPost", [(x * 0.55, -0.8, 0.6), (x * 0.52, -0.8, 1.85)], 0.02, pal["dark_metal"])
        box("Headlight", (0.12, 0.03, 0.06), (x * 0.4, 1.2, 0.45), pal["head"])
        box("Taillight", (0.08, 0.03, 0.05), (x * 0.45, -1.2, 0.45), pal["tail"])
    gnkit.bevel(box("Roof", (W + 0.1, 1.7, 0.05), (0, -0.15, 1.85), pal["canopy"]), 0.02)
    box("Windscreen", (1.05, 0.01, 0.75), (0, 0.5, 1.05), pal["car_glass"])
    tube("SteeringColumn", [(0.25, 0.45, 0.6), (0.25, 0.25, 1.0)], 0.018, pal["dark_metal"])
    cylinder("SteeringWheel", 0.16, 0.03, (0.25, 0.23, 1.02), pal["rubber"], verts=16)
    box("BagRack", (W - 0.2, 0.35, 0.3), (0, -1.05, 0.62), pal["dark_metal"])
    axle_pair(wb / 2 - 0.05, r, W - 0.15, 0.18, pal)
    axle_pair(-wb / 2 - 0.05, r, W - 0.15, 0.18, pal)
    _export("golf_buggy_" + colour, "Golf buggy, " + colour, "buggy", L, wb, colour)


def main():
    for kind in CAR_SPECS:
        for colour in CARS:
            car(kind, colour)
    for colour in CARS:
        pickup(colour)
    for colour in ("yellow", "black", "white"):
        car("saloon", colour, taxi=True)
    for colour in ("red", "white", "black", "mint"):
        scooter(colour)
    for colour in ("red", "white", "green"):
        city_bus(colour)
    for colour in ("white", "silver", "blue"):
        coach(colour)
    for colour in ("black", "silver", "white"):
        coach(colour, tour=True)
    for colour in ("white", "silver", "red"):
        box_truck(colour)
    for colour in ("white", "blue", "red"):
        articulated(colour)
    for colour in ("white", "black", "silver"):
        ob_van(colour)
    for colour in ("white", "grey", "green"):
        generator(colour)
    for colour in ("orange", "blue", "yellow"):
        scissor_lift(colour)
        boom_lift(colour)
    for colour in ("yellow", "red", "orange"):
        forklift(colour)
    for colour in ("white", "green", "cream"):
        golf_buggy(colour)


main()
