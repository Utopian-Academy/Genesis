"""Control positions: lighting, sound and video consoles, racks, DJ gear.

A console is a sloping desk with its controls laid out on the slope (fader
banks at the front, encoders and keys behind, touch screens hinged up at the
back). Each is sized and laid out like the class of desk it stands for and
nicknamed after it, never a real brand or model number.

    blender --background --factory-startup --python tools/blender/control.py
"""

import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import gnkit  # noqa: E402
from gnkit import box, cylinder, prism, tube  # noqa: E402

SCRIPT = "control.py"
CATEGORY = "control"


class Desk:
    """A sloping console top. Controls are placed in flat desk coordinates,
    (x across, v from the front edge back, in metres), and land on the slope."""

    def __init__(self, w, d, front=0.06, back=0.14, pal=None, image="screen_lighting"):
        self.w, self.d, self.front, self.back = w, d, front, back
        self.slope = math.atan2(back - front, d)
        self.pal = pal
        self.glass = gnkit.screen_material(image)
        # Side profile: a rounded front lip, the working slope, and a raised
        # hood at the back that the screens stand in.
        hood = back + 0.05
        profile = [(d / 2 + 0.02, 0), (d / 2 + 0.03, front * 0.5), (d / 2 + 0.02, front), (d / 2 - 0.02, front + 0.004),
                   (-d / 2 + 0.12, back), (-d / 2 + 0.1, hood), (-d / 2 + 0.02, hood + 0.01), (-d / 2, hood - 0.01), (-d / 2, 0)]
        gnkit.bevel(prism("Desk", profile, w, pal["paint"]), 0.012, 3)
        # Side cheeks in a contrasting metal, and a padded armrest.
        for sd in (-1, 1):
            gnkit.bevel(prism("Cheek", [(p[0], p[1] + 0.004) if i not in (0, len(profile) - 1) else p for i, p in enumerate(profile)],
                              0.012, pal["metal"], x=sd * (w / 2 + 0.006)), 0.004, 2)
        gnkit.lathe("Armrest", [(0.0, -w / 2), (0.028, -w / 2 + 0.005), (0.03, -w / 2 + 0.02), (0.03, w / 2 - 0.02),
                                (0.028, w / 2 - 0.005), (0.0, w / 2)], pal["rubber"], 20, (0, d / 2 - 0.005, front - 0.005), axis="X")

    def put(self, objs, v):
        """Tilt objects built flat at height 0 (at desk position v) onto the slope."""
        y = self.d / 2 - v
        z = self.front + v * math.tan(self.slope)
        for o in objs:
            o.data.transform(gnkit.Matrix.Translation((0, y, z)) @ gnkit.Matrix.Rotation(self.slope, 4, "X"))
        return objs

    def faders(self, x0, x1, v, n, rng, travel=0.1):
        pal = self.pal
        out = []
        step = (x1 - x0) / max(n, 1)
        for i in range(n):
            x = x0 + step * (i + 0.5)
            out.append(box("Slot", (0.006, travel, 0.002), (x, 0, 0), pal["plastic"]))
            out.append(box("FaderCap", (0.016, 0.022, 0.016), (x, rng.uniform(-travel / 2.5, travel / 2.5), 0), pal["fader"]))
            out.append(box("Select", (0.014, 0.01, 0.006), (x, -travel / 2 - 0.02, 0), pal["led_blue"] if rng.random() < 0.3 else pal["key"]))
        return self.put(out, v)

    def knobs(self, x0, x1, v, n, rows=1, r=0.009):
        out = []
        step = (x1 - x0) / max(n, 1)
        for j in range(rows):
            for i in range(n):
                out.append(cylinder("Knob", r, 0.018, (x0 + step * (i + 0.5), -j * 0.035, 0.009), self.pal["plastic"], verts=12))
        return self.put(out, v)

    def keys(self, x0, x1, v, cols, rows, rng, lit=0.2, size=0.018):
        out = []
        step = (x1 - x0) / cols
        for j in range(rows):
            for i in range(cols):
                roll = rng.random()
                mat = self.pal["key"]
                if roll < lit:
                    mat = rng.choice([self.pal["led_red"], self.pal["led_green"], self.pal["led_blue"]])
                out.append(box("Key", (size, size, 0.008), (x0 + step * (i + 0.5), -j * (size + 0.006), 0), mat))
        return self.put(out, v)

    def touch(self, x, v, w, h):
        """A screen set into the desk surface."""
        return self.put([box("TouchBezel", (w + 0.02, h + 0.02, 0.004), (x, 0, 0), self.pal["plastic"]),
                         gnkit.picture("Touch", w, h, (x, 0, 0.0045), self.glass, "up")], v)

    def screen(self, x, w, h, lean=18):
        """A screen hinged up at the back of the desk, leaning back."""
        pal = self.pal
        y = -self.d / 2 + 0.03
        z = self.back
        body = box("ScreenBody", (w + 0.03, 0.025, h + 0.03), (x, 0, 0), pal["paint"])
        gnkit.bevel(body, 0.008, 3)
        objs = [body, gnkit.picture("ScreenGlass", w, h, (x, 0.0131, 0.015 + h / 2), self.glass, "+Y")]
        for o in objs:
            o.data.transform(gnkit.Matrix.Translation((0, y, z)) @ gnkit.Matrix.Rotation(math.radians(-lean), 4, "X"))
        return objs

    def tbar(self, x, v):
        pal = self.pal
        out = [box("TbarSlot", (0.012, 0.14, 0.002), (x, 0, 0), pal["plastic"]),
               box("TbarLever", (0.012, 0.012, 0.12), (x, 0.03, 0), pal["metal"]),
               box("TbarHandle", (0.08, 0.02, 0.02), (x, 0.03, 0.12), pal["dark_metal"])]
        return self.put(out, v)


