#!/usr/bin/env python3
"""One-off asset generator for the website (PRD-2.3 §5.4 / §11.3 performance). Writes hosting/src/gen/.

Needs fonttools, brotli and pillow, plus rsvg-convert (librsvg) on PATH:
    uv run --with fonttools --with brotli --with pillow python hosting/tools/make_assets.py
The outputs are committed, so hosting/build.py itself needs only the standard library.

- fonts: the game's three fonts as subset WOFF2 (Basic Latin, Latin-1 and the typographic punctuation the
  pages and canvases use);
- icons: the 17C renders (favicon.ico 16/32/48, icon-48/96/192/512 PNG, apple-touch-icon 180, header/footer
  WebP at 1x and 2x), all rendered from icon_concepts/17c_clean_flap_big_eyes_cyan.svg;
- store badges as WebP at 2x their largest display size;
- the 2014 sprites shown on /story (copied from FlappySpikes/, read only).
"""
import io, pathlib, shutil, subprocess
from fontTools import subset
from fontTools.ttLib import TTFont
from PIL import Image

HOST = pathlib.Path(__file__).resolve().parents[1]
REPO = HOST.parent
SRC = HOST / 'src'
GEN = SRC / 'gen'
ORIG = REPO.parents[1] / 'FlappySpikes' / 'Flappy Spikes'     # the 2014 game (workspace, read only)
if not ORIG.exists():
    ORIG = REPO.parent / 'FlappySpikes' / 'Flappy Spikes'
GEN.mkdir(parents=True, exist_ok=True)

# ---------- fonts ----------
UNICODES = list(range(0x20, 0x7F)) + list(range(0xA0, 0x100)) + [
    0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026, 0x00D7, 0x2192, 0x2190, 0x20AC, 0x2122, 0x00B7]
for src, out in (('Opificio_neue-regular.ttf', 'opificio.woff2'), ('Fredoka-SemiBold.ttf', 'fredoka.woff2'), ('LVDCC.TTF', 'lvdc.woff2')):
    opts = subset.Options(); opts.flavor = 'woff2'; opts.layout_features = ['*']; opts.name_IDs = ['*']; opts.notdef_outline = True
    f = TTFont(REPO / 'assets/fonts' / src)
    s = subset.Subsetter(opts); s.populate(unicodes=UNICODES); s.subset(f)
    f.flavor = 'woff2'; f.save(GEN / out)
    print(out, (GEN / out).stat().st_size)

# ---------- 17C icon renders ----------
SVG = SRC / 'img/icon_17c.svg'
def render(px):
    png = subprocess.run(['rsvg-convert', '-w', str(px), '-h', str(px), str(SVG)], check=True, capture_output=True).stdout
    return Image.open(io.BytesIO(png)).convert('RGBA')
for px, name in ((48, 'icon-48.png'), (96, 'icon-96.png'), (192, 'icon-192.png'), (512, 'icon-512.png'), (180, 'apple-touch-icon.png')):
    im = render(px)
    if name == 'apple-touch-icon.png':
        im = im.convert('RGB')                                   # iOS adds its own mask; no alpha
    im.save(GEN / name, optimize=True)
for px in (28, 40, 56, 80):                                      # header 40 pt and footer 28 pt slots, 1x and 2x
    render(px).save(GEN / f'icon-{px}.webp', quality=90, method=6)
ico = render(256)
ico.save(GEN / 'favicon.ico', sizes=[(16, 16), (32, 32), (48, 48)])

# ---------- store badges (600 x 178 sources, shown at 58 px / 38 px high) ----------
for n in ('gp', 'as'):
    im = Image.open(SRC / f'img/{n}.png').convert('RGBA')
    w = round(im.width * 116 / im.height)
    im.resize((w, 116), Image.LANCZOS).save(GEN / f'{n}.webp', quality=92, method=6)

# ---------- 2014 sprites for /story ----------
(GEN / '2014').mkdir(exist_ok=True)
for n in ('bird@2x.png', 'bird_flap@2x.png', 'pipe_top@2x.png', 'pipe_bottom@2x.png'):
    shutil.copyfile(ORIG / n, GEN / '2014' / n.replace('@2x', ''))
for p in sorted(GEN.rglob('*')):
    if p.is_file():
        print(p.relative_to(GEN), p.stat().st_size)

# ---------- the contact address as an SVG of glyph paths (PRD-2.3 §5.2 <noscript> fallback: no text to scrape) ----------
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
def text_svg(text, font_path, size, color):
    f = TTFont(font_path); gs = f.getGlyphSet(); cmap = f.getBestCmap(); upm = f['head'].unitsPerEm
    k = size / upm; asc = f['hhea'].ascent * k; desc = -f['hhea'].descent * k
    pen = SVGPathPen(gs, ntos=lambda v: ('%.1f' % v).rstrip('0').rstrip('.')); x = 0.0
    for ch in text:
        g = cmap[ord(ch)]
        gs[g].draw(TransformPen(pen, (k, 0, 0, -k, x, asc)))
        x += gs[g].width * k
    w, h = round(x + 1), round(asc + desc + 1)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
            f'<path fill="{color}" d="{pen.getCommands()}"/></svg>')
ADDR = 'hello' + chr(64) + 'duoleads.com'
(GEN / 'contact.svg').write_text(text_svg(ADDR, REPO / 'assets/fonts/Fredoka-SemiBold.ttf', 15, '#FFFFFF'))
(GEN / 'contact-pink.svg').write_text(text_svg(ADDR, REPO / 'assets/fonts/Fredoka-SemiBold.ttf', 17, '#EC008C'))
print('contact.svg', (GEN / 'contact.svg').stat().st_size)
