"""People for Genesis, built on MakeHuman (through its Blender plugin, MPFB).

MakeHuman's body, skins, hair, eyes and clothes are CC0, so everything this
makes is ours to ship. Each person is a real MakeHuman body with randomised
proportions (gender, age, build, height, heritage), a skin to match, hair,
eyebrows, clothes and shoes, on a game-engine rig. The rig is posed here, by
aiming bones in world space (so the poses don't depend on each bone's
roll), then everything is baked to one mesh, lightened for crowds and
turned to face +Y.

Needs MPFB installed in Blender, with the MakeHuman system assets pack in its
user data (tools/setup_makehuman.py does both).

    blender --background --python tools/blender/humans.py [-- pose count]

writes genesis_assets/people/<pose>_<n>.gltf, sharing one textures/
folder so a skin used by forty people is stored once.
"""

import glob
import math
import os
import random
import sys

import addon_utils
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import gnkit  # noqa: E402

addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402
from bl_ext.user_default.mpfb.services.locationservice import LocationService  # noqa: E402

SCRIPT = "humans.py"
OUT = os.environ.get("GN_PEOPLE_OUT", os.path.join(gnkit.ASSETS, "people"))
TEXTURES = os.path.join(OUT, "textures")
DATA = LocationService.get_user_data()
# Most triangles a crowd person may have: thousands of them share a view.
TRIANGLE_BUDGET = 9000

# Arms: (abduction out to the side, flexion forward, elbow bend), degrees.
# Or a hand target: ((x to the figure's left, y forward, z up) in metres from
# the base of the neck, (pole: which way the elbow points)).
# Legs: (hip flexion forward, knee bend). "head": tilt down (+) or up (-).
POSES = {
    "standing": {"arm_l": (8, 2, 8), "arm_r": (8, 2, 8)},
    "relaxed": {"arm_l": (8, -5, 15), "arm_r": (12, 10, 70), "leg_l": (4, 6), "leg_r": (-3, 0)},
    "walking": {"arm_l": (6, 22, 20), "arm_r": (6, -20, 10), "leg_l": (-18, 6), "leg_r": (22, 12), "lean": 3},
    "cheering": {"arm_l": (35, 160, 20), "arm_r": (30, 165, 15), "head": -12},
    "fist_up": {"arm_l": (8, 0, 15), "arm_r": (15, 170, 10), "head": -8},
    "clapping": {"hand_l": ((0.03, 0.3, -0.2), (1, -0.3, -1)), "hand_r": ((-0.03, 0.3, -0.18), (-1, -0.3, -1)), "head": -5},
    "phone": {"arm_l": (10, 5, 10), "hand_r": ((-0.05, 0.3, -0.12), (-1, -0.2, -1)), "head": 20},
    "talking": {"arm_l": (10, 15, 80), "arm_r": (14, 30, 90), "leg_l": (3, 3)},
    "sitting": {"hand_l": ((0.14, 0.38, -0.5), (1, -0.5, -0.3)), "hand_r": ((-0.14, 0.38, -0.5), (-1, -0.5, -0.3)),
                "leg_l": (88, 90), "leg_r": (88, 90), "sit": True, "palms": "down"},
    "arms_crossed": {"hand_l": ((-0.1, 0.16, -0.3), (1, -0.2, -0.6)), "hand_r": ((0.1, 0.13, -0.27), (-1, -0.2, -0.6)),
                     "head": 5, "leg_l": (3, 0), "leg_r": (-4, 0)},
    "hands_on_hips": {"hand_l": ((0.19, 0.0, -0.5), (1, -0.6, 0.2)), "hand_r": ((-0.19, 0.0, -0.5), (-1, -0.6, 0.2)),
                      "leg_r": (-6, 0)},
    "facepalm": {"hand_r": ((-0.02, 0.13, 0.12), (-0.6, 0.2, -1)), "arm_l": (8, 5, 20), "head": 22},
    "exasperated": {"hand_l": ((0.08, 0.02, 0.26), (1, -0.3, 0.4)), "hand_r": ((-0.08, 0.02, 0.26), (-1, -0.3, 0.4)),
                    "head": -18},
    "shrugging": {"hand_l": ((0.36, 0.25, -0.38), (0.5, -0.4, -1)), "hand_r": ((-0.36, 0.25, -0.38), (-0.5, -0.4, -1)),
                  "head": 8},
    "pointing": {"arm_r": (18, 88, 0), "hand_l": ((0.19, 0.0, -0.5), (1, -0.6, 0.2)), "lean": 4, "leg_r": (8, 4)},
}
COUNTS = {"standing": 6, "relaxed": 4, "walking": 6, "cheering": 6, "fist_up": 4, "clapping": 4, "phone": 3,
          "talking": 4, "sitting": 6, "arms_crossed": 4, "hands_on_hips": 3, "facepalm": 3, "exasperated": 3,
          "shrugging": 3, "pointing": 3}

