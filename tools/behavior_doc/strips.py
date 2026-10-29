"""Render per-behavior frame strips from the built orange sprite sheet, same scale, head-aligned."""
import sys, os
from PIL import Image, ImageDraw, ImageFont

_SHEET = {}
def cell(i):
    """Frame i from the built 64-cell sprite sheet (8 x 8 cells of 384 x 256)."""
    if "s" not in _SHEET: _SHEET["s"] = Image.open(f"{SRC_SHEET}/sheet.png").convert("RGBA")
    return _SHEET["s"].crop((i % 8 * 384, i // 8 * 256, i % 8 * 384 + 384, i // 8 * 256 + 256))

src, out = sys.argv[1], sys.argv[2]
SRC_SHEET = src
os.makedirs(out, exist_ok=True)
FONT = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 22)
SMALL = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 16)

def placed(i):
    im = cell(i)  # head anchor at x = 300 in every cell
    canvas = Image.new("RGBA", (420, 256), (0, 0, 0, 0))
    canvas.paste(im, (20, 0), im)
    return canvas

def shrink(im, w, h):
    # Same as the app: halve step by step, then one final resize to the exact pixel size.
    while im.width // 2 >= w * 2 and im.height // 2 >= h * 2:
        im = im.resize((im.width // 2, im.height // 2), Image.BICUBIC)
    return im.resize((w, h), Image.BICUBIC)

def strip(name, frames, labels=None, per_row=8):
    ims = [placed(i) for i in frames]
    box = None
    for im in ims:
        b = im.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox()
        if b: box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    left, top, right = max(0, box[0] - 10), max(0, box[1] - 10), min(420, box[2] + 10)
    bottom = 246  # a little below the 232 px ground line
    # mode: (suffix, screen pixels per point, integer zoom so all three come out about the same size)
    for suffix, density, zoom in (("", None, 1), ("-2x", 2, 3), ("-1x", 1, 6)):
        cells = []
        for im in ims:
            if density is None:
                cells.append(im.crop((left, top, right, bottom))); continue
            s = 24 / 180 * density  # adult cat; source px -> screen px
            small = shrink(im, round(420 * s), round(256 * s))
            l, t, r, b = (round(v * s) for v in (left, top, right, bottom))
            cells.append(small.crop((l, t, r, b)).resize(((r - l) * zoom, (b - t) * zoom), Image.NEAREST))
        cw, ch = cells[0].size
        unit = ch / (bottom - top)
        pad, label_h = 8, 30
        cols = min(per_row, len(cells)); rows = (len(cells) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * (cw + pad) + pad, rows * (ch + label_h + pad) + pad), (255, 255, 255))
        d = ImageDraw.Draw(sheet)
        for k, cell in enumerate(cells):
            r, c = divmod(k, cols)
            x, y = pad + c * (cw + pad), pad + r * (ch + label_h + pad)
            d.rectangle([x, y, x + cw - 1, y + ch + label_h - 1], fill=(246, 244, 240))
            gy = y + round((232 - top) * unit)
            d.line([x + 4, gy, x + cw - 5, gy], fill=(200, 190, 175), width=2)
            sheet.paste(cell, (x, y), cell)
            text = labels[k] if labels else f"#{frames[k]}"
            d.text((x + 8, y + ch + 4), text, fill=(60, 50, 40), font=FONT)
        sheet.save(f"{out}/{name}{suffix}.png")

groups = {
    "stand": [0, 1, 2, 3], "walk": list(range(4, 12)), "run": list(range(12, 20)), "turn": [20, 21, 22, 23],
    "stand-sit": [24, 25, 26], "sit-loaf": [27, 28, 29], "loaf-sleep": [30, 31, 32], "sleep": [33, 34],
    "groom": [35, 36, 37, 38], "stretch": [39, 40, 41, 42, 43], "yawn": [26, 44, 45, 26], "crouch": [46, 47],
    "creep": [48, 49, 50, 51], "wiggle": [52, 53], "pounce": [54, 55, 56, 57], "bat": [46, 58, 59, 26],
    "held": [60, 61], "sit": [26], "loaf": [29],
    "rest-chain": [0, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33],
}
for name, frames in groups.items():
    strip(name, frames, per_row=6 if name == "rest-chain" else 8)
strip("all", list(range(62)), per_row=8)
print("ok")