# Gear somebody sits or stands at is built with the operator at +Y, then
# turned round, so its front (+Y) is the way the operator looks: at the
# stage. Placing a desk is then "face the stage", like everything else.
OPERATED = ("lighting_console", "audio_console", "video_switcher", "dj_player", "dj_mixer", "turntable")


def _export(name, label, kind, extra=None):
    obj = gnkit.join_all(name)
    if kind in OPERATED:
        obj.data.transform(gnkit.Matrix.Rotation(math.pi, 4, "Z"))
    info = {"label": label, "kind": kind}
    info.update(extra or {})
    gnkit.export(CATEGORY, name, SCRIPT, info)


def lighting_console(name, label, w, d, screens, faders, seed=1):
    gnkit.reset()
    pal = gnkit.palette()
    rng = random.Random(seed)
    desk = Desk(w, d, pal=pal, image="screen_lighting")
    m = 0.05
    # Playback faders along the front, keys above them.
    desk.faders(-w / 2 + m, w / 2 - m - 0.25, 0.1, faders, rng)
    desk.keys(-w / 2 + m, w / 2 - m - 0.25, 0.2, faders, 2, rng, lit=0.35)
    # The programmer: keypad and encoders on the right.
    desk.keys(w / 2 - 0.23, w / 2 - m, 0.1, 5, 6, rng, lit=0.1)
    desk.knobs(w / 2 - 0.23, w / 2 - m, 0.3, 4, r=0.014)
    desk.put([cylinder("Trackball", 0.022, 0.02, (w / 2 - 0.14, 0, 0), pal["plastic"], verts=16)], 0.38)
    # Touch screens in the surface, and screens up at the back.
    desk.touch(-0.1, 0.33, min(0.4, w * 0.35), 0.14)
    sw = (w - 0.1) / max(screens, 1) - 0.03
    for i in range(screens):
        desk.screen(-w / 2 + 0.05 + (i + 0.5) * (sw + 0.03), sw, sw * 0.62)
    _export(name, label, "lighting_console", {"width_m": w})