HAIR = {"female": ["long01", "bob01", "bob02", "ponytail01", "braid01", "afro01", "short01"],
        "male": ["short02", "short03", "short04", "short01", "afro01"]}
SUITS = {"female": ["female_casualsuit01", "female_casualsuit02", "female_sportsuit01", "female_elegantsuit01"],
         "male": ["male_casualsuit01", "male_casualsuit02", "male_casualsuit03", "male_casualsuit04",
                  "male_casualsuit05", "male_casualsuit06", "male_worksuit01", "male_elegantsuit01"]}
SHOES = ["shoes01", "shoes02", "shoes03", "shoes04", "shoes05", "shoes06"]


def _asset(kind, name, ext=".mhclo"):
    path = os.path.join(DATA, kind, name, name + ext)
    return path if os.path.exists(path) else None


def _skin_for(gender, age, heritage):
    band = "young" if age < 0.55 else ("middleage" if age < 0.8 else "old")
    name = "%s_%s_%s" % (band, heritage, gender)
    return _asset("skins", name, ".mhmat") or _asset("skins", "young_%s_%s" % (heritage, gender), ".mhmat")


def build(rng, pose_name, gender):
    body, rig, info = dress(rng, gender)
    pose(rig, POSES[pose_name])
    person = bake(pose_name)
    info["pose"] = pose_name
    return person, info


def dress(rng, gender):
    """A MakeHuman body on its game-engine rig, skinned, dressed and haired.
    Returns (body, rig, info)."""
    gnkit.reset()
    addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
    heritage = rng.choice(["african", "asian", "caucasian"])
    age = rng.uniform(0.35, 0.9)  # MakeHuman: 0.5 is 25, 1.0 is 90
    race = {"asian": 0.05, "caucasian": 0.05, "african": 0.05}
    race[heritage] = 0.9
    macro = {"gender": 0.0 if gender == "female" else 1.0, "age": age, "muscle": rng.uniform(0.35, 0.7),
             "weight": rng.uniform(0.3, 0.8), "proportions": rng.uniform(0.4, 0.8), "height": rng.uniform(0.3, 0.75),
             "cupsize": rng.uniform(0.3, 0.7), "firmness": 0.5, "race": race}
    body = HumanService.create_human(macro_detail_dict=macro)
    HumanService.add_builtin_rig(body, "game_engine")
    rig = body.parent
    skin = _skin_for(gender, age, heritage)
    if skin:
        HumanService.set_character_skin(skin, body, skin_type="GAMEENGINE")
    for kind, name in (("eyes", "low-poly"), ("eyebrows", "eyebrow%03d" % rng.randint(1, 12)),
                       ("hair", rng.choice(HAIR[gender])), ("clothes", rng.choice(SUITS[gender])),
                       ("clothes", rng.choice(SHOES))):
        path = _asset(kind, name)
        if path:
            HumanService.add_mhclo_asset(path, body, asset_type=kind.capitalize(), subdiv_levels=0)
    return body, rig, {"gender": gender, "heritage": heritage}


# --- walkers: rigged, with a looping walk --------------------------------------

# One stride: left heel down, passing, right heel down, passing; frame 32 is
# frame 0 again. At 30 fps that is a 1.07 s cycle covering about 1.4 m, a
# 1.3 m/s stroll; Genesis speeds it to match the path.
WALK_FPS = 30
WALK_KEYS = [
    (0, {"leg_l": (24, 4), "leg_r": (-16, 12), "arm_l": (6, -18, 15), "arm_r": (6, 20, 22), "bob": -0.025}),
    (8, {"leg_l": (0, 4), "leg_r": (16, 50), "arm_l": (6, 0, 12), "arm_r": (6, 2, 14), "bob": 0.012}),
    (16, {"leg_r": (24, 4), "leg_l": (-16, 12), "arm_r": (6, -18, 15), "arm_l": (6, 20, 22), "bob": -0.025}),
    (24, {"leg_r": (0, 4), "leg_l": (16, 50), "arm_r": (6, 0, 12), "arm_l": (6, 2, 14), "bob": 0.012}),
]
WALK_STRIDE_M = 1.4
WALK_CYCLE_FRAMES = 32


