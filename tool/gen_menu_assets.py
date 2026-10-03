"""Generate the Flappy Spikes 2.0 menu art (icons + bird skins).

Run (needs Pillow + Playwright's Chromium):

    uv run --with pillow --with playwright python tool/gen_menu_assets.py \
        --design ../design/menu_v2 [--app .] [--contact /tmp/contact.png]

Outputs (all under <app>/assets/images/):

* ``menu/*.png`` + ``menu/manifest.json`` -- UI icons rasterised straight
  from the inline SVGs of the approved HTML mocks (headless Chromium,
  deviceScaleFactor 4, transparent background). Every PNG is exactly
  4x the logical size recorded in the manifest ({name: [w, h]}).
* ``skins/*.png`` + ``skins/manifest.json`` -- 11 bird skins x 3 frames,
  built from the original ``bird*.png`` sprites. Each skin is two layers:
  a greyscale *tinted* layer (drawn with the stage foreground colour as a
  ``modulate`` ColorFilter, like pipes/spikes) and an untinted *overlay*
  (beak, eye, accessories) drawn on top. Plus full-colour menu previews
  rasterised from the skins mock (``<id>_preview.png`` /
  ``<id>_preview_locked.png``).

The mocks are the source of truth; this script only *copies* their SVG
markup, so re-running it after a mock change reproduces the art.
"""

from __future__ import annotations

import argparse
import json
import random
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat

SCALE = 4  # icon PNG pixels per logical point
SKIN_PX = 2  # bird sprites are 2 px per point (bird.png = 93x59 = 46.5x29.5 pt)

ROOT_VARS = {
    "--bg": "#F1F1F1",
    "--fg": "#828282",
    "--pink": "#EC008C",
    "--soft": "#FCD9EE",
    "--ui": "#FF4FB7",
    "--gold": "#FFB529",
    "--plum": "#7A0044",
}
PINK = (0xEC, 0x00, 0x8C)
PINK_DARK = (0xC4, 0x00, 0x73)
GOLD = (0xFF, 0xB5, 0x29)
# .card / .sk background at stage 0: color-mix(in srgb, #828282 14%, #F1F1F1)
CARD = tuple(round(0.14 * a + 0.86 * b) for a, b in zip((0x82,) * 3, (0xF1,) * 3))

HOME = "screen_home_centered.html"
SHOP = "screen_shop_s1_fix.html"
SKINS = "screen_skins.html"
POPUP = "screen_popup.html"
SHIELD = "screen_shield3.html"

# Mock screenshots (phone renders) used for the verification crops.
MOCK_PNG = {
    (HOME, 0): "home_v2_a.png",
    (HOME, 1): "home_v2_b.png",
    (SHOP, 1): "shop_s1b.png",
    (SKINS, 0): "skins_k1.png",
    (POPUP, 0): "popup_p1.png",
}

# name -> primary source (page, phone index, css selector, match index, bg)
# plus extra usages to verify against. The primary source fixes the logical
# size (largest usage, so smaller usages are clean downscales).
# Shop pack art: n coins of size c pt, each `step` pt below the previous one,
# the lower coin painted over the upper. The mock's markup derives the overlap
# from its font's line box, so the layout was fitted against shop_s1b.png
# (quarter-pt search, mean error < 0.5/255); all stacks bottom-align at the
# card's top + 78 pt and are centred in the 142 pt card.
# n: (coin size, step, card left, card top)
COIN_STACKS = {1: (28, 0, 14, 266), 2: (28, 15, 164, 266),
               3: (20, 12, 14, 426), 4: (20, 12, 164, 426)}
