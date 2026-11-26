"""Three original mascot directions for Braidy's icon (a playful game buddy).
Renders each at 1024 px plus a side-by-side sheet with home-screen-size previews."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # draw big, downsample for smooth edges
INK = (30, 20, 60)


def gradient(c1, c2, angle=135):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    a = math.radians(angle)
    t = np.clip((xx * math.cos(a) + yy * math.sin(a) + 0.5) / 1.6, 0, 1)[..., None]
    img = np.array(c1, np.float32) * (1 - t) + np.array(c2, np.float32) * t
    return Image.fromarray(img.astype(np.uint8), "RGB").convert("RGBA")


def sparkle(d, x, y, r, color):
    d.polygon([(x, y - r), (x + r * 0.22, y - r * 0.22), (x + r, y), (x + r * 0.22, y + r * 0.22),
               (x, y + r), (x - r * 0.22, y + r * 0.22), (x - r, y), (x - r * 0.22, y - r * 0.22)], fill=color)


def face(d, cx, cy, scale, cheeks, eye=INK):
    ex = 150 * scale
    for sx in (-1, 1):
        x = cx + sx * ex
        d.ellipse([x - 62 * scale, cy - 95 * scale, x + 62 * scale, cy + 95 * scale], fill=eye)
        d.ellipse([x - 22 * scale, cy - 70 * scale, x + 18 * scale, cy - 22 * scale], fill=(255, 255, 255))
        d.ellipse([x + 14 * scale, cy + 20 * scale, x + 34 * scale, cy + 42 * scale], fill=(255, 255, 255))
    for sx in (-1, 1):
        x = cx + sx * 255 * scale
        cheeks.ellipse([x - 62 * scale, cy + 68 * scale, x + 62 * scale, cy + 122 * scale], fill=(255, 110, 150, 140))
    # happy "talking" mouth
    d.chord([cx - 80 * scale, cy + 50 * scale, cx + 80 * scale, cy + 190 * scale], 0, 180, fill=eye)
    d.chord([cx - 45 * scale, cy + 125 * scale, cx + 45 * scale, cy + 185 * scale], 180, 360, fill=(255, 110, 140))


def shadow(img, mask, offset=(0, 40), blur=60, alpha=110):
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sh.paste((10, 0, 30, alpha), offset, mask)
    return Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(blur)))


def waves(d, cx, cy, color):
    for r in (150, 250, 350):
        d.arc([cx - r, cy - r, cx + r, cy + r], -40, 40, fill=color, width=42)


# ---------- A: Bubble Buddy: a talking speech bubble with sound waves ----------
def concept_a():
    img = gradient((40, 18, 110), (235, 60, 150))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(3)
    for _ in range(60):
        x, y = rng.integers(0, S, 2)
        s = int(rng.integers(8, 20))
        d.rectangle([x, y, x + s, y + s], fill=(255, 255, 255, int(rng.integers(40, 140))))
    bx0, by0, bx1, by1 = 260, 400, 1540, 1440
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([bx0, by0, bx1, by1], radius=440, fill=255)
    md.polygon([(520, 1320), (800, 1400), (400, 1720)], fill=255)
    img = shadow(img, mask)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    layer.paste(INK + (255,), (0, 0), mask.filter(ImageFilter.MaxFilter(69)))
    layer.paste((120, 230, 255, 255), (0, 0), mask)
    over = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    od = ImageDraw.Draw(over)
    od.rounded_rectangle([bx0 + 150, by0 + 80, bx0 + 600, by0 + 180], radius=50, fill=(255, 255, 255, 120))
    face(ld, (bx0 + bx1) / 2, (by0 + by1) / 2 - 40, 1.3, od)
    img = Image.alpha_composite(Image.alpha_composite(img, layer), over)
    d = ImageDraw.Draw(img)
    waves(d, 1520, 900, (255, 214, 80))
    sparkle(d, 1800, 300, 100, (255, 240, 150))
    sparkle(d, 1650, 1700, 70, (255, 255, 255))
    return img


# ---------- B: Pixel Pal: 8-bit speech-bubble buddy on a neon arcade floor ----------
SPRITE = [
    "....OOOOOOOO....",
    "..OOWWWWWWWWOO..",
    ".OWWWWWWWWWWWWO.",
    "OWWWWWWWWWWWWWWO",
    "OWWWEEWWWWEEWWWO",
    "OWWWEFWWWWEFWWWO",
    "OWWWEEWWWWEEWWWO",
    "OWCCWWWWWWWWCCWO",
    "OWWWWMMMMMMWWWWO",
    "OWWWWWMPPMWWWWWO",
    ".OWWWWWMMWWWWWO.",
    "..OOWWWWWWWWOO..",
    "....OOWWOOOO....",
    "....OWWO........",
    "...OWO..........",
    "...OO...........",
]
PAL = {"O": (30, 20, 60), "W": (120, 230, 255), "E": (30, 20, 60), "F": (255, 255, 255),
       "C": (255, 130, 170), "M": (30, 20, 60), "P": (255, 90, 140)}


def concept_b():
    img = gradient((12, 6, 40), (70, 20, 120), angle=90)
    d = ImageDraw.Draw(img)
    horizon = 1380
    for i in range(-12, 13):
        d.line([(S / 2 + i * 60, horizon), (S / 2 + i * 420, S)], fill=(255, 60, 200), width=10)
    y, gap = horizon, 30
    while y < S:
        d.line([(0, y), (S, y)], fill=(255, 60, 200), width=8)
        gap *= 1.35
        y += gap
    d.ellipse([S / 2 - 560, horizon - 700, S / 2 + 560, horizon + 420], fill=(255, 150, 60))
    for k in range(6):
        yy = horizon - 240 + k * 62
        d.rectangle([0, yy, S, yy + 18 + k * 4], fill=(70, 20, 120))
    d.rectangle([0, horizon, S, horizon + 6], fill=(255, 120, 230))
    px = 100
    ox, oy = (S - 16 * px) / 2 - 120, 230
    sprite = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sprite)
    for r, row in enumerate(SPRITE):
        for c, ch in enumerate(row):
            if ch in PAL:
                x, y = ox + c * px, oy + r * px
                sd.rectangle([x, y, x + px, y + px], fill=PAL[ch])
    img = Image.alpha_composite(img, sprite.filter(ImageFilter.GaussianBlur(40)))
    img = Image.alpha_composite(img, sprite)
    d = ImageDraw.Draw(img)
    for k in range(3):  # pixel sound waves
        x = ox + 16 * px + 70 + k * 110
        h = 240 + k * 160
        cy = oy + 6 * px
        for j in range(-h // 2, h // 2, 60):
            d.rectangle([x, cy + j, x + 50, cy + j + 40], fill=(255, 214, 80))
    return img


# ---------- C: Pad Pal: a round, controller-shaped buddy ----------
def concept_c():
    img = gradient((20, 170, 180), (40, 60, 170))
    d = ImageDraw.Draw(img)
    for r, a in ((920, 40), (780, 55), (640, 70)):
        d.ellipse([S / 2 - r, S / 2 - r + 60, S / 2 + r, S / 2 + r + 60], outline=(255, 255, 255, a), width=26)
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([330, 640, 1718, 1300], radius=330, fill=255)
    md.ellipse([250, 900, 820, 1640], fill=255)
    md.ellipse([1228, 900, 1798, 1640], fill=255)
    img = shadow(img, mask)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    layer.paste((60, 30, 20, 255), (0, 0), mask.filter(ImageFilter.MaxFilter(69)))
    layer.paste((255, 196, 80, 255), (0, 0), mask)
    over = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    od = ImageDraw.Draw(over)
    od.rounded_rectangle([520, 700, 1000, 790], radius=45, fill=(255, 255, 255, 110))
    face(ld, S / 2, 940, 1.1, od, eye=(60, 30, 20))
    gx, gy = 520, 1330
    ld.rounded_rectangle([gx - 120, gy - 40, gx + 120, gy + 40], radius=16, fill=(60, 30, 20))
    ld.rounded_rectangle([gx - 40, gy - 120, gx + 40, gy + 120], radius=16, fill=(60, 30, 20))
    for (bx, by, col) in ((1528, 1230, (255, 80, 140)), (1640, 1340, (60, 220, 255)),
                          (1528, 1450, (90, 220, 120)), (1416, 1340, (150, 110, 255))):
        ld.ellipse([bx - 58, by - 58, bx + 58, by + 58], fill=(60, 30, 20))
        ld.ellipse([bx - 44, by - 44, bx + 44, by + 44], fill=col)
    img = Image.alpha_composite(Image.alpha_composite(img, layer), over)
    d = ImageDraw.Draw(img)
    sparkle(d, 360, 380, 110, (255, 250, 200))
    d.rounded_rectangle([1250, 230, 1760, 520], radius=120, fill=(255, 255, 255))
    d.polygon([(1340, 500), (1440, 500), (1300, 620)], fill=(255, 255, 255))
    for k in range(3):
        d.ellipse([1370 + k * 120, 340, 1430 + k * 120, 400], fill=(40, 60, 170))
    return img


if __name__ == "__main__":
    outs = []
    for name, fn in (("A_bubble_buddy", concept_a), ("B_pixel_pal", concept_b), ("C_pad_pal", concept_c)):
        im = fn().convert("RGB").resize((1024, 1024), Image.LANCZOS)
        im.save(f"/home/claude/icon_{name}.png")
        outs.append(im)
    sheet = Image.new("RGB", (3 * 560 + 80, 760), (245, 245, 250))
    mask = Image.new("L", (512, 512), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, 511, 511], radius=115, fill=255)
    small = mask.resize((120, 120), Image.LANCZOS)
    for i, im in enumerate(outs):
        x = 40 + i * 560
        sheet.paste(im.resize((512, 512), Image.LANCZOS), (x, 40), mask)
        sheet.paste(im.resize((120, 120), Image.LANCZOS), (x + 196, 600), small)
    sheet.save("/home/claude/icon_concepts.png")
    print("ok")
