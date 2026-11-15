#!/usr/bin/env python3
"""Draws what tools/preview/dump.lua wrote:  draw.py scene.json out.png   (needs Pillow; PREVIEW_FONT = path of a TTF)"""
import json, sys
from PIL import Image, ImageDraw, ImageFont
src, out = sys.argv[1], sys.argv[2]
ops = json.load(open(src, encoding="utf-8"))
SCALE = 2
img = Image.new("RGBA", (1280 * SCALE, 800 * SCALE), (58, 74, 70, 255))
# a rough "game world" behind the windows so that transparency shows
bgd = ImageDraw.Draw(img)
for i in range(0, 800 * SCALE, 8):
    bgd.rectangle([0, i, 1280 * SCALE, i + 8], fill=(52 + (i // 40) % 14, 70 + (i // 24) % 18, 64 + (i // 32) % 12, 255))
import os
FONT = os.environ.get("PREVIEW_FONT", "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf")
fonts = {}
def font(size):
    if size not in fonts:
        try:
            fonts[size] = ImageFont.truetype(FONT, int(size * SCALE))
        except OSError:
            fonts[size] = ImageFont.load_default()
    return fonts[size]
def col(c): return tuple(int(max(0, min(1, v)) * 255) for v in c)
for op in ops:
    x, y, w, h = [v * SCALE for v in (op["x"], op["y"], op["w"], op["h"])]
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if op["t"] == "rect":
        if w >= 1 and h >= 1: d.rectangle([x, y, x + w - 1, y + h - 1], fill=col(op["c"]))
    elif op["t"] == "icon":
        c = op["c"]
        tint = (int(120 * c[0]) + 40, int(150 * c[1]) + 40, int(110 * c[2]) + 40, int(255 * c[3]))
        marker = "arrow" in op["n"] or "star" in op["n"]
        if w >= 1 and h >= 1:
            # a marker is its shape only, in its own color - or the chosen one (the addon tints a decolored picture)
            plain = c[0] > 0.99 and c[1] > 0.99 and c[2] > 0.99
            own = (64, 255, 64) if "arrow" in op["n"] else (255, 220, 60)
            shade = own if plain else (int(255 * c[0]), int(255 * c[1]), int(255 * c[2]))
            fill = shade + (int(255 * c[3]),)
            if not marker: d.rectangle([x, y, x + w - 1, y + h - 1], fill=tint)
            if "arrow" in op["n"]:
                d.polygon([(x + w / 2, y + 1), (x + w - 1, y + h * .55), (x + w * .68, y + h * .55), (x + w * .68, y + h - 1),
                           (x + w * .32, y + h - 1), (x + w * .32, y + h * .55), (x + 1, y + h * .55)], fill=fill, outline=(0, 0, 0, fill[3]))
            if "star" in op["n"]:
                d.polygon([(x + w / 2, y), (x + w * .62, y + h * .38), (x + w, y + h * .38), (x + w * .69, y + h * .62), (x + w * .81, y + h),
                           (x + w / 2, y + h * .76), (x + w * .19, y + h), (x + w * .31, y + h * .62), (x, y + h * .38), (x + w * .38, y + h * .38)],
                          fill=fill, outline=(0, 0, 0, fill[3]))
    else:
        f = font(op["size"])
        s = op["s"]
        tw = d.textlength(s, font=f)
        # a line that does not fit: cut (no wrap) - marks it with an ellipsis like the client
        if w > 0 and tw > w and not op["wrap"]:
            while s and d.textlength(s + "…", font=f) > w: s = s[:-1]
            s += "…"
            tw = d.textlength(s, font=f)
        tx = x
        if op["j"] == "RIGHT": tx = x + w - tw
        elif op["j"] == "CENTER": tx = x + (w - tw) / 2
        d.text((tx, y), s, font=f, fill=col(op["c"]))
    img = Image.alpha_composite(img, layer)
# crop to what was drawn
xs = [op["x"] for op in ops] + [op["x"] + op["w"] for op in ops]
ys = [op["y"] for op in ops] + [op["y"] + op["h"] for op in ops]
pad = 24
box = (max(0, int((min(xs) - pad) * SCALE)), max(0, int((min(ys) - pad) * SCALE)), min(img.width, int((max(xs) + pad) * SCALE)), min(img.height, int((max(ys) + pad) * SCALE)))
img.crop(box).convert("RGB").save(out)
print(out, img.crop(box).size)