ICONS = {
    "shop": [(HOME, 0, ".wide .tile svg", 0, PINK)],
    "skins": [(HOME, 0, ".wide .tile svg", 1, PINK)],
    "invite": [(HOME, 0, ".wide .tile svg", 2, PINK)],
    "noads": [
        (POPUP, 0, 'div[style*="height:120px"] > svg', 0, PINK),
        (HOME, 0, ".wide .tile svg", 3, PINK),
        (SHOP, 1, ".pbtn > svg", 0, PINK),
        (POPUP, 0, ".sq svg", 0, PINK),
    ],
    "trophy": [(HOME, 0, ".abs > .tile svg", 0, PINK)],
    "shield": [(SHIELD, None, 'svg[width="58"]', 0, PINK)],
    "shield_slot": [(HOME, 1, ".hoops svg", 1, GOLD)],
    "video": [(HOME, 0, ".hoops svg", 0, GOLD)],
    "video_soft": [(SHOP, 1, ".gbtn .pbtn svg", 0, PINK)],
    "play": [(HOME, 0, ".start svg", 0, PINK)],
    "coin": [
        (SHOP, 1, ".gbtn svg.coin", 0, GOLD),
        (HOME, 0, ".pill svg.coin", 0, PINK),
        (POPUP, 0, ".sq svg.coin", 0, PINK),
        (SKINS, 0, ".price svg.coin", 0, PINK),
    ],
    "lock": [(SKINS, 0, '.sk.lock > div[style*="left:6px"] svg', 0, CARD)],
    "check": [(SKINS, 0, ".chk svg", 0, PINK)],
    "plus": [(HOME, 0, ".pill .plus svg", 0, PINK_DARK)],
    "close": [(POPUP, 0, ".back svg", 0, PINK_DARK)],
    # The mock's back chevron / gear differ from the 1.0 back_arrow.png and
    # settings_gear.png (filled arrow, rounded gear), so both are new.
    "back": [(SHOP, 1, ".back svg", 0, PINK)],
    "gear": [(HOME, 0, ".gear svg", 0, PINK)],
}
# Glyph parts the mock paints in tile-pink are real cut-outs (transparent),
# so the icon also reads on a pressed/darker tile.
CUTOUT_ICONS = {"shop", "skins", "trophy"}

SKIN_IDS = [
    "pink", "blue", "green", "purple", "grey", "sand",
    "crown", "tophat", "sunglasses", "headband", "partyhat", "ghost",
]

JS_PROBE = """
([phoneIdx, sel, idx]) => {
  let scope = document, k = 1, ox = 0, oy = 0;
  if (phoneIdx !== null) {
    scope = document.querySelectorAll('.phone')[phoneIdx];
    const pr = scope.getBoundingClientRect();
    k = 320 / pr.width; ox = pr.x; oy = pr.y;
  }
  const el = scope.querySelectorAll(sel)[idx];
  if (!el) return null;
  let r = el.getBoundingClientRect();
  if (el.tagName.toLowerCase() !== 'svg') {
    // container (coin stack): union of the coin svgs, which overflow it
    let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    for (const s of el.querySelectorAll('svg')) {
      const q = s.getBoundingClientRect();
      x0 = Math.min(x0, q.left); y0 = Math.min(y0, q.top);
      x1 = Math.max(x1, q.right); y1 = Math.max(y1, q.bottom);
    }
    r = {x: x0, y: y0, width: x1 - x0, height: y1 - y0};
  }
  const cs = getComputedStyle(el);
  return {x: (r.x - ox) * k, y: (r.y - oy) * k, w: r.width * k, h: r.height * k,
          html: el.outerHTML, color: cs.color, fill: cs.fill,
          pw: el.parentElement.getBoundingClientRect().width * k};
}
"""


def resolve_vars(s: str) -> str:
    for k, v in ROOT_VARS.items():
        s = s.replace(f"var({k})", v)
    return s


def cutout(svg: str) -> str:
    """Turn every element filled with tile pink into a transparent hole."""
    holes = re.findall(r'<(?:path|rect|circle)[^>]*fill="#EC008C"[^>]*/>', svg)
    if not holes:
        return svg
    for h in holes:
        svg = svg.replace(h, "")
    mask_els = "".join(h.replace('fill="#EC008C"', 'fill="#000"') for h in holes)
    head_end = svg.index(">") + 1
    body_end = svg.rindex("</svg>")
    mask = (
        '<defs><mask id="cut" maskUnits="userSpaceOnUse" x="-50" y="-50" '
        'width="200" height="200"><rect x="-50" y="-50" width="200" height="200" '
        f'fill="#fff"/>{mask_els}</mask></defs>'
    )
    return (svg[:head_end] + mask + '<g mask="url(#cut)">'
            + svg[head_end:body_end] + "</g></svg>")


def standalone_page(inner: str, color: str, fill: str, width: float | None) -> str:
    w = f"width:{width}px;" if width else ""
    return (
        "<!doctype html><html><head><style>*{box-sizing:border-box;margin:0}"
        "html,body{background:transparent}"
        f":root{{{';'.join(f'{k}:{v}' for k, v in ROOT_VARS.items())}}}"
        "</style></head><body>"
        f'<div id="w" style="position:absolute;left:40px;top:60px;{w}'
        f'display:flex;flex-direction:column;align-items:center;color:{color};fill:{fill}">'
        f"{inner}</div></body></html>"
    )


