"""Braidy's app icon and in-app mascot: Bubble Buddy, a happy talking speech bubble.
Writes Braidy/Assets.xcassets/AppIcon (1024, opaque) and Mascot (transparent, for in-app use)."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import icon_concepts as ic

S = ic.S


def buddy_layers():
    """The character alone on a transparent canvas, plus its drop shadow."""
    bx0, by0, bx1, by1 = 260, 400, 1540, 1440
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([bx0, by0, bx1, by1], radius=440, fill=255)
    md.polygon([(520, 1320), (800, 1400), (400, 1720)], fill=255)
    body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    body.paste(ic.INK + (255,), (0, 0), mask.filter(ImageFilter.MaxFilter(69)))
    body.paste((120, 230, 255, 255), (0, 0), mask)
    ld = ImageDraw.Draw(body)
    over = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    od = ImageDraw.Draw(over)
    od.rounded_rectangle([bx0 + 150, by0 + 80, bx0 + 600, by0 + 180], radius=50, fill=(255, 255, 255, 120))
    ic.face(ld, (bx0 + bx1) / 2, (by0 + by1) / 2 - 40, 1.3, od)
    body = Image.alpha_composite(body, over)
    ImageDraw.Draw(body).text((0, 0), "")
    wd = ImageDraw.Draw(body)
    ic.waves(wd, 1520, 900, (255, 214, 80))
    return body, mask


if __name__ == "__main__":
    icon = ic.concept_a().convert("RGB").resize((1024, 1024), Image.LANCZOS)
    icon.save("../Braidy/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

    body, mask = buddy_layers()
    # crop to the character with a little margin, square
    box = body.getbbox()
    pad = 60
    l, t, r, b = box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad
    side = max(r - l, b - t)
    cx, cy = (l + r) // 2, (t + b) // 2
    crop = body.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2))
    crop.resize((512, 512), Image.LANCZOS).save("../Braidy/Assets.xcassets/Mascot.imageset/Mascot.png")
    print("ok")