def _clear_pose(rig):
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()


def animate_walk(rig):
    """Keys a looping walk on the rig, as an action named "walk"."""
    rig.animation_data_create()
    action = bpy.data.actions.new("walk")
    rig.animation_data.action = action
    keys = WALK_KEYS + [(WALK_CYCLE_FRAMES, WALK_KEYS[0][1])]
    for frame, spec in keys:
        _clear_pose(rig)
        pose(rig, spec)
        pelvis = rig.pose.bones["pelvis"]
        pelvis.matrix = Matrix.Translation((0, 0, spec.get("bob", 0.0))) @ pelvis.matrix
        bpy.context.view_layer.update()
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
        pelvis.keyframe_insert("location", frame=frame)
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = WALK_CYCLE_FRAMES
    bpy.context.scene.render.fps = WALK_FPS


def bake_skinned(rig, name):
    """Like bake(), but keeps the skin: every mesh at rest (masks, shape keys
    and fitting applied, the armature not), joined, lightened, and bound to
    the rig again. The whole figure is turned to face +Y."""
    deps_meshes = [o for o in bpy.data.objects if o.type == "MESH" and not o.hide_render]
    for o in deps_meshes:
        for m in o.modifiers:
            if m.type == "ARMATURE":
                m.show_viewport = False
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    baked = []
    for o in deps_meshes:
        mesh = bpy.data.meshes.new_from_object(o.evaluated_get(deps), preserve_all_data_layers=True, depsgraph=deps)
        new = bpy.data.objects.new(o.name + "_baked", mesh)
        new.matrix_world = o.matrix_world.copy()
        bpy.context.collection.objects.link(new)
        # Vertex groups carry the skin weights; the new mesh needs them named.
        for g in o.vertex_groups:
            new.vertex_groups.new(name=g.name)
        baked.append(new)
    for o in deps_meshes:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in baked:
        o.select_set(True)
    bpy.context.view_layer.objects.active = baked[0]
    bpy.ops.object.join()
    person = bpy.context.active_object
    person.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    tris = sum(len(p.vertices) - 2 for p in person.data.polygons)
    if tris > TRIANGLE_BUDGET:
        mod = person.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = TRIANGLE_BUDGET / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_smooth()
    arm = person.modifiers.new("Armature", "ARMATURE")
    arm.object = rig
    person.parent = rig
    # Face +Y, like every model.
    rig.rotation_euler = (0, 0, math.pi)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    person.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(rotation=True)
    return person


def export_walker(person, rig, name, info):
    _share_textures(person)
    path = os.path.join(OUT, name + ".gltf")
    bpy.ops.object.select_all(action="DESELECT")
    person.select_set(True)
    rig.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", export_texture_dir="textures",
                              use_selection=True, export_animations=True, export_skins=True,
                              export_image_format="AUTO", export_force_sampling=True)
    info = dict(info)
    info.update(gnkit.license_for(SCRIPT))
    info["source"] = "Generated by tools/blender/humans.py from MakeHuman CC0 assets (via MPFB)"
    info["kind"] = "walker"
    info["animation"] = "walk"
    info["stride_m"] = WALK_STRIDE_M
    info["cycle_s"] = round(WALK_CYCLE_FRAMES / WALK_FPS, 3)
    import json
    with open(os.path.join(OUT, name + ".license.json"), "w") as f:
        json.dump(info, f, indent=2)
        f.write("\n")
    print("wrote walker", name)


# --- posing -----------------------------------------------------------------

def _pb(rig, name):
    return rig.pose.bones[name]


def _head(rig, name):
    return rig.matrix_world @ _pb(rig, name).head


def _aim(rig, name, direction):
    """Turn a pose bone so it points along a world direction."""
    pb = _pb(rig, name)
    world = rig.matrix_world @ pb.matrix
    current = (world.to_3x3() @ Vector((0, 1, 0))).normalized()
    turn = current.rotation_difference(direction.normalized()).to_matrix().to_4x4()
    at = world.translation.copy()
    pb.matrix = rig.matrix_world.inverted() @ (Matrix.Translation(at) @ turn @ Matrix.Translation(-at) @ world)
    bpy.context.view_layer.update()