class Renderer:
    def __init__(self, pw, design: Path):
        self.design = design
        self.browser = pw.chromium.launch()
        self.mock = self.browser.new_page(viewport={"width": 1600, "height": 1200})
        self.loaded = None
        self.page = self.browser.new_page(
            viewport={"width": 400, "height": 400}, device_scale_factor=SCALE)

    def probe(self, html_name, phone, sel, idx):
        if self.loaded != html_name:
            self.mock.goto((self.design / html_name).as_uri(), wait_until="domcontentloaded")
            self.mock.evaluate("document.fonts.ready")
            self.mock.wait_for_timeout(150)
            self.loaded = html_name
        info = self.mock.evaluate(JS_PROBE, [phone, sel, idx])
        if info is None:
            raise SystemExit(f"selector not found: {html_name} #{phone} {sel}[{idx}]")
        return info

    def render(self, html: str, clip_sel: str, wrapper_css: str = "") -> Image.Image:
        """Rasterise; clip = union of the svgs inside #w (logical px)."""
        self.page.set_content(html)
        if wrapper_css:
            self.page.evaluate(
                "css => document.getElementById('w').setAttribute('style', "
                "document.getElementById('w').getAttribute('style') + css)", wrapper_css)
        box = self.page.evaluate(
            """sel => { let x0=1e9,y0=1e9,x1=-1e9,y1=-1e9;
              for (const s of document.querySelectorAll(sel)) { const q=s.getBoundingClientRect();
                x0=Math.min(x0,q.left);y0=Math.min(y0,q.top);x1=Math.max(x1,q.right);y1=Math.max(y1,q.bottom);}
              return {x:x0,y:y0,width:x1-x0,height:y1-y0}; }""", clip_sel)
        png = self.page.screenshot(clip=box, omit_background=True)
        from io import BytesIO
        return Image.open(BytesIO(png)).convert("RGBA"), (box["width"], box["height"])

    def close(self):
        self.browser.close()


def prepare_svg(info, w, h, name) -> str:
    svg = resolve_vars(info["html"])
    svg = re.sub(r'\sclass="[^"]*"', "", svg, count=1)
    # pin the rendered size to the size the mock laid it out at
    svg = re.sub(r'\swidth="[^"]*"', "", svg, count=1)
    svg = re.sub(r'\sheight="[^"]*"', "", svg, count=1)
    svg = svg.replace("<svg", f'<svg width="{w}" height="{h}"', 1)
    if name in CUTOUT_ICONS:
        svg = cutout(svg)
    return svg


def gen_icons(r: Renderer, out: Path):
    out.mkdir(parents=True, exist_ok=True)
    manifest, checks = {}, []
    for name, uses in ICONS.items():
        page, phone, sel, idx, bg = uses[0]
        info = r.probe(page, phone, sel, idx)
        w, h = round(info["w"] * 4) / 4, round(info["h"] * 4) / 4
        inner = prepare_svg(info, w, h, name)
        img, (lw, lh) = r.render(standalone_page(inner, info["color"], info["fill"], None),
                                 "#w > svg")
        lw, lh = round(lw * 4) / 4, round(lh * 4) / 4
        target = (round(lw * SCALE), round(lh * SCALE))
        if img.size != target:
            img = img.resize(target, Image.LANCZOS)
        img.save(out / f"{name}.png", optimize=True)
        manifest[name] = [lw, lh]
        for (pg, ph, s, i, b) in uses:
            if (pg, ph) in MOCK_PNG:
                checks.append((name, img, r.probe(pg, ph, s, i), (pg, ph), b))
        print(f"icon {name:14s} {lw}x{lh} pt -> {img.size}")
    coin = Image.open(out / "coin.png").convert("RGBA")
    for n, (c, step, cx, cy) in COIN_STACKS.items():
        lh = c + (n - 1) * step
        img = Image.new("RGBA", (c * SCALE, lh * SCALE), (0, 0, 0, 0))
        glyph = coin.resize((c * SCALE, c * SCALE), Image.LANCZOS)
        for i in range(n):
            img.alpha_composite(glyph, (0, i * step * SCALE))
        name = f"coin_stack_{n}"
        img.save(out / f"{name}.png", optimize=True)
        manifest[name] = [c, lh]
        info = {"x": cx + (142 - c) / 2, "y": cy + 78 - lh, "w": c, "h": lh}
        checks.append((name, img, info, (SHOP, 1), CARD))
        print(f"icon {name:14s} {c}x{lh} pt -> {img.size}")
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return checks


