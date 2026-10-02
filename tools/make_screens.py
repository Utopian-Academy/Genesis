"""Screen pictures for the kit's consoles, players and monitors: what their
displays show mid-show, drawn here so they are ours (CC0), with no real
product's interface copied. Saved to genesis_assets/kit_textures/.

    python tools/make_screens.py
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join(os.path.dirname(__file__), "..", "genesis_assets", "kit_textures")
BG = (14, 16, 22)
PANEL = (28, 32, 42)
TEXT = (150, 160, 175)


def _text_lines(d, x, y, w, rows, rng, h=10):
    for r in range(rows):
        d.rectangle((x, y + r * (h + 6), x + rng.randint(w // 3, w), y + r * (h + 6) + 3), fill=TEXT)


def lighting(w=1024, h=640, seed=1):
    """Cue list, fixture sheet and a grid of coloured playback buttons."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w, 28), fill=PANEL)
    _text_lines(d, 10, 10, 200, 1, rng)
    # Playback pool: a grid of labelled, coloured buttons.
    colours = [(200, 60, 60), (60, 160, 220), (230, 180, 40), (120, 200, 90), (190, 90, 220), (240, 120, 40), (70, 70, 80)]
    for j in range(5):
        for i in range(8):
            x0, y0 = 10 + i * 62, 40 + j * 52
            c = rng.choice(colours)
            d.rectangle((x0, y0, x0 + 56, y0 + 46), fill=tuple(v // 3 for v in c), outline=c, width=2)
            d.rectangle((x0 + 6, y0 + 8, x0 + 40, y0 + 12), fill=TEXT)
            if rng.random() < 0.2:
                d.rectangle((x0 + 2, y0 + 38, x0 + 54, y0 + 44), fill=(80, 220, 120))
    # Fixture sheet.
    d.rectangle((520, 40, w - 10, h - 10), fill=PANEL)
    for r in range(20):
        y = 50 + r * 28
        d.rectangle((526, y, w - 16, y + 22), fill=(34, 40, 52) if r % 2 else (30, 35, 46))
        for c in range(6):
            x = 532 + c * 80
            fill = (230, 180, 60) if rng.random() < 0.25 else TEXT
            d.rectangle((x, y + 8, x + rng.randint(20, 60), y + 12), fill=fill)
    # Programmer bar with encoders.
    d.rectangle((10, 310, 505, h - 10), fill=PANEL)
    for k in range(5):
        cx, cy = 60 + k * 95, 420
        d.ellipse((cx - 34, cy - 34, cx + 34, cy + 34), outline=(90, 150, 230), width=5)
        a = rng.uniform(0, 2 * math.pi)
        d.line((cx, cy, cx + 30 * math.cos(a), cy + 30 * math.sin(a)), fill=(230, 230, 240), width=3)
        _text_lines(d, cx - 30, cy + 48, 60, 2, rng)
    return img


def audio(w=1024, h=640, seed=2):
    """Channel overview: meters, gain, EQ curves."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img)
    n = 24
    cw = (w - 20) // n
    for c in range(n):
        x = 10 + c * cw
        d.rectangle((x + 2, 10, x + cw - 3, h - 10), fill=PANEL)
        # EQ curve.
        pts = [(x + 4 + k * (cw - 10) / 20, 70 + 22 * math.sin(k / 3.0 + c) * rng.uniform(0.3, 1.0)) for k in range(21)]
        d.line(pts, fill=(120, 200, 255), width=2)
        # Meter.
        level = rng.uniform(0.2, 0.9)
        top = int(h - 60 - level * 300)
        for yy in range(h - 60, top, -8):
            f = (h - 60 - yy) / 300
            col = (80, 210, 90) if f < 0.7 else ((230, 200, 60) if f < 0.9 else (230, 70, 60))
            d.rectangle((x + 8, yy - 5, x + cw - 9, yy), fill=col)
        # Fader value and name.
        d.rectangle((x + 6, h - 40, x + cw - 7, h - 22), fill=(50, 58, 74))
        d.rectangle((x + 8, h - 34, x + 8 + rng.randint(4, cw - 18), h - 30), fill=TEXT)
    return img


def video(w=1024, h=576, seed=3):
    """A multiview: sources in a grid, programme and preview bigger, with
    red and green tally borders."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (4, 4, 6))
    d = ImageDraw.Draw(img)

    def thumb(x0, y0, x1, y1, tally=None):
        top = tuple(rng.randint(40, 200) for _ in range(3))
        bottom = tuple(rng.randint(10, 90) for _ in range(3))
        for y in range(y0, y1):
            f = (y - y0) / max(y1 - y0, 1)
            d.line((x0, y, x1, y), fill=tuple(int(top[i] * (1 - f) + bottom[i] * f) for i in range(3)))
        # A figure or a stage, as shapes.
        cx = rng.randint(x0 + 20, x1 - 20)
        d.ellipse((cx - 12, y0 + (y1 - y0) // 3, cx + 12, y0 + (y1 - y0) // 3 + 24), fill=(220, 190, 170))
        d.rectangle((cx - 18, y0 + (y1 - y0) // 3 + 24, cx + 18, y1), fill=tuple(rng.randint(20, 120) for _ in range(3)))
        d.rectangle((x0, y1 - 16, x0 + 70, y1), fill=(0, 0, 0))
        d.rectangle((x0 + 6, y1 - 11, x0 + 60, y1 - 7), fill=TEXT)
        if tally:
            d.rectangle((x0, y0, x1, y1), outline=tally, width=5)

    thumb(0, 0, w // 2 - 2, h // 2 - 2, (60, 220, 90))
    thumb(w // 2 + 2, 0, w, h // 2 - 2, (230, 40, 40))
    for j in range(2):
        for i in range(4):
            thumb(i * w // 4 + 2, h // 2 + 2 + j * h // 4, (i + 1) * w // 4 - 2, h // 2 + (j + 1) * h // 4 - 2)
    return img


def dj(w=1024, h=512, seed=4):
    """Two decks' waveforms, beat grids and big BPM figures."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img)
    for deck in range(2):
        y0 = 20 + deck * 170
        mid = y0 + 70
        colour = (60, 170, 255) if deck == 0 else (255, 140, 40)
        amp = 0.0
        for x in range(10, w - 10, 2):
            amp = 0.7 * amp + 0.3 * rng.random()
            v = int(55 * amp * (0.6 + 0.4 * abs(math.sin(x / 37.0))))
            d.line((x, mid - v, x, mid + v), fill=colour)
        for x in range(10, w - 10, 64):
            d.line((x, y0, x, y0 + 140), fill=(200, 200, 210))
        d.line((w // 2, y0 - 5, w // 2, y0 + 145), fill=(240, 40, 40), width=3)
    d.rectangle((10, 370, w - 10, h - 10), fill=PANEL)
    for k in range(4):
        d.rectangle((30 + k * 250, 400, 30 + k * 250 + 200, 470), fill=(40, 46, 60), outline=(90, 100, 120), width=2)
        _text_lines(d, 44 + k * 250, 416, 170, 3, rng)
    return img


def small_display(w=256, h=128, seed=5):
    """A fixture's or an amplifier's little status display."""
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h), (10, 30, 60))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w, 24), fill=(20, 60, 120))
    _text_lines(d, 8, 8, 120, 1, rng)
    _text_lines(d, 8, 36, 200, 5, rng, h=8)
    return img


def banner(w=2048, h=512, seed=6):
    """Show graphics for a big outdoor screen (the blimp's flanks): a bold
    gradient, sweeping bands, one line of lettering."""
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for x in range(w):
        t = x / (w - 1)
        d.line((x, 0, x, h), fill=(int(230 - 60 * t), int(40 + 110 * t), int(150 - 110 * t)))
    for k in range(7):
        y = 60 + k * 70
        d.arc((-w // 2, y - 900, w + w // 2, y + 300), 200, 340, fill=(255, 255, 255), width=6 + k)
    try:
        font = ImageFont.truetype("arialbd.ttf", 190)
    except OSError:
        font = ImageFont.load_default(size=190)
    text = "LIVE TONIGHT"
    box = d.textbbox((0, 0), text, font=font)
    d.text(((w - box[2]) // 2, (h - box[3]) // 2 - 20), text, fill=(255, 255, 255), font=font)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (("screen_lighting", lighting), ("screen_audio", audio), ("screen_video", video),
                     ("screen_dj", dj), ("screen_small", small_display), ("screen_banner", banner)):
        img = fn().filter(ImageFilter.SMOOTH)
        img.save(os.path.join(OUT, name + ".png"))
        print("made", name)


if __name__ == "__main__":
    main()
