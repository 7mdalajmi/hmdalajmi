#!/usr/bin/env python3
"""Draw صكة's app icon: 1024 × 1024, RGB with no alpha.

Usage (from the repository root):  python3 tools/make_icon.py
Needs Pillow and Node with Playwright's Chromium (the cloud machine has both: /opt/npm-tools/node_modules/playwright).

Design (spec §10): flat charcoal #1B1A17; a cream #F3EEE4 ring, radius 352 px, 16 px stroke; one gold #D6B06A dot,
52 px across, on the ring at 12 o'clock, where the win screen's ring starts drawing; «صكة» in Amiri Bold about
318 px, cream, optically centred: the word is drawn, its ink is measured, and it is moved so the ink sits in the
middle of the ring. Chromium shapes the Arabic with the bundled Amiri, so the letters join as they should.
"""
import json
import os
import subprocess
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "Sakka", "Resources", "Fonts", "Amiri-Bold.ttf")
OUT = os.path.join(ROOT, "Sakka", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
PLAYWRIGHT = os.environ.get("PLAYWRIGHT_MODULE", "/opt/npm-tools/node_modules/playwright/index.mjs")

SIZE, RING_R, RING_W, DOT_D, WORD_PX = 1024, 352, 16, 52, 318
BG, CREAM, GOLD = "#1B1A17", "#F3EEE4", "#D6B06A"


def page(dx, dy, word=True):
    c = SIZE / 2
    text = f"""<div style="position:absolute;left:0;top:0;width:{SIZE}px;height:{SIZE}px;display:flex;align-items:center;
      justify-content:center;transform:translate({dx}px,{dy}px)"><span dir="rtl" style="font-family:IconAmiri;font-size:{WORD_PX}px;
      line-height:1;color:{CREAM}">صكة</span></div>""" if word else ""
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
    @font-face {{ font-family: IconAmiri; src: url("file://{FONT}"); }}
    html,body {{ margin:0; width:{SIZE}px; height:{SIZE}px; background:{BG}; overflow:hidden; }}
    </style></head><body>
    <svg width="{SIZE}" height="{SIZE}" style="position:absolute;left:0;top:0">
      <circle cx="{c}" cy="{c}" r="{RING_R}" fill="none" stroke="{CREAM}" stroke-width="{RING_W}"/>
      <circle cx="{c}" cy="{c - RING_R}" r="{DOT_D / 2}" fill="{GOLD}"/>
    </svg>{text}</body></html>"""


def shoot(html, png, workdir):
    src = os.path.join(workdir, "icon.html")
    with open(src, "w", encoding="utf-8") as f:
        f.write(html)
    script = f"""
import {{ chromium }} from {json.dumps(PLAYWRIGHT)};
const b = await chromium.launch();
const p = await b.newPage({{ viewport: {{ width: {SIZE}, height: {SIZE} }}, deviceScaleFactor: 1 }});
await p.goto('file://{src}');
await p.evaluate(() => document.fonts.ready);
await p.waitForTimeout(200);
await p.screenshot({{ path: {json.dumps(png)} }});
await b.close();
"""
    js = os.path.join(workdir, "shoot.mjs")
    with open(js, "w") as f:
        f.write(script)
    subprocess.run(["node", js], check=True)


def ink_box(png):
    """The box of the word's cream pixels, inside the ring."""
    im = Image.open(png).convert("RGB")
    c = SIZE / 2
    xs, ys = [], []
    for y in range(0, SIZE, 2):
        for x in range(0, SIZE, 2):
            if (x - c) ** 2 + (y - c) ** 2 > (RING_R - RING_W) ** 2:
                continue
            r, g, b = im.getpixel((x, y))
            if r > 150 and g > 150 and b > 150:
                xs.append(x)
                ys.append(y)
    return min(xs), min(ys), max(xs), max(ys)


def main():
    with tempfile.TemporaryDirectory() as work:
        first = os.path.join(work, "first.png")
        shoot(page(0, 0), first, work)
        x0, y0, x1, y1 = ink_box(first)
        dx = round(SIZE / 2 - (x0 + x1) / 2)
        dy = round(SIZE / 2 - (y0 + y1) / 2)
        final = os.path.join(work, "final.png")
        shoot(page(dx, dy), final, work)
        Image.open(final).convert("RGB").save(OUT, "PNG")
        x0, y0, x1, y1 = ink_box(final)
    im = Image.open(OUT)
    print(f"wrote {os.path.relpath(OUT, ROOT)}: {im.size[0]}x{im.size[1]} {im.mode}, word box {x1 - x0}x{y1 - y0} "
          f"centred at ({(x0 + x1) / 2:.0f}, {(y0 + y1) / 2:.0f}), moved by ({dx}, {dy})")


if __name__ == "__main__":
    main()