# --------------------------------------------------------------------------
# Skins
# --------------------------------------------------------------------------

TOP_PAD = 34  # px of headroom above the original sprite for hats (17 pt)
CANVAS = (93, 59 + TOP_PAD)

# Mock bird space (skins mock: body rect x 6..36, y 3..33) -> sprite px.
SX, SY = 58.5 / 30, 59 / 30


def mx(x):
    return 16.5 + (x - 6) * SX


def my(y):
    return TOP_PAD + (y - 3) * SY


# Per-skin shades for the tinted layer (1.0 = full stage colour).
# body / wing (wing also colours the tail, like the mock's darker tail).
SKIN_LOOKS = {
    "blue": dict(body=0.86, wing=0.56, pattern="belly"),
    "green": dict(body=0.72, wing=0.46, pattern="stripe"),
    "purple": dict(body=0.50, wing=0.30, pattern="twotone"),
    "grey": dict(body=0.62, wing=0.42, pattern="speckle"),
    "sand": dict(body=0.94, wing=0.70, pattern="spots"),
    "crown": dict(body=0.80, wing=0.56),
    "tophat": dict(body=1.00, wing=0.64),
    "sunglasses": dict(body=0.86, wing=0.58),
    "headband": dict(body=0.30, wing=0.16),
    "partyhat": dict(body=0.68, wing=0.45),
    "ghost": dict(body=1.00, wing=0.80, alpha=0.78, pattern="ghost"),
}
# Mock body colour of each skin (screen_skins.html K1), for reference only.
MOCK_COLOURS = {
    "pink": "#EC008C", "blue": "#29B6F6", "green": "#7CB342", "purple": "#8E24AA",
    "grey": "#37474F", "sand": "#FFB300", "crown": "#EC008C", "tophat": "#FAFAFA",
    "sunglasses": "#FF7043", "headband": "#212121", "partyhat": "#26A69A",
    "ghost": "#ECEFF1",
}

SS = 8  # supersampling for vector accessories