def _roll(rig, name, local_axis, toward):
    """Turn a pose bone about its own length until one of its local axes
    (a palm's normal, say) faces as nearly as it can towards a direction."""
    pb = _pb(rig, name)
    world = rig.matrix_world @ pb.matrix
    along = (world.to_3x3() @ Vector((0, 1, 0))).normalized()
    have = world.to_3x3() @ Vector(local_axis)
    have = (have - along * have.dot(along)).normalized()
    want = (toward - along * toward.dot(along)).normalized()
    angle = have.angle(want)
    if have.cross(want).dot(along) < 0:
        angle = -angle
    turn = Matrix.Rotation(angle, 4, along)
    at = world.translation.copy()
    pb.matrix = rig.matrix_world.inverted() @ (Matrix.Translation(at) @ turn @ Matrix.Translation(-at) @ world)
    bpy.context.view_layer.update()


# Which local axis of the game-engine rig's hand bone is the back of the hand.
PALM_BACK = tuple(float(v) for v in os.environ.get("GN_PALM_AXIS", "1,0,0").split(","))


def pose(rig, spec):
    bpy.context.view_layer.update()
    # MakeHuman stands facing -Y; its left side is whichever way upperarm_l is.
    fwd = Vector((0, -1, 0))
    left = Vector((1 if _head(rig, "upperarm_l").x > 0 else -1, 0, 0))
    up = Vector((0, 0, 1))
    down = -up

    def local(x, y, z):
        return left * x + fwd * y + up * z

    if spec.get("lean"):
        a = math.radians(spec["lean"])
        _aim(rig, "spine_01", up * math.cos(a) + fwd * math.sin(a))
    for side, s in (("l", 1), ("r", -1)):
        flex, knee = spec.get("leg_" + side, (0, 0))
        _aim(rig, "thigh_" + side, down * math.cos(math.radians(flex)) + fwd * math.sin(math.radians(flex)))
        shin = math.radians(flex - knee)
        _aim(rig, "calf_" + side, down * math.cos(shin) + fwd * math.sin(shin))
        _aim(rig, "foot_" + side, fwd * 0.9 + down * 0.4)

        shoulder = _head(rig, "upperarm_" + side)
        a_len = (_head(rig, "lowerarm_" + side) - shoulder).length
        b_len = (_head(rig, "hand_" + side) - _head(rig, "lowerarm_" + side)).length
        if "hand_" + side in spec:
            target, pole = spec["hand_" + side]
            wrist = _head(rig, "neck_01") + local(*target)
            pole = local(*pole)
            to = wrist - shoulder
            d = min(to.length, (a_len + b_len) * 0.999)
            dirn = to.normalized()
            cos_a = max(-1.0, min(1.0, (a_len * a_len + d * d - b_len * b_len) / (2 * a_len * d)))
            across = (pole - dirn * pole.dot(dirn)).normalized()
            elbow = shoulder + dirn * a_len * cos_a + across * a_len * math.sqrt(1 - cos_a * cos_a)
            upper, fore = (elbow - shoulder).normalized(), (shoulder + dirn * d - elbow).normalized()
        else:
            abd, flx, bend = spec.get("arm_" + side, (8, 0, 10))
            a, f = math.radians(abd), math.radians(flx)
            v = Vector((s * math.sin(a), 0, -math.cos(a)))
            v = Vector((v.x, -v.z * math.sin(f), v.z * math.cos(f)))
            upper = local(*v).normalized()
            axis = upper.cross(fwd)
            if axis.length < 1e-4:
                axis = left * s
            fore = Matrix.Rotation(math.radians(bend), 3, axis.normalized()) @ upper
            if fore.dot(fwd) < upper.dot(fwd) - 0.01 and bend > 0:
                fore = Matrix.Rotation(-math.radians(bend), 3, axis.normalized()) @ upper
        _aim(rig, "upperarm_" + side, upper)
        _aim(rig, "lowerarm_" + side, fore)
        _aim(rig, "hand_" + side, fore)
        if spec.get("palms") == "down":
            _roll(rig, "hand_" + side, PALM_BACK, up)
    h = math.radians(spec.get("head", 0))
    # (A walk's hip bob is set by animate_walk, after the limbs.)
    _aim(rig, "neck_01", up * math.cos(h * 0.5) + fwd * math.sin(h * 0.5))
    _aim(rig, "head", up * math.cos(h) + fwd * math.sin(h))


# --- baking and export ------------------------------------------------------