def audio_console(name, label, w, d, screens, faders, knob_rows=4, meter_bridge=False, seed=2):
    gnkit.reset()
    pal = gnkit.palette()
    rng = random.Random(seed)
    desk = Desk(w, d, front=0.07, back=0.16, pal=pal, image="screen_audio")
    m = 0.04
    desk.faders(-w / 2 + m, w / 2 - m, 0.09, faders, rng)
    # Channel strips: a column of knobs over every fader.
    desk.knobs(-w / 2 + m, w / 2 - m, 0.25, faders, rows=knob_rows)
    sw = min(0.42, (w - 0.1) / max(screens, 1) - 0.03)
    for i in range(screens):
        x = (i - (screens - 1) / 2) * (sw + 0.04)
        desk.touch(x, 0.25 + knob_rows * 0.035 + 0.05, sw, sw * 0.4)
    if meter_bridge:
        box("MeterBridge", (w - 0.04, 0.05, 0.08), (0, -d / 2 + 0.03, desk.back), pal["paint"])
        gnkit.grid("Meter", faders, 1, (0.012, 0.06), (w - 0.1) / faders - 0.012,
                   (-w / 2 + 0.05, -d / 2 + 0.06, desk.back + 0.01), pal["led_green"], 0.004, axis="Y")
    else:
        for i in range(max(1, screens // 2)):
            desk.screen((i - (max(1, screens // 2) - 1) / 2) * 0.5, 0.45, 0.28)
    _export(name, label, "audio_console", {"width_m": w})


def video_switcher(name, label, w, d, rows=4, cols=20, tbar=True, screens=2, seed=3):
    gnkit.reset()
    pal = gnkit.palette()
    rng = random.Random(seed)
    desk = Desk(w, d, front=0.05, back=0.1, pal=pal, image="screen_video")
    desk.keys(-w / 2 + 0.05, w / 2 - 0.2, 0.08, cols, rows, rng, lit=0.4)
    desk.knobs(-w / 2 + 0.05, w / 2 - 0.2, 0.08 + rows * 0.025 + 0.04, 8)
    if tbar:
        desk.tbar(w / 2 - 0.1, 0.12)
    for i in range(screens):
        desk.touch(-w / 2 + 0.12 + i * 0.22, d - 0.1, 0.18, 0.08)
    _export(name, label, "video_switcher", {"width_m": w})


def rack_unit(name, label, units, face="server"):
    """A single piece of rack gear, 19 inches wide: media servers, processors."""
    gnkit.reset()
    pal = gnkit.palette()
    h = units * 0.0445
    gnkit.bevel(box("Chassis", (0.44, 0.6, h), (0, 0, 0), pal["dark_metal"]), 0.004)
    box("Ears", (0.483, 0.004, h), (0, 0.3, 0), pal["dark_metal"])
    gnkit.picture("Screen", 0.1, h * 0.5, (-0.14, 0.3025, h * 0.5), gnkit.screen_material("screen_small"), "+Y")
    gnkit.grid("Vent", 14, max(1, units), (0.012, 0.02), 0.006, (-0.05, 0.303, 0.01), pal["plastic"], 0.003, axis="Y")
    _export(name, label, "rack_unit", {"units": units})


def rack(name, label, units, fill, standing=False):
    """A rack: a road case (or a standing cabinet) full of gear."""
    gnkit.reset()
    pal = gnkit.palette()
    rng = random.Random(units)
    inner = units * 0.0445
    w, d = 0.6, 0.7
    h = inner + 0.12
    base = 0.14 if not standing else 0.05
    gnkit.bevel(box("Case", (w, d, h), (0, 0, base), pal["case" if not standing else "paint"]), 0.006)
    box("Opening", (0.46, 0.01, inner), (0, d / 2 - 0.004, base + 0.06), pal["fabric"])
    u = 0
    while u < units:
        size = min(rng.choice(fill), units - u)
        z = base + 0.06 + u * 0.0445
        box("Gear", (0.44, 0.01, size * 0.0445 - 0.003), (0, d / 2 + 0.002, z), pal["dark_metal"])
        gnkit.picture("GearScreen", 0.06, 0.02, (-0.16, d / 2 + 0.0075, z + 0.022), gnkit.screen_material("screen_small"), "+Y")
        for k in range(rng.randint(2, 10)):
            box("GearLed", (0.006, 0.004, 0.006), (0.0 + k * 0.018, d / 2 + 0.008, z + 0.018),
                rng.choice([pal["led_green"], pal["led_blue"], pal["led_red"], pal["key"]]))
        u += size
    if not standing:
        for sx in (-1, 1):
            for sy in (-1, 1):
                cylinder("Castor", 0.05, 0.035, (sx * (w / 2 - 0.08), sy * (d / 2 - 0.08), 0.05), pal["rubber"], axis="X", verts=12)
                box("CastorPlate", (0.08, 0.08, 0.02), (sx * (w / 2 - 0.08), sy * (d / 2 - 0.08), 0.12), pal["metal"])
                box("Corner", (0.05, 0.05, 0.05), (sx * (w / 2 - 0.02), sy * (d / 2 - 0.02), base + h - 0.05), pal["metal"])
    _export(name, label, "rack", {"units": units})


def _player_parts(pal, dj_screen):
    """A DJ media player, operator at +Y: sloped body, big turned jog wheel
    with its centre display, a waveform screen at the back, play and cue,
    tempo slider, hot-cue pads."""
    gnkit.bevel(prism("Body", [(0.2, 0), (0.205, 0.05), (0.2, 0.1), (-0.2, 0.125), (-0.205, 0.07), (-0.2, 0)], 0.32,
                      pal["paint"]), 0.012, 3)
    top = lambda y: 0.1 + (0.2 - y) / 0.4 * 0.025
    gnkit.lathe("Jog", [(0.105, top(0.06)), (0.105, top(0.06) + 0.016), (0.1, top(0.06) + 0.022), (0.06, top(0.06) + 0.022),
                        (0.055, top(0.06) + 0.018), (0.0, top(0.06) + 0.018)], pal["alu"], 64, (0.0, 0.06, 0.0))
    gnkit.lathe("JogRing", [(0.106, top(0.06) + 0.004), (0.108, top(0.06) + 0.012)], pal["led_blue"], 64, (0.0, 0.06, 0.0))
    gnkit.picture("JogDisplay", 0.07, 0.07, (0.0, 0.06, top(0.06) + 0.019), dj_screen, "up")
    box("ScreenBezel", (0.23, 0.13, 0.006), (0.0, -0.13, top(-0.13)), pal["plastic"])
    gnkit.picture("Screen", 0.2, 0.11, (0.0, -0.13, top(-0.13) + 0.0065), dj_screen, "up")
    for i, mat in enumerate((pal["led_green"], pal["led_red"])):
        gnkit.lathe("PlayCue", [(0.024, 0.0), (0.024, 0.008), (0.02, 0.012), (0.0, 0.012)], mat, 24,
                    (-0.125, 0.17 - i * 0.055, top(0.17 - i * 0.055)))
    box("TempoSlot", (0.012, 0.13, 0.003), (0.13, 0.07, top(0.07)), pal["plastic"])
    box("TempoCap", (0.03, 0.02, 0.016), (0.13, 0.08, top(0.08)), pal["fader"])
    for k in range(8):
        box("Pad", (0.03, 0.022, 0.006), (-0.105 + k * 0.03, -0.045, top(-0.045)), pal["key"])


def _mixer_parts(pal, rng):
    """A four-channel DJ mixer, operator at +Y: turned knobs in columns,
    meters, channel faders, a crossfader."""
    gnkit.bevel(box("Body", (0.33, 0.44, 0.1), (0, 0, 0), pal["paint"]), 0.012, 3)
    box("Faceplate", (0.31, 0.42, 0.003), (0, 0, 0.1), pal["metal"])
    for i in range(4):
        x = -0.12 + i * 0.08
        for j in range(5):
            gnkit.lathe("Knob", [(0.012, 0.0), (0.012, 0.014), (0.009, 0.019), (0.0, 0.02)], pal["plastic"], 20,
                        (x, -0.17 + j * 0.045, 0.103))
            box("KnobMark", (0.002, 0.008, 0.002), (x, -0.17 + j * 0.045 + 0.005, 0.1225), pal["fader"])
        box("Slot", (0.005, 0.09, 0.002), (x, 0.12, 0.103), pal["plastic"])
        box("FaderCap", (0.018, 0.024, 0.018), (x, 0.12 + rng.uniform(-0.03, 0.03), 0.103), pal["fader"])
        level = rng.randint(4, 9)
        for k in range(10):
            box("Meter", (0.008, 0.005, 0.002), (x + 0.028, 0.08 - k * 0.008, 0.103),
                (pal["led_green"] if k < 7 else pal["led_red"]) if k < level else pal["key"])
    box("CrossSlot", (0.11, 0.005, 0.002), (0, 0.19, 0.103), pal["plastic"])
    box("CrossCap", (0.024, 0.02, 0.018), (0, 0.19, 0.103), pal["fader"])


def _turned_round(before, at):
    """Stands parts built for an operator at +Y where the operator is at -Y,
    at `at`."""
    for o in gnkit.made_since(before):
        o.data.transform(gnkit.Matrix.Translation(at) @ gnkit.Matrix.Rotation(math.pi, 4, "Z"))


def cdj(name, label):
    gnkit.reset()
    pal = gnkit.palette()
    _player_parts(pal, gnkit.screen_material("screen_dj"))
    _export(name, label, "dj_player")


def dj_mixer(name, label):
    gnkit.reset()
    pal = gnkit.palette()
    _mixer_parts(pal, random.Random(4))
    _export(name, label, "dj_mixer")


def turntable(name, label):
    gnkit.reset()
    pal = gnkit.palette()
    gnkit.bevel(box("Plinth", (0.45, 0.35, 0.16), (0, 0, 0), pal["metal"]), 0.01)
    cylinder("Platter", 0.15, 0.02, (-0.04, 0.0, 0.17), pal["dark_metal"], verts=48)
    cylinder("Record", 0.148, 0.004, (-0.04, 0.0, 0.182), pal["plastic"], verts=48)
    cylinder("Label", 0.045, 0.005, (-0.04, 0.0, 0.183), pal["led_red"], verts=24)
    tube("Tonearm", [(0.17, -0.12, 0.2), (0.15, 0.05, 0.2), (0.08, 0.1, 0.19)], 0.004, pal["alu"])
    cylinder("ArmBase", 0.025, 0.03, (0.17, -0.12, 0.175), pal["alu"], verts=16)
    box("Pitch", (0.02, 0.1, 0.004), (0.18, 0.06, 0.16), pal["plastic"])
    _export(name, label, "turntable")


def dj_booth(name, label, w=2.0, d=0.8, h=1.0, shroud=True):
    gnkit.reset()
    pal = gnkit.palette()
    if shroud:
        prof = [(d / 2 + 0.05, h), (d / 2 - 0.05, 0), (-d / 2, 0), (-d / 2, h)]
        gnkit.bevel(prism("Shroud", prof, w, pal["white_fabric"]), 0.04, 3)
    else:
        gnkit.bevel(box("Facade", (w, d, h), (0, 0, 0), pal["fabric"]), 0.01)
    box("Top", (w + 0.06, d + 0.1, 0.03), (0, 0.025, h), pal["paint"])
    top = h + 0.03
    # The DJ stands behind (-Y) and faces the crowd (+Y), so the gear, built
    # for an operator at +Y, is turned round on the table.
    dj_screen = gnkit.screen_material("screen_dj")
    for x, kind in ((-0.4, "cdj"), (0.0, "mixer"), (0.4, "cdj")):
        before = set(bpy.data.objects)
        if kind == "cdj":
            _player_parts(pal, dj_screen)
        else:
            _mixer_parts(pal, random.Random(4))
        _turned_round(before, (x, -0.05, top))
    # A laptop on a stand to one side, its screen towards the DJ.
    before = set(bpy.data.objects)
    gnkit.bevel(box("LaptopStand", (0.24, 0.2, 0.1), (0, 0, 0), pal["alu"]), 0.006, 2)
    gnkit.bevel(box("LaptopBase", (0.32, 0.22, 0.012), (0, 0, 0.1), pal["alu"]), 0.004, 2)
    lid = gnkit.bevel(box("LaptopLid", (0.32, 0.008, 0.21), (0, -0.11, 0.112), pal["alu"]), 0.004, 2)
    scr = gnkit.picture("LaptopScreen", 0.29, 0.18, (0, -0.1055, 0.112 + 0.105), dj_screen, "+Y")
    gnkit.rotate_about([lid, scr], "X", 12, (0, -0.11, 0.112))
    _turned_round(before, (0.78, -0.1, top))
    _export(name, label, "dj_booth", {"width_m": w, "height_m": h})


def foh_table(name, label, w=2.4, d=0.9, h=0.8):
    """The front-of-house table: a trestle in a black cloth to the floor."""
    gnkit.reset()
    pal = gnkit.palette()
    box("Cloth", (w, d, h - 0.03), (0, 0, 0), pal["fabric"])
    box("Top", (w + 0.02, d + 0.02, 0.03), (0, 0, h - 0.03), pal["fabric"])
    _export(name, label, "table")


def monitor_screen(name, label, size_in=24, stand=True):
    gnkit.reset()
    pal = gnkit.palette()
    diag = size_in * 0.0254
    w, h = diag * 0.87, diag * 0.49
    z = 0.12 if stand else 0.0
    box("Bezel", (w + 0.02, 0.025, h + 0.02), (0, 0, z), pal["paint"])
    gnkit.picture("Panel", w, h, (0, 0.0126, z + 0.01 + h / 2), gnkit.screen_material("screen_video"), "+Y")
    if stand:
        box("Neck", (0.05, 0.03, 0.2), (0, -0.03, 0.0), pal["dark_metal"])
        box("Foot", (0.22, 0.18, 0.012), (0, -0.03, 0.0), pal["dark_metal"])
    _export(name, label, "monitor", {"diagonal_in": size_in})


def main():
    # Lighting.
    lighting_console("lighting_console_grandpa_full", "grandPA 4 full-size lighting console", 1.36, 0.8, 3, 15, seed=11)
    lighting_console("lighting_console_grandpa_light", "grandPA 4 light lighting console", 0.98, 0.72, 2, 15, seed=12)
    lighting_console("lighting_console_mysticq", "MysticQ 5000 lighting console", 1.1, 0.72, 3, 10, seed=13)
    lighting_console("lighting_console_sapphire", "Avalanche Sapphire lighting console", 1.24, 0.78, 2, 20, seed=14)
    lighting_console("lighting_console_warthog", "Warthog 5 lighting console", 1.12, 0.75, 2, 10, seed=15)
    lighting_console("lighting_console_eon_summit", "Eon Summit lighting console", 1.3, 0.8, 3, 20, seed=16)
    lighting_console("lighting_wing_compact", "Compact command wing", 0.56, 0.45, 1, 10, seed=17)
    # Sound.
    audio_console("audio_console_digidoc_sd8", "DigiDoc SD8 mixing console", 1.5, 0.95, 3, 36, knob_rows=4, seed=21)
    audio_console("audio_console_yamanaka_cl6", "Yamanaka CL6 mixing console", 1.06, 0.66, 1, 25, knob_rows=6, meter_bridge=True, seed=22)
    audio_console("audio_console_dlife", "Allan & Keith dLife mixing surface", 1.2, 0.78, 2, 24, knob_rows=2, seed=23)
    audio_console("audio_console_avidly_s7l", "Avidly S7L mixing console", 1.35, 0.85, 1, 32, knob_rows=8, meter_bridge=True, seed=24)
    audio_console("audio_console_ex33", "Ex-33 compact digital mixer", 0.9, 0.53, 1, 17, knob_rows=3, seed=25)
    # Video.
    video_switcher("video_switcher_event_mister", "Event Mister E3 presentation switcher", 1.2, 0.5, rows=4, cols=24, seed=31)
    video_switcher("video_switcher_atom", "ATOM Constellation live production switcher", 0.95, 0.4, rows=3, cols=20, seed=32)
    video_switcher("video_switcher_mini", "ATOM Mini streaming switcher", 0.3, 0.2, rows=2, cols=8, tbar=False, screens=0, seed=33)
    rack_unit("media_server_guise", "Guise gx4 media server", 4)
    rack_unit("media_server_small", "Compact media server", 2)
    rack("rack_12u", "12U touring rack", 12, [1, 1, 2, 2, 3])
    rack("rack_24u", "24U touring rack", 24, [1, 2, 2, 3, 4])
    rack("rack_42u", "42U standing rack cabinet", 42, [1, 1, 2, 2, 4], standing=True)
    rack("rack_iem", "In-ear monitor rack", 10, [1, 1])
    monitor_screen("monitor_24", "24-inch preview monitor", 24)
    monitor_screen("monitor_55", "55-inch confidence monitor", 55, stand=False)
    # DJ.
    cdj("dj_player_cdj", "Piloneer CDJ-3100 player")
    dj_mixer("dj_mixer_djm", "Piloneer DJM-A11 mixer")
    turntable("dj_turntable", "Technix 1210 turntable")
    dj_booth("dj_booth_shroud", "DJ booth in a stretch shroud", shroud=True)
    dj_booth("dj_booth_facade", "DJ booth with a black facade", shroud=False)
    foh_table("foh_table", "Front-of-house table")


main()