def poly_layer(shapes):
    """shapes: list of (kind, coords_in_canvas_px, rgba). Returns AA RGBA image."""
    big = Image.new("RGBA", (CANVAS[0] * SS, CANVAS[1] * SS), (0, 0, 0, 0))
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    for kind, pts, col in shapes:
        layer = Image.new("RGBA", big.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        if kind == "poly":
            d.polygon([(x * SS, y * SS) for x, y in pts], fill=col)
        elif kind == "rect":
            x0, y0, x1, y1 = pts
            d.rectangle([x0 * SS, y0 * SS, x1 * SS - 1, y1 * SS - 1], fill=col)
        elif kind == "circle":
            cx, cy, rr = pts
            d.ellipse([(cx - rr) * SS, (cy - rr) * SS, (cx + rr) * SS, (cy + rr) * SS], fill=col)
        out.alpha_composite(layer.resize(CANVAS, Image.LANCZOS))
    return out


def mrect(x, y, w, h):
    return (mx(x), my(y), mx(x + w), my(y + h))


def accessory(skin_id):
    hexc = lambda s: tuple(int(s[i:i + 2], 16) for i in (1, 3, 5)) + (255,)
    if skin_id == "crown":
        return [("poly", [(mx(x), my(y)) for x, y in
                          [(9, 3.3), (9, -3), (13, 0), (16, -4), (19, 0), (23, -3), (23, 3.3)]],
                 hexc("#FFB529"))]
    if skin_id == "tophat":
        return [("rect", mrect(10, -6, 20, 9), hexc("#222222")),
                ("rect", mrect(5, 1, 30, 3), hexc("#222222")),
                ("rect", mrect(10, -1, 20, 2), hexc("#EC008C"))]
    if skin_id == "sunglasses":
        return [("rect", mrect(21, 8.5, 12, 6), hexc("#222222")),
                ("rect", mrect(18, 10, 4, 2), hexc("#222222"))]
    if skin_id == "headband":
        # mock: band y 5..10 + tails; nudged up 1.5 so it clears the sprite's
        # (larger) eye.
        return [("rect", mrect(6, 3.5, 30, 5), hexc("#E53935")),
                ("poly", [(mx(6), my(5.5)), (mx(-1), my(2.5)), (mx(-1), my(11.5))],
                 hexc("#E53935"))]
    if skin_id == "partyhat":
        return [("poly", [(mx(14), my(3.3)), (mx(20), my(-10)), (mx(26), my(3.3))],
                 hexc("#26C6DA")),
                ("circle", (mx(20), my(-11), 2.5 * SX), hexc("#FFB529"))]
    return []


def classify(src: Image.Image, frame: str):
    """Split an original sprite into (tinted-mask data, beak, eye overlay).

    Returns per-pixel arrays over the 93x59 sprite:
      a[x,y]   alpha of the body (tinted) layer
      t[x,y]   wing fraction 0..1
      beak     RGBA image of the beak (untinted)
      eye      RGBA image of the eye (white square or dead X)
    """
    w, h = src.size
    px = src.load()
    body_g = 40 if frame == "dead" else 0
    alpha = [[0] * h for _ in range(w)]
    wing = [[0.0] * h for _ in range(w)]
    beak = Image.new("RGBA", src.size, (0, 0, 0, 0))
    eye = Image.new("RGBA", src.size, (0, 0, 0, 0))
    bp, ep = beak.load(), eye.load()
    for y in range(h):
        # reference beak colour for this row (fully inside the beak)
        ref = px[78, y]
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if x >= 74:
                if x >= 77 or ref[3] == 0:
                    f = 1.0 if x >= 76 else 0.0
                else:
                    f = max(0.0, min(1.0, (g - body_g) / max(1, ref[1] - body_g)))
                if x >= 77:
                    bp[x, y] = (r, g, b, a)
                elif f > 0.02 and ref[3]:
                    bp[x, y] = (ref[0], ref[1], ref[2], round(a * f))
                # keep the body solid under the beak's soft edge so the two
                # layers don't leak background between them
                if x < 77:
                    alpha[x][y] = a if (x <= 75 and ref[3]) else round(a * (1 - f))
                continue
            alpha[x][y] = a
            in_eye = 51 <= x <= 70 and 7 <= y <= 27
            if in_eye:
                f = max(0.0, min(1.0, (g - body_g) / (255 - body_g)))
                if f > 0.02:
                    ep[x, y] = (255, 255, 255, round(255 * f))
                continue
            if frame == "dead":
                wing[x][y] = max(0.0, min(1.0, (g - 40) / 43))
            else:
                wing[x][y] = max(0.0, min(1.0, (140 - b) / 74))
    return alpha, wing, beak, eye


def in_tail(x, y):
    return x < 16.5 and 17 <= y <= 35


def pattern_value(skin, x, y, base, wingv, t, rnd_spots):
    """Grey level (0..1) for canvas-relative sprite pixel (x, y) (sprite space)."""
    p = skin.get("pattern")
    body = base
    if p == "belly":
        # lighter rounded belly patch under the eye/wing
        dx, dy = (x - 54) / 26, (y - 62) / 18
        if dx * dx + dy * dy < 1.0:
            body = 1.0
    elif p == "twotone" and y >= 30:
        body = 0.68
    elif p == "speckle":
        v = rnd_spots.get((x // 2, y // 2))
        if v is not None:
            body = v
    elif p == "spots":
        for cx, cy, rr in rnd_spots["spots"]:
            if (x - cx) ** 2 + (y - cy) ** 2 <= rr * rr:
                body = 0.74
                break
    w = wingv
    if p == "stripe" and 34 <= x <= 37:  # vertical band: hits both wing poses
        w = 0.86
    if in_tail(x, y):
        return wingv
    return body * (1 - t) + w * t


def speckles(seed):
    rnd = random.Random(seed)
    sp = {}
    for _ in range(46):
        cx, cy = rnd.randrange(9, 37), rnd.randrange(0, 29)
        if 26 <= cx <= 34 and 4 <= cy <= 13:  # keep the eye clean
            continue
        sp[(cx, cy)] = rnd.choice([0.46, 0.80])
    return sp


SAND_SPOTS = {"spots": [(24, 47, 3.5), (37, 40, 3), (50, 51, 3.5), (66, 42, 3),
                        (30, 7, 2.5), (62, 30, 2.5), (42, 30, 2), (21, 33, 2.5)]}


def build_skin(skin_id, srcs):
    skin = SKIN_LOOKS[skin_id]
    acc = poly_layer(accessory(skin_id))
    outs = {}
    for frame, src in srcs.items():
        alpha, wing, beak, eye = classify(src, frame)
        tint = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        tp = tint.load()
        rnd = (speckles(7) if skin.get("pattern") == "speckle" else SAND_SPOTS)
        ga = skin.get("alpha", 1.0)
        for x in range(src.width):
            for y in range(src.height):
                a = alpha[x][y]
                if a == 0:
                    continue
                v = pattern_value(skin, x, y, skin["body"], skin["wing"], wing[x][y], rnd)
                if frame == "dead":
                    # mirror the 1.0 dead sprite: dark body, lighter wing
                    b0 = pattern_value(skin, x, y, skin["body"], skin["body"], 0, rnd) * 0.36
                    v = b0 * (1 - wing[x][y]) + min(1.0, b0 * 2.1) * wing[x][y]
                    if in_tail(x, y):
                        v = b0 * 1.4
                if skin.get("pattern") == "ghost":
                    # wavy (zig-zag) bottom edge: 6 teeth, 3 pt deep
                    ph = ((x - 16.5) % 10) / 10
                    edge = 59 - 6 * (1 - abs(2 * ph - 1)) if x >= 16 else 99
                    if y >= edge:
                        continue
                g = max(0, min(255, round(v * 255)))
                tp[x, y + TOP_PAD] = (g, g, g, round(a * ga))
        over = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        over.alpha_composite(beak, (0, TOP_PAD))
        if skin_id != "sunglasses":  # the shades cover the eye (and the dead X)
            over.alpha_composite(eye, (0, TOP_PAD))
        over.alpha_composite(acc)
        outs[frame] = (tint, over)
    return outs


def gen_skins(r: Renderer, app: Path, out: Path):
    out.mkdir(parents=True, exist_ok=True)
    img_dir = app / "assets/images"
    srcs = {f: Image.open(img_dir / n).convert("RGBA") for f, n in
            [("idle", "bird.png"), ("flap", "bird_flap.png"), ("dead", "bird_dead.png")]}
    suffix = {"idle": "", "flap": "_flap", "dead": "_dead"}
    size_pt = [CANVAS[0] / SKIN_PX, CANVAS[1] / SKIN_PX]
    anchor_y = (TOP_PAD + 59 / 2) / CANVAS[1]
    # Paths are relative to assets/images/. Frames are [idle, flap, dead]
    # (same roles as bird.png, bird_flap.png, bird_dead.png). Draw "tinted"
    # with ColorFilter.mode(stageForeground, BlendMode.modulate), then
    # "overlay" untinted on top, both at "size" (pt) with "anchor" on the
    # bird body centre (= the 1.0 bird position; hitbox unchanged). "offset"
    # is the canvas top-left relative to the 1.0 bird.png top-left, in pt.
    # "preview"/"previewLocked" are full-colour menu renders from the skins
    # mock (48x52 pt box, viewBox -2 -14 48 52).
    manifest = {
        "pink": {
            "tinted": None,
            "overlay": ["bird.png", "bird_flap.png", "bird_dead.png"],
            "size": [93 / SKIN_PX, 59 / SKIN_PX], "offset": [0, 0], "anchor": [0.5, 0.5],
            "preview": "skins/pink_preview.png", "previewLocked": "skins/pink_preview_locked.png",
            "previewSize": [48, 52], "mockColor": MOCK_COLOURS["pink"],
        },
    }
    built = {}
    for sid in SKIN_IDS[1:]:
        frames = build_skin(sid, srcs)
        built[sid] = frames
        tl, ol = [], []
        for f in ("idle", "flap", "dead"):
            t, o = frames[f]
            t.save(out / f"{sid}{suffix[f]}.png", optimize=True)
            o.save(out / f"{sid}_acc{suffix[f]}.png", optimize=True)
            tl.append(f"skins/{sid}{suffix[f]}.png")
            ol.append(f"skins/{sid}_acc{suffix[f]}.png")
        manifest[sid] = {
            "tinted": tl, "overlay": ol, "size": size_pt,
            "offset": [0, -TOP_PAD / SKIN_PX], "anchor": [0.5, round(anchor_y, 6)],
            "preview": f"skins/{sid}_preview.png",
            "previewLocked": f"skins/{sid}_preview_locked.png",
            "previewSize": [48, 52], "mockColor": MOCK_COLOURS[sid],
        }
    # full-colour previews straight from the K1 mock
    previews = {}
    for i, sid in enumerate(SKIN_IDS):
        info = r.probe(SKINS, 0, ".sk .b svg", i)
        svg = resolve_vars(info["html"])
        for locked in (False, True):
            css = ";opacity:.45;filter:grayscale(.6)" if locked else ""
            img, _ = r.render(standalone_page(f"<div>{svg}</div>", info["color"],
                                              info["fill"], None), "#w svg", css)
            img = img.resize((48 * SCALE, 52 * SCALE), Image.LANCZOS) \
                if img.size != (48 * SCALE, 52 * SCALE) else img
            name = f"{sid}_preview{'_locked' if locked else ''}.png"
            img.save(out / name, optimize=True)
            previews[(sid, locked)] = (img, info)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"skins: {len(SKIN_IDS) - 1} x 3 frames x 2 layers + {len(previews)} previews")
    return built, previews, srcs


# --------------------------------------------------------------------------
# Contact sheet
# --------------------------------------------------------------------------

def stage_colours(app: Path):
    txt = (app / "lib/game/palettes.dart").read_text()
    res = {}
    for m in re.finditer(r"(\d+): Palette\(Color\(0xFF(\w{6})\), Color\(0xFF(\w{6})\)\)", txt):
        res[int(m.group(1))] = tuple(tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))
                                     for c in (m.group(2), m.group(3)))
    return res