def bake(name):
    """Everything posed, masked and fitted becomes one plain mesh, standing on
    the floor at the origin and facing +Y."""
    deps = bpy.context.evaluated_depsgraph_get()
    baked = []
    for obj in list(bpy.data.objects):
        if obj.type != "MESH" or obj.hide_render:
            continue
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(deps), preserve_all_data_layers=False, depsgraph=deps)
        new = bpy.data.objects.new(obj.name + "_baked", mesh)
        new.matrix_world = obj.matrix_world.copy()
        bpy.context.collection.objects.link(new)
        baked.append(new)
    for obj in list(bpy.data.objects):
        if obj not in baked:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in baked:
        o.select_set(True)
    bpy.context.view_layer.objects.active = baked[0]
    bpy.ops.object.join()
    person = bpy.context.active_object
    person.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    lowest = min(v.co.z for v in person.data.vertices)
    person.data.transform(Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Translation((0, 0, -lowest)))
    # Lighter for crowds, if it is over budget.
    tris = sum(len(p.vertices) - 2 for p in person.data.polygons)
    if tris > TRIANGLE_BUDGET:
        mod = person.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = TRIANGLE_BUDGET / tris
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_smooth()
    return person


def _share_textures(person):
    """Every image saved once into people/textures, at a crowd-sensible size;
    normal and AO maps dropped."""
    os.makedirs(TEXTURES, exist_ok=True)
    for mat in person.data.materials:
        if not mat or not mat.use_nodes:
            continue
        nodes = mat.node_tree.nodes
        for n in list(nodes):
            if n.type == "NORMAL_MAP" or (n.type == "TEX_IMAGE" and n.image and any(
                    k in n.image.name.lower() for k in ("normal", "_ao", "bump", "specular"))):
                nodes.remove(n)
        for n in nodes:
            if n.type != "TEX_IMAGE" or not n.image:
                continue
            img = n.image
            alpha = any(k in img.name.lower() for k in ("hair", "eyebrow", "eyelash", "short", "long", "bob",
                                                        "braid", "ponytail", "afro"))
            ext = ".png" if alpha else ".jpg"
            base = os.path.splitext(os.path.basename(img.filepath or img.name))[0]
            target = os.path.join(TEXTURES, base + ext)
            if not os.path.exists(target):
                size = 512 if alpha else 1024
                if img.size[0] > size:
                    img.scale(size, int(size * img.size[1] / max(img.size[0], 1)))
                img.filepath_raw = target
                img.file_format = "PNG" if alpha else "JPEG"
                img.save()
                # File-backed again, so the exporter copies it rather than
                # re-encoding a second copy.
                img.filepath = target
                img.reload()
            else:
                img.filepath = target
                img.reload()


def export(person, name, info):
    _share_textures(person)
    path = os.path.join(OUT, name + ".gltf")
    bpy.ops.object.select_all(action="DESELECT")
    person.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", export_texture_dir="textures",
                              use_selection=True, export_apply=True, export_image_format="AUTO")
    info = dict(info)
    info.update(gnkit.license_for(SCRIPT))
    info["source"] = "Generated by tools/blender/humans.py from MakeHuman CC0 assets (via MPFB)"
    info["triangles"] = sum(len(p.vertices) - 2 for p in person.data.polygons)
    import json
    with open(os.path.join(OUT, name + ".license.json"), "w") as f:
        json.dump(info, f, indent=2)
        f.write("\n")
    print("wrote", name, info["triangles"], "triangles")


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = args[0] if args else ""
    limit = int(args[1]) if len(args) > 1 else 0
    rng = random.Random(2026)
    if only == "walkers":
        for i in range(limit or 8):
            seed = rng.randrange(1 << 30)
            body, rig, info = dress(random.Random(seed), ("female", "male")[i % 2])
            animate_walk(rig)
            person = bake_skinned(rig, "walker_%d" % (i + 1))
            export_walker(person, rig, "walker_%d" % (i + 1), info)
        return
    for pose_name, count in COUNTS.items():
        for i in range(limit or count):
            seed = rng.randrange(1 << 30)
            if only and pose_name != only:
                continue
            # Alternate, so every pose has women and men.
            gender = ("female", "male")[(i + len(pose_name)) % 2]
            person, info = build(random.Random(seed), pose_name, gender)
            export(person, "%s_%d" % (pose_name, i + 1), info)
    # Opaque skin and clothes, cutout hair, one copy of each texture.
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
    import tidy_people
    for path in glob.glob(os.path.join(OUT, "*.gltf")):
        tidy_people.tidy(path)
    tidy_people.sweep(OUT)


main()
