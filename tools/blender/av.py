"""AV and broadcast: cameras and their supports, projectors and screens,
microphones, lecterns, prompters.

Nicknamed after the class of product each stands for, never a real brand or
model number. Cameras and projectors face +Y: the way they shoot or throw.

    blender --background --factory-startup --python tools/blender/av.py
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import gnkit  # noqa: E402
from gnkit import box, cylinder, sphere, tube  # noqa: E402

SCRIPT = "av.py"
CATEGORY = "av"


def _export(name, label, kind, extra=None):
    gnkit.join_all(name)
    info = {"label": label, "kind": kind}
    info.update(extra or {})
    gnkit.export(CATEGORY, name, SCRIPT, info)


def _tripod(pal, height, spread=0.45, head=True, dolly=False):
    """Broadcast legs: two-stage legs with a spreader, fluid head on top."""
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 2
        foot = (math.cos(a) * spread, math.sin(a) * spread, 0.03 if dolly else 0.0)
        tube("Leg", [(math.cos(a) * 0.05, math.sin(a) * 0.05, height - 0.05), foot], 0.014, pal["dark_metal"])
        tube("LegInner", [(math.cos(a) * 0.07, math.sin(a) * 0.07, height - 0.1),
                          (foot[0] * 0.98 + math.cos(a) * 0.03, foot[1] * 0.98 + math.sin(a) * 0.03, foot[2])],
             0.009, pal["alu"])
        tube("Spreader", [(0, 0, 0.12), (foot[0] * 0.6, foot[1] * 0.6, 0.12)], 0.008, pal["dark_metal"])
        if dolly:
            cylinder("Castor", 0.05, 0.03, (foot[0], foot[1], 0.05), pal["rubber"], axis="X", verts=12)
    cylinder("Bowl", 0.07, 0.06, (0, 0, height), pal["dark_metal"], verts=24)
    if head:
        box("FluidHead", (0.14, 0.14, 0.1), (0, 0, height + 0.03), pal["dark_metal"])
        tube("PanBar", [(0.05, -0.05, height + 0.08), (0.15, -0.5, height - 0.05)], 0.012, pal["dark_metal"])
    return height + 0.13


def _barrel(y0, y1, r, z, pal, rings=((0.3, 0.03), (0.62, 0.03)), hood=True):
    """A lens along +Y from y0 to y1: a turned barrel with knurled rings, a
    hood, and the front element behind dark glass."""
    L = y1 - y0
    prof = [(r * 0.85, 0.0), (r, L * 0.04), (r, L * 0.96), (r * 1.02, L)]
    gnkit.lathe("Barrel", prof, pal["paint"], 40, (0, y0, z), axis="Y")
    for at, width in rings:
        gnkit.lathe("Ring", [(r * 1.03, L * at), (r * 1.03, L * (at + width))], pal["rubber"], 40, (0, y0, z), axis="Y")
        for k in range(24):
            a = 2 * math.pi * k / 24
            box("Knurl", (0.004, L * width, 0.004), (math.cos(a) * r * 1.04, y0 + L * at, z + math.sin(a) * r * 1.04 - 0.002),
                pal["rubber"])
    if hood:
        gnkit.lathe("Hood", [(r * 1.02, L), (r * 1.35, L + r * 0.9), (r * 1.3, L + r * 0.9), (r * 0.97, L + 0.004)],
                    pal["plastic"], 40, (0, y0, z), axis="Y")
    gnkit.lathe("FrontGlass", [(r * 0.92, L - 0.002), (r * 0.5, L + r * 0.05), (0.0, L + r * 0.07)], pal["lens_glass"], 40,
                (0, y0, z), axis="Y")


def studio_camera(name, label, with_lens="box"):
    """A broadcast camera on a pedestal tripod: rounded body, a big box lens
    or a long zoom, a viewfinder showing the shot, tally light, pan bars."""
    gnkit.reset()
    pal = gnkit.palette()
    top = _tripod(pal, 1.2, dolly=True)
    grey = gnkit.kit_material("powder_grey", "Grey powder coat", metallic=0.3)
    gnkit.bevel(box("Body", (0.17, 0.38, 0.27), (0, -0.06, top), grey), 0.03, 4)
    for sd in (-1, 1):
        for k in range(5):
            box("Vent", (0.004, 0.14, 0.008), (sd * 0.087, -0.1, top + 0.06 + k * 0.02), pal["plastic"])
        gnkit.lathe("Button", [(0.01, 0.0), (0.01, 0.006 * sd), (0.0, 0.007 * sd)], pal["key"], 16, (sd * 0.086, 0.05, top + 0.2),
                    axis="X")
    if with_lens == "box":
        gnkit.bevel(box("BoxLens", (0.24, 0.5, 0.27), (0, 0.38, top - 0.03), pal["paint"]), 0.035, 4)
        gnkit.bevel(box("LensGrip", (0.05, 0.16, 0.08), (0.14, 0.3, top + 0.02), pal["rubber"]), 0.015, 3)
        _barrel(0.63, 0.7, 0.11, top + 0.105, pal, rings=(), hood=True)
    else:
        _barrel(0.13, 0.52, 0.065, top + 0.135, pal)
        gnkit.bevel(box("ZoomGrip", (0.05, 0.14, 0.09), (0.1, 0.25, top + 0.06), pal["rubber"]), 0.015, 3)
    # Viewfinder: a hood round a screen showing the programme.
    gnkit.bevel(box("Viewfinder", (0.24, 0.14, 0.18), (0, -0.25, top + 0.28), pal["paint"]), 0.02, 3)
    gnkit.picture("VfScreen", 0.2, 0.13, (0, -0.3215, top + 0.37), gnkit.screen_material("screen_video"), "-Y")
    gnkit.lathe("Tally", [(0.018, 0.0), (0.018, 0.012), (0.0, 0.016)], pal["led_red"], 16, (0, 0.02, top + 0.27))
    for sd in (-1, 1):
        tube("PanHandle", [(sd * 0.1, -0.15, top + 0.05), (sd * 0.3, -0.7, top - 0.05)], 0.013, pal["dark_metal"])
        gnkit.lathe("Grip", [(0.02, 0.0), (0.02, 0.12)], pal["rubber"], 16, (sd * 0.3, -0.7, top - 0.05), axis="Y")
    _export(name, label, "camera")


def eng_camera(name, label):
    """A shoulder camera on a light tripod."""
    gnkit.reset()
    pal = gnkit.palette()
    top = _tripod(pal, 1.3, spread=0.4)
    gnkit.bevel(box("Body", (0.13, 0.32, 0.2), (0, 0, top), pal["paint"]), 0.015)
    cylinder("Lens", 0.045, 0.25, (0, 0.28, top + 0.1), pal["paint"], axis="Y", verts=20)
    cylinder("Hood", 0.06, 0.06, (0, 0.43, top + 0.1), pal["paint"], axis="Y", verts=20, radius2=0.045)
    box("Handle", (0.03, 0.2, 0.05), (0, 0.02, top + 0.2), pal["plastic"])
    box("Monitor", (0.02, 0.12, 0.08), (-0.1, 0.05, top + 0.13), pal["screen"])
    _export(name, label, "camera")


def ptz_camera(name, label):
    """A remote pan-tilt-zoom camera, the kind on a bracket at conferences."""
    gnkit.reset()
    pal = gnkit.palette()
    white = gnkit.material("PTZ white", (0.9, 0.9, 0.9), 0.4)
    gnkit.bevel(box("Base", (0.16, 0.16, 0.06), (0, 0, 0), white), 0.01)
    for s in (-1, 1):
        box("Yoke", (0.02, 0.07, 0.14), (s * 0.08, 0, 0.06), white)
    cylinder("Head", 0.065, 0.14, (0, 0.02, 0.17), white, axis="Y", verts=32)
    cylinder("Lens", 0.04, 0.012, (0, 0.095, 0.17), pal["glass"], axis="Y", verts=24)
    box("Tally", (0.02, 0.005, 0.01), (0, 0.082, 0.24), pal["led_red"])
    _export(name, label, "camera")


def jib(name, label, arm=6.0):
    """A camera crane: counterweighted arm on a column, remote head at the tip."""
    gnkit.reset()
    pal = gnkit.palette()
    _tripod(pal, 1.4, spread=0.9, head=False, dolly=True)
    pivot_z = 1.6
    box("Column", (0.16, 0.16, 0.3), (0, 0, 1.35), pal["dark_metal"])
    tip = (0, arm * 0.7 * math.cos(math.radians(15)), pivot_z + arm * 0.7 * math.sin(math.radians(15)))
    tail = (0, -arm * 0.3 * math.cos(math.radians(15)), pivot_z - arm * 0.3 * math.sin(math.radians(15)))
    for s in (-1, 1):
        tube("Tube", [(s * 0.06, tail[1], tail[2]), (s * 0.03, tip[1], tip[2])], 0.025, pal["alu"])
    tube("TopTube", [(0, tail[1] * 0.6, tail[2] + 0.35), (0, tip[1] * 0.7, tip[2] + 0.12)], 0.012, pal["alu"])
    tube("Wire", [(0, tail[1], tail[2]), (0, 0, pivot_z + 0.5), (0, tip[1], tip[2])], 0.004, pal["dark_metal"])
    for k in range(4):
        box("Weight", (0.25, 0.06, 0.25), (0, tail[1] + k * 0.07, tail[2] - 0.12), pal["dark_metal"])
    box("RemoteHead", (0.18, 0.18, 0.2), (0, tip[1], tip[2] - 0.2), pal["dark_metal"])
    box("JibCamera", (0.12, 0.26, 0.16), (0, tip[1] + 0.05, tip[2] - 0.38), pal["paint"])
    cylinder("JibLens", 0.04, 0.16, (0, tip[1] + 0.25, tip[2] - 0.3), pal["paint"], axis="Y", verts=16)
    _export(name, label, "crane", {"arm_m": arm})


def dolly_track(name, label, length=4.8):
    gnkit.reset()
    pal = gnkit.palette()
    for s in (-1, 1):
        cylinder("Rail", 0.02, length, (s * 0.31, 0, 0.04), pal["alu"], axis="Y", verts=12)
    n = int(length / 0.6) + 1
    for i in range(n):
        box("Sleeper", (0.8, 0.06, 0.03), (0, -length / 2 + i * length / (n - 1), 0), pal["wood"])
    gnkit.bevel(box("Dolly", (0.75, 0.9, 0.12), (0, 0, 0.07), pal["dark_metal"]), 0.01)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cylinder("Wheel", 0.04, 0.03, (sx * 0.31, sy * 0.35, 0.08), pal["rubber"], axis="X", verts=12)
    cylinder("DollyColumn", 0.06, 0.7, (0, 0, 0.54), pal["dark_metal"], verts=16)
    box("DollySeat", (0.3, 0.3, 0.06), (0, -0.4, 0.55), pal["plastic"])
    _export(name, label, "dolly")


def projector(name, label, w, d, h, lumens, lens_r=0.07):
    """A large-venue laser projector in its rigging frame, throwing along
    +Y: a rounded powder-coated body, big front vents, a turned lens."""
    gnkit.reset()
    pal = gnkit.palette()
    body = gnkit.kit_material("powder_white", "White powder coat")
    gnkit.bevel(box("Body", (w, d, h), (0, 0, 0.06), body), 0.04, 5)
    gnkit.bevel(box("FrontPanel", (w - 0.06, 0.01, h - 0.06), (0, d / 2 - 0.002, 0.09), pal["paint"]), 0.01, 2)
    for k in range(14):
        box("Louvre", (w * 0.42, 0.012, 0.012), (-w * 0.22, d / 2 + 0.006, 0.12 + k * (h - 0.12) / 15), pal["plastic"])
    # The lens off to one side, in a turned mount.
    x, z = w * 0.22, 0.06 + h * 0.5
    gnkit.lathe("LensMount", [(lens_r * 1.6, 0.0), (lens_r * 1.6, 0.03), (lens_r * 1.35, 0.04)], pal["dark_metal"], 40,
                (x, d / 2, z), axis="Y")
    _barrel(d / 2 + 0.04, d / 2 + 0.24, lens_r * 1.2, z, pal, rings=((0.2, 0.08),), hood=False)
    gnkit.picture("Status", 0.1, 0.05, (x, d / 2 + 0.004, 0.12), gnkit.screen_material("screen_small"), "+Y")
    for sd in (-1, 1):
        gnkit.side_handle(sd * w / 2, 0.0, h * 0.4, d * 0.3, h * 0.3, sd, pal["plastic"], pal["dark_metal"])
        for k in range(8):
            box("SideVent", (0.004, d * 0.5, 0.01), (sd * (w / 2 + 0.001), -d * 0.05, 0.12 + k * 0.03), pal["plastic"])
    # The rigging frame round it: tubes at each corner, feet under.
    for sx in (-1, 1):
        for sy in (-1, 1):
            cylinder("FrameTube", 0.02, h + 0.1, (sx * (w / 2 + 0.035), sy * (d / 2 + 0.03), 0.03 + (h + 0.1) / 2), pal["dark_metal"], verts=16)
            cylinder("Foot", 0.035, 0.03, (sx * (w / 2 + 0.035), sy * (d / 2 + 0.03), 0.015), pal["rubber"], verts=16)
        tube("FrameTop", [(sx * (w / 2 + 0.035), -d / 2 - 0.03, h + 0.13), (sx * (w / 2 + 0.035), d / 2 + 0.03, h + 0.13)], 0.02, pal["dark_metal"], verts=12)
        tube("FrameBottom", [(sx * (w / 2 + 0.035), -d / 2 - 0.03, 0.04), (sx * (w / 2 + 0.035), d / 2 + 0.03, 0.04)], 0.02, pal["dark_metal"], verts=12)
    for sy in (-1, 1):
        tube("FrameCross", [(-w / 2 - 0.035, sy * (d / 2 + 0.03), h + 0.13), (w / 2 + 0.035, sy * (d / 2 + 0.03), h + 0.13)], 0.02,
             pal["dark_metal"], verts=12)
    _export(name, label, "projector", {"lumens": lumens, "lens_height_m": round(0.06 + h * 0.5, 3)})


def small_projector(name, label):
    gnkit.reset()
    pal = gnkit.palette()
    white = gnkit.material("Projector white", (0.88, 0.88, 0.88), 0.4)
    gnkit.bevel(box("Body", (0.33, 0.26, 0.1), (0, 0, 0.01), white), 0.015)
    cylinder("Lens", 0.03, 0.02, (0.08, 0.135, 0.06), pal["lens_lit"], axis="Y", verts=24)
    _export(name, label, "projector", {"lumens": 5000})


def screen(name, label, w, h, rear=False, legs=True):
    """A fast-fold projection screen: a frame with the surface stretched on it,
    on legs, with a black dress kit round the edge."""
    gnkit.reset()
    pal = gnkit.palette()
    surface = gnkit.material("Rear projection" if rear else "Screen white", (0.55, 0.56, 0.58) if rear else (0.92, 0.92, 0.9), 0.9)
    bottom = 0.9 if legs else 0.0
    box("Surface", (w, 0.01, h), (0, 0, bottom), surface)
    box("DressTop", (w + 0.3, 0.02, 0.15), (0, -0.01, bottom + h), pal["fabric"])
    box("DressBottom", (w + 0.3, 0.02, bottom), (0, -0.01, 0), pal["fabric"])
    for s in (-1, 1):
        box("DressSide", (0.15, 0.02, h), (s * (w / 2 + 0.075), -0.01, bottom), pal["fabric"])
        if legs:
            cylinder("Leg", 0.02, bottom + h, (s * (w / 2 + 0.05), -0.1, (bottom + h) / 2), pal["alu"], verts=10)
            tube("Brace", [(s * (w / 2 + 0.05), -0.1, bottom + h * 0.6), (s * (w / 2 + 0.05), -1.2, 0.0)], 0.015, pal["alu"])
            box("FootPlate", (0.1, 1.3, 0.02), (s * (w / 2 + 0.05), -0.6, 0), pal["alu"])
    _export(name, label, "projection_screen", {"image_width_m": w, "image_height_m": h, "rear": rear})


def mic_stand(name, label, boom=True, with_mic=True):
    gnkit.reset()
    pal = gnkit.palette()
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 2
        tube("Leg", [(0, 0, 0.3), (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.0)], 0.008, pal["dark_metal"])
    cylinder("Mast", 0.011, 1.2, (0, 0, 0.9), pal["dark_metal"], verts=10)
    cylinder("Clutch", 0.018, 0.04, (0, 0, 1.0), pal["plastic"], verts=10)
    top = (0, 0, 1.5)
    if boom:
        top = (0, 0.55, 1.6)
        tube("Boom", [(0, -0.2, 1.46), top], 0.008, pal["dark_metal"])
        cylinder("Counterweight", 0.02, 0.06, (0, -0.22, 1.45), pal["dark_metal"], axis="Y", verts=10)
    if with_mic:
        cylinder("MicBody", 0.02, 0.14, (top[0], top[1] + 0.07, top[2] - 0.02), pal["plastic"], axis="Y", verts=16, radius2=0.016)
        sphere("Grille", 0.028, (top[0], top[1] + 0.16, top[2] - 0.02), pal["metal"])
    _export(name, label, "mic_stand")


def lectern(name, label):
    """A lectern in wood: a framed front panel towards the audience (+Y), a
    sloped reading desk with a lip towards the speaker (-Y), a shelf, a
    plinth, a gooseneck microphone."""
    gnkit.reset()
    pal = gnkit.palette()
    wood = gnkit.kit_material("wood_light", "Light oak")
    dark = gnkit.material("Lectern trim", (0.08, 0.06, 0.05), 0.4)
    gnkit.bevel(gnkit.prism("Lectern", [(0.25, 0.05), (0.25, 1.05), (-0.25, 1.15), (-0.28, 1.15), (-0.28, 0.05)], 0.6, wood),
                0.012, 3)
    gnkit.frame("FrontFrame", 0.5, 0.8, (0, 0.254, 0.15), 0.008, 0.035, dark)
    box("FrontInset", (0.43, 0.004, 0.73), (0, 0.251, 0.185), wood)
    lip = gnkit.bevel(box("DeskLip", (0.62, 0.03, 0.035), (0, -0.28, 1.15), dark), 0.006, 2)
    gnkit.bevel(box("Plinth", (0.7, 0.62, 0.05), (0, -0.015, 0), pal["paint"]), 0.01, 2)
    box("Shelf", (0.56, 0.2, 0.02), (0, -0.17, 0.85), wood)
    tube("Gooseneck", [(0.2, -0.2, 1.15), (0.2, -0.15, 1.3), (0.18, -0.02, 1.38)], 0.005, pal["dark_metal"])
    gnkit.lathe("Capsule", [(0.0, 0.0), (0.009, 0.004), (0.009, 0.045), (0.0, 0.05)], pal["dark_metal"], 12, (0.18, -0.02, 1.38),
                axis="Y")
    gnkit.lathe("Collar", [(0.02, 0.0), (0.02, 0.02)], pal["dark_metal"], 16, (0.2, -0.2, 1.15))
    _export(name, label, "lectern")


def prompter(name, label):
    """A presidential-style prompter: angled glass on a slim stand."""
    gnkit.reset()
    pal = gnkit.palette()
    glass = gnkit.material("Prompter glass", (0.5, 0.55, 0.6), 0.02, alpha=0.25)
    cylinder("Pole", 0.02, 1.55, (0, 0, 0.78), pal["dark_metal"], verts=10)
    box("Base", (0.4, 0.4, 0.02), (0, 0, 0), pal["dark_metal"])
    box("Monitor", (0.36, 0.3, 0.04), (0, -0.05, 1.5), pal["paint"])
    pane = box("Glass", (0.4, 0.006, 0.5), (0, 0.0, 1.55), glass)
    gnkit.rotate_about([pane], "X", 40, (0, 0, 1.55))
    _export(name, label, "prompter")


def main():
    studio_camera("camera_studio_box_lens", "Studio camera with an 80x box lens", "box")
    studio_camera("camera_studio_zoom", "Studio camera with a portable zoom", "zoom")
    eng_camera("camera_shoulder", "Shoulder camera on a tripod")
    ptz_camera("camera_ptz", "PTZ-150 remote camera")
    jib("camera_jib", "Jimmy-Jab camera crane", 6.0)
    dolly_track("camera_dolly_track", "Camera dolly on track")
    projector("projector_barcade_40k", "Barcade UDX-40 laser projector", 0.75, 1.0, 0.36, 40000, lens_r=0.08)
    projector("projector_christy_30k", "Christy Griffon 30k laser projector", 0.65, 0.9, 0.32, 30000)
    projector("projector_panorama_20k", "Panorama RZ-21 laser projector", 0.58, 0.75, 0.25, 20000, lens_r=0.06)
    small_projector("projector_meeting", "Meeting-room projector")
    screen("screen_fastfold_16x9", "Quick-Fold screen 16:9, 4 m", 4.0, 2.25)
    screen("screen_fastfold_16x9_6m", "Quick-Fold screen 16:9, 6 m", 6.0, 3.375)
    screen("screen_rear_16x9", "Rear-projection screen 16:9, 5 m", 5.0, 2.81, rear=True)
    mic_stand("mic_stand_boom", "Vocal mic on a boom stand")
    mic_stand("mic_stand_straight", "Vocal mic on a straight stand", boom=False)
    lectern("lectern", "Lectern with gooseneck mic")
    prompter("prompter_glass", "Glass speech prompter")


main()