def modulate(img: Image.Image, colour):
    r, g, b, a = img.split()
    r = r.point(lambda v: round(v * colour[0] / 255))
    g = g.point(lambda v: round(v * colour[1] / 255))
    b = b.point(lambda v: round(v * colour[2] / 255))
    return Image.merge("RGBA", (r, g, b, a))


def on_bg(img, bg, size=None):
    if size:
        img = img.resize(size, Image.LANCZOS)
    base = Image.new("RGBA", img.size, tuple(bg) + (255,))
    base.alpha_composite(img)
    return base


def compare(m, info, img, bg, margin=5):
    """Place `img` where the mock drew it and return (mine, mock crop,
    |diff| x4, mean abs error). The live mock layout can sit a few px off
    the PNG (font metrics), so the placement is searched: whole px within
    +-4, then quarter px around the best."""
    k = m.width / 320
    x0 = int(info["x"] * k) - margin
    y0 = int(info["y"] * k) - margin
    x1 = int((info["x"] + info["w"]) * k + 0.999) + margin
    y1 = int((info["y"] + info["h"]) * k + 0.999) + margin
    crop = m.crop((x0, y0, x1, y1))
    q = 4
    sized = img.resize((round(info["w"] * k * q), round(info["h"] * k * q)), Image.LANCZOS)
    bx, by = round((info["x"] * k - x0) * q), round((info["y"] * k - y0) * q)

    def score(dx, dy):
        big = Image.new("RGBA", (crop.width * q, crop.height * q), tuple(bg) + (255,))
        big.alpha_composite(sized, (bx + dx, by + dy))
        mine = big.resize(crop.size, Image.BOX)
        diff = ImageChops.difference(mine.convert("RGB"), crop.convert("RGB"))
        return sum(ImageStat.Stat(diff).mean) / 3, mine, diff

    best = min(((score(dx, dy)[0], dx, dy) for dy in range(-4 * q, 4 * q + 1, q)
                for dx in range(-4 * q, 4 * q + 1, q)))
    _, cx, cy = best
    best = min(((score(dx, dy)[0], dx, dy) for dy in range(cy - q + 1, cy + q)
                for dx in range(cx - q + 1, cx + q)))
    mae, mine, diff = score(best[1], best[2])
    return mine, crop, diff.point(lambda v: min(255, v * 4)).convert("RGBA"), mae


