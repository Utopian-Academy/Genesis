"""A close look at kit models, the way a render camera sees them: a 50 mm
lens a few metres away, lit by a real sky, in EEVEE. Contact sheets are too
small and too flat to judge quality; this is the check before calling a
model finished.

    blender --background --factory-startup --python tools/blender/closeup.py -- out.png model.gltf [model2 ...]

Several models are lined up side by side; the camera frames them all.
GN_VIEW=back|side moves the camera, GN_FLOOR=none drops the floor, GN_ZMAX
crops the framing to a height.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import gnkit  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
out, models = args[0], args[1:]
gnkit.reset()

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1600
scene.render.resolution_y = 1000
scene.view_settings.view_transform = "AgX"
world = bpy.data.worlds.new("Sky")
world.use_nodes = True
env = world.node_tree.nodes.new("ShaderNodeTexEnvironment")
env.image = bpy.data.images.load(os.path.join(gnkit.ROOT, "genesis_data", "external", "skies", "overcast.hdr"))
world.node_tree.links.new(env.outputs["Color"], world.node_tree.nodes["Background"].inputs["Color"])
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
scene.world = world
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(50), 0, math.radians(35))
bpy.context.collection.objects.link(sun)

x = 0.0
lo = Vector((1e9, 1e9, 1e9))
hi = -lo
for path in models:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    a = Vector((1e9, 1e9, 1e9))
    b = -a
    for o in new:
        if o.type == "MESH":
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                a = Vector(map(min, a, w))
                b = Vector(map(max, b, w))
    shift = Vector((x - a.x, -(a.y + b.y) / 2, 0))
    for o in new:
        if o.parent is None:
            o.location += shift
    lo = Vector(map(min, lo, a + shift))
    hi = Vector(map(max, hi, b + shift))
    x += (b.x - a.x) + max(0.3, (b.x - a.x) * 0.25)

# GN_FLOOR=none leaves the floor out, to see a boat's hull below its waterline.
if os.environ.get("GN_FLOOR") != "none":
    bpy.ops.mesh.primitive_plane_add(size=200)
    bpy.context.active_object.data.materials.append(gnkit.kit_material("powder_grey", "Floor"))
# GN_ZMAX frames only up to that height (a yacht's hull, not its mast).
if os.environ.get("GN_ZMAX"):
    hi.z = min(hi.z, float(os.environ["GN_ZMAX"]))

centre = (lo + hi) / 2
size = max(hi.x - lo.x, hi.z - lo.z, hi.y - lo.y)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.data.lens = 50
bpy.context.collection.objects.link(cam)
# Three-quarter front view: the models face +Y.
dist = size * 1.25 + 0.6
# GN_VIEW=back looks from behind: the operator's side of a console.
view = os.environ.get("GN_VIEW", "")
if view == "side":
    cam.location = centre + Vector((dist * 1.0, dist * 0.08, dist * 0.12))
else:
    side = -1.0 if view == "back" else 1.0
    cam.location = centre + Vector((dist * 0.45, side * dist * 0.85, dist * 0.35))
cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
print("closeup", out)
