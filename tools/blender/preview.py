"""Contact sheet of generated assets, for checking them by eye.

    blender --background --factory-startup --python tools/blender/preview.py -- <category> <out.png> [prefix]

Imports every GLB in genesis_assets/<category> (optionally only names
starting with prefix), lines them up in rows and renders them with the
Workbench engine in their material colours.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import gnkit  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
category, out = args[0], args[1]
prefix = args[2] if len(args) > 2 else ""

gnkit.reset()
folder = category if os.path.isdir(category) else os.path.join(gnkit.ASSETS, category)
files = sorted(f for f in os.listdir(folder) if f.endswith((".glb", ".gltf")) and f.startswith(prefix))
placed = []
for f in files:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(folder, f))
    new = [o for o in bpy.data.objects if o not in before]
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in new:
        if o.type == "MESH":
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
    placed.append((new, lo, hi))

cols = max(1, min(len(placed), math.ceil(math.sqrt(len(placed) * 1.8))))
gap = max(max(h.x - l.x, h.y - l.y) for _, l, h in placed) * 1.15
x = y = 0
tallest = 0
for i, (objs, lo, hi) in enumerate(placed):
    col, row = i % cols, i // cols
    for o in objs:
        if o.parent is None:
            o.location += Vector((col * gap - (lo.x + hi.x) / 2, -row * gap * 1.3, 0))
    tallest = max(tallest, hi.z)

bpy.ops.mesh.primitive_plane_add(size=1000)
ground = bpy.context.active_object
ground.data.materials.append(gnkit.material("Ground", (0.5, 0.5, 0.5), 1.0))

rows = math.ceil(len(placed) / cols)
width = cols * gap
depth = rows * gap * 1.3
centre = Vector(((cols - 1) * gap / 2, -(rows - 1) * gap * 1.3 / 2, tallest * 0.4))
cam_data = bpy.data.cameras.new("Cam")
cam_data.lens = 50
cam = bpy.data.objects.new("Cam", cam_data)
bpy.context.collection.objects.link(cam)
dist = max(width, depth * 1.6, tallest * 2) * 1.6
view = os.environ.get("GN_VIEW", "front")
offset = {"front": Vector((0, 0.9, 0.45)), "side": Vector((0.95, 0.25, 0.2)), "back": Vector((0, -0.9, 0.45))}[view]
cam.location = centre + offset * dist
cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
bpy.context.scene.camera = cam

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.render.resolution_x = 1800
scene.render.resolution_y = 1100
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
print("preview", out, len(placed), "assets")