def contact(design: Path, app: Path, checks, built, previews, srcs, path: Path):
    font = ImageFont.load_default()
    mocks = {k: Image.open(design / v).convert("RGBA") for k, v in MOCK_PNG.items()}
    rows = []
    # icons: mine (at the mock's pixel scale) | mock crop | |diff| x4
    for name, img, info, key, bg in checks:
        m = mocks[key]
        k = m.width / 320
        mine, crop, diff, mae = compare(m, info, img, bg)
        z = max(1, 96 // max(crop.size))
        tiles = [mine, crop, diff]
        tiles = [t.resize((t.width * z, t.height * z), Image.NEAREST) for t in tiles]
        rows.append((f"{name} @{info['w']:.0f}x{info['h']:.0f}pt {key[0][7:12]} MAE {mae:.1f}",
                     tiles))
    # previews vs skins_k1 crops
    m = mocks[(SKINS, 0)]
    for (sid, locked), (img, info) in previews.items():
        is_locked = sid in ("grey", "sand", "crown", "sunglasses", "headband", "partyhat", "ghost")
        if locked != is_locked:
            continue
        mine, crop, diff, mae = compare(m, info, img, CARD, margin=1)
        tiles = [mine, crop, diff]
        rows.append((f"preview {sid}{' locked' if locked else ''} MAE {mae:.1f}", tiles))

    # skins: 3 frames x stages 0/15/45, plus pink reference row
    pal = stage_colours(app)
    skin_rows = []
    z = 2
    for sid in ["pink"] + SKIN_IDS[1:]:
        tiles = []
        for st in (0, 15, 45):
            bg, fg = pal[st]
            for f in ("idle", "flap", "dead"):
                cell = Image.new("RGBA", CANVAS, bg + (255,))
                if sid == "pink":
                    cell.alpha_composite(srcs[f], (0, TOP_PAD))
                else:
                    t, o = built[sid][f]
                    cell.alpha_composite(modulate(t, fg))
                    cell.alpha_composite(o)
                tiles.append(cell.resize((CANVAS[0] * z, CANVAS[1] * z), Image.NEAREST))
        skin_rows.append((sid, tiles))

    pad, label_h = 8, 14
    W1 = max(sum(t.width for t in ts) + pad * (len(ts) + 1) for _, ts in rows)
    W2 = max(sum(t.width for t in ts) + pad * (len(ts) + 1) for _, ts in skin_rows)
    W = max(W1 * 2 + pad, W2)
    # icon rows in two columns
    half = (len(rows) + 1) // 2
    col_h = [sum(max(t.height for t in ts) + label_h + pad for _, ts in rows[:half]),
             sum(max(t.height for t in ts) + label_h + pad for _, ts in rows[half:])]
    H = max(col_h) + sum(max(t.height for t in ts) + label_h + pad for _, ts in skin_rows) + 40
    sheet = Image.new("RGBA", (W, H), (60, 60, 64, 255))
    d = ImageDraw.Draw(sheet)
    for c, chunk in enumerate((rows[:half], rows[half:])):
        y = pad
        for label, ts in chunk:
            x = pad + c * (W1 + pad)
            d.text((x, y), label, fill=(255, 255, 255, 255), font=font)
            y += label_h
            for t in ts:
                sheet.alpha_composite(t, (x, y))
                x += t.width + pad
            y += max(t.height for t in ts) + pad
    y = max(col_h) + 20
    d.text((pad, y), "skins: stage 0 | stage 15 | stage 45  (idle, flap, dead each)",
           fill=(255, 255, 0, 255), font=font)
    y += 16
    for label, ts in skin_rows:
        d.text((pad, y), label, fill=(255, 255, 255, 255), font=font)
        y += label_h
        x = pad
        for i, t in enumerate(ts):
            sheet.alpha_composite(t, (x, y))
            x += t.width + (pad * 3 if i % 3 == 2 else 2)
        y += ts[0].height + pad
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(path)
    print(f"contact sheet -> {path}")


def find_design(start: Path) -> Path | None:
    for p in [start, *start.parents]:
        if (p / "design/menu_v2").is_dir():
            return p / "design/menu_v2"
    return None


def main():
    here = Path(__file__).resolve().parent
    default_app = here.parent if here.name == "tool" else here.parent / "flappy_spikes"
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--app", type=Path, default=default_app, help="Flutter app root")
    ap.add_argument("--design", type=Path, default=None, help="design/menu_v2 dir")
    ap.add_argument("--contact", type=Path, default=None, help="write a verification sheet")
    a = ap.parse_args()
    design = a.design or find_design(here) or find_design(Path.cwd())
    if not design or not (design / HOME).exists():
        sys.exit("design/menu_v2 not found; pass --design")
    from playwright.sync_api import sync_playwright
    with sync_playwright() as pw:
        r = Renderer(pw, design.resolve())
        try:
            checks = gen_icons(r, a.app / "assets/images/menu")
            built, previews, srcs = gen_skins(r, a.app, a.app / "assets/images/skins")
        finally:
            r.close()
    if a.contact:
        contact(design, a.app, checks, built, previews, srcs, a.contact)


if __name__ == "__main__":
    main()
