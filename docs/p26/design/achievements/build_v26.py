"""Builds design/approvals_v26/achievement_icons.html: the approval page for the 10 new 2.6
achievement icons (PRD-2.6 §7.1 D15, O94).

Same pipeline as build.py: inlines skin_art.js + emblem_art.js + ach_art.js and the 48's icon
core (frame / shadow / drawIcon / ACH, sliced unchanged from achievements.tpl.html, so the ring
and shadow have one master), plus ach_art_v26.js with the new scenes. Fonts: the Opificio TTF
(canvas text, as on the 48's page) and the approvals_v26 Opi / Fred webfonts (page chrome).
"""
import base64, pathlib, re
HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
b64 = lambda p: base64.b64encode(p.read_bytes()).decode()
font = b64(ROOT / 'flappy_spikes/assets/fonts/Opificio_neue-regular.ttf')
skin = (ROOT / 'design/menu_v2/skin_art.js').read_text()
emb = (ROOT / 'design/menu_v2/emblem_art.js').read_text()
ach = (HERE / 'ach_art.js').read_text()
v26 = (HERE / 'ach_art_v26.js').read_text()
old = (HERE / 'achievements.tpl.html').read_text()
a = old.index('// ---- 17C app icon language')
b = old.index('const cards=[],minis=[];')
core = old[a:b]
guide = (ROOT / 'design/approvals_v26/flight_guide.html').read_text()
webfonts = '\n'.join(re.findall(r"@font-face\{font-family:(?:Opi|Fred);[^}]*\}", guide))
assert webfonts.count('@font-face') == 2, 'Opi/Fred webfonts not found'
tpl = (HERE / 'achievement_icons_v26.tpl.html').read_text()
out = (tpl.replace('/*FONT*/', font).replace('/*WEBFONTS*/', webfonts)
          .replace('/*SKIN_ART*/', skin).replace('/*EMBLEM_ART*/', emb)
          .replace('/*ACH_ART*/', ach).replace('/*ACH_ART_V26*/', v26).replace('/*CORE*/', core))
dst = ROOT / 'design/approvals_v26/achievement_icons.html'
dst.write_text(out)
print('wrote', dst, len(out) // 1024, 'KB')
