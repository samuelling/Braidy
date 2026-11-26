"""Navi's app icon: a glowing speech bubble with sound waves on a night-blue field."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)

# Background: radial night blue.
cx, cy = S * 0.5, S * 0.45
r = np.clip(np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (S * 0.75), 0, 1)[..., None]
bg = np.array([22, 44, 96], np.float32) * (1 - r) + np.array([5, 8, 24], np.float32) * r

# Speech bubble shape.
mask = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(mask)
bx0, by0, bx1, by1 = S * 0.17, S * 0.22, S * 0.83, S * 0.68
d.rounded_rectangle([bx0, by0, bx1, by1], radius=S * 0.16, fill=255)
d.polygon([(S * 0.30, by1 - 10), (S * 0.46, by1 - 10), (S * 0.26, S * 0.84)], fill=255)

# Sound waves inside the bubble: three arcs around a dot.
waves = Image.new("L", (S, S), 0)
w = ImageDraw.Draw(waves)
ox, oy = S * 0.36, S * 0.45
w.ellipse([ox - S * 0.045, oy - S * 0.045, ox + S * 0.045, oy + S * 0.045], fill=255)
for i, rad in enumerate([0.12, 0.2, 0.28]):
    R = S * rad
    w.arc([ox - R, oy - R, ox + R, oy + R], start=-48, end=48, fill=255, width=int(S * 0.034))

m = np.asarray(mask, np.float32) / 255
wv = np.asarray(waves, np.float32) / 255

# Glow around the bubble.
glow = np.asarray(mask.filter(ImageFilter.GaussianBlur(S * 0.05)), np.float32) / 255
img = bg + np.array([90, 220, 255], np.float32) * (glow * 0.55)[..., None]

# Bubble fill: soft cyan-to-white gradient.
t = np.clip((yy - by0) / (by1 - by0), 0, 1)[..., None]
fill = np.array([235, 252, 255], np.float32) * (1 - t) + np.array([120, 222, 248], np.float32) * t
img = img * (1 - m[..., None]) + fill * m[..., None]

# Waves in deep blue.
img = img * (1 - wv[..., None]) + np.array([18, 48, 110], np.float32) * wv[..., None]

# A few sparkles.
sp = Image.new("L", (S, S), 0)
s = ImageDraw.Draw(sp)
for (x, y, k) in [(0.86, 0.16, 0.035), (0.12, 0.80, 0.025), (0.80, 0.82, 0.02)]:
    X, Y, K = S * x, S * y, S * k
    s.polygon([(X, Y - K), (X + K * 0.25, Y - K * 0.25), (X + K, Y), (X + K * 0.25, Y + K * 0.25),
               (X, Y + K), (X - K * 0.25, Y + K * 0.25), (X - K, Y), (X - K * 0.25, Y - K * 0.25)], fill=255)
spm = np.asarray(sp.filter(ImageFilter.GaussianBlur(3)), np.float32) / 255
img = img * (1 - spm[..., None]) + np.array([255, 246, 200], np.float32) * spm[..., None]

out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").resize((1024, 1024), Image.LANCZOS)
out.save("Navi/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
print("ok")
