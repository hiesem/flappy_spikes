"""Builds achievements.html: all 48 achievement icons (512x512) as a standalone page.

Inlines the game's own emblem/bird art (design/menu_v2/skin_art.js + emblem_art.js),
the Opificio font and the store icon, so the page opens straight from disk.
"""
import base64, pathlib
HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
b64 = lambda p: base64.b64encode(p.read_bytes()).decode()
font = b64(ROOT / 'flappy_spikes/assets/fonts/Opificio_neue-regular.ttf')
icon = b64(ROOT / 'design/landing_v23/app_icon_17c.png')
skin = (ROOT / 'design/menu_v2/skin_art.js').read_text()
emb = (ROOT / 'design/menu_v2/emblem_art.js').read_text()
ach = (HERE / 'ach_art.js').read_text()
tpl = (HERE / 'achievements.tpl.html').read_text()
out = (tpl.replace('/*FONT*/', font).replace('/*ICON*/', icon)
          .replace('/*SKIN_ART*/', skin).replace('/*EMBLEM_ART*/', emb).replace('/*ACH_ART*/', ach))
(HERE / 'achievements.html').write_text(out)
print('wrote', HERE / 'achievements.html', len(out) // 1024, 'KB')
