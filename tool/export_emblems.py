"""Export the approved J6 SVG art without redrawing it (WP-J8).

Run from any directory:
  uv run --with pillow --with playwright==1.58.0 python tool/export_emblems.py

The 320-art-unit canvas has its plate at (160, 160). The approved ALBATROSS
wings exceed J7's proposed 280-unit bounds, so integration must use 320.
The source's 260-unit viewBox is expanded, never scaled or cropped to ink.
Birds are omitted: the game paints the equipped look at the plate centre.
Every outermost SMIL target is removed from the base and exported separately
in source stacking order. Each PNG preserves its ancestor transforms;
manifest.json records animation attributes and insertion indices. Layers
are neutral, fully visible poses (scale 1, rotation/translation 0, opacity 1);
their SMIL attributes describe the runtime motion, including alternate frames.
All files use the same canvas so no layer needs an alignment correction.

J8's authorized destination differs from the in-flight J7 assetFor contract
(assets/emblems/emblem_01.png with density folders). Integration must reconcile
that contract; this exporter writes only assets/levels/emblems/ as briefed.
"""

from __future__ import annotations

import base64
import hashlib
import io
import json
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright


APP = Path(__file__).resolve().parent.parent
SOURCE = APP / "docs/p26/design/levels_v26/emblems.html"
OUTPUT = APP / "assets/levels/emblems"
ART_SIZE = 320

# Work on the approved function's DOM output, including its embedded fonts.
# No design-page files are modified, and no network resources are used.
EXTRACT = r"""() => {
  const fonts = [...document.styleSheets].flatMap(s => [...s.cssRules])
    .filter(r => r.type === CSSRule.FONT_FACE_RULE).map(r => r.cssText).join('\n');
  const result = [];
  for (let n = 1; n <= 32; n++) {
    const holder = document.createElement('div');
    holder.innerHTML = emblemSVG(n, 320, {bird: false});
    const svg = holder.firstElementChild;
    svg.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
    svg.setAttribute('viewBox', '-160 -160 320 320');
    const style = document.createElementNS(svg.namespaceURI, 'style');
    style.textContent = fonts;
    svg.prepend(style);
    const targets = [...new Set([...svg.querySelectorAll('animate,animateTransform')]
      .map(a => a.parentElement))];
    const roots = targets.filter(e => !targets.some(p => p !== e && p.contains(e)));
    const layers = roots.map((target, i) => {
      const animations = [...target.querySelectorAll('animate,animateTransform')].map(a => ({
        tag: a.tagName, ...Object.fromEntries([...a.attributes].map(x => [x.name, x.value]))
      }));
      const layer = svg.cloneNode(false);
      layer.append(style.cloneNode(true), svg.querySelector('defs').cloneNode(true));
      let content = target.cloneNode(true);
      // Preserve static ancestor transforms and clipping, without their siblings.
      for (let p = target.parentElement; p !== svg; p = p.parentElement) {
        const wrap = p.cloneNode(false); wrap.append(content); content = wrap;
      }
      layer.append(content);
      for (const a of layer.querySelectorAll('animate,animateTransform')) {
        const p = a.parentElement;
        if (a.tagName === 'animateTransform') {
          const type = a.getAttribute('type');
          p.setAttribute('transform', type === 'scale' ? 'scale(1)' :
            type === 'rotate' ? 'rotate(0)' : 'translate(0 0)');
        } else if (a.getAttribute('attributeName') === 'opacity') {
          p.setAttribute('opacity', '1');
        }
        a.remove();
      }
      const ancestors = [];
      for (let p = target; p !== svg; p = p.parentElement) {
        ancestors.unshift([...p.parentElement.children].indexOf(p));
      }
      return {id: `emblem_${String(n).padStart(2,'0')}_layer_${String(i+1).padStart(2,'0')}`,
        insertionPath: ancestors, animations, svg: layer.outerHTML};
    });
    for (const root of roots) root.remove();
    result.push({id: `emblem_${String(n).padStart(2,'0')}`, name: LV[n-1].name,
      svg: svg.outerHTML, layers});
  }
  return result;
}"""

RASTER = r"""async ({svg, size}) => {
  const im = new Image();
  im.src = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(svg)));
  await im.decode();
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = size;
  canvas.getContext('2d').drawImage(im, 0, 0, size, size);
  return canvas.toDataURL('image/png').split(',')[1];
}"""


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "source": str(SOURCE.relative_to(APP)),
        "sourceSha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "artSize": ART_SIZE,
        "plateCentre": [160, 160],
        "scales": [1, 2, 3],
        "birdIncluded": False,
        "emblems": [],
    }
    expected = {"manifest.json"}
    errors: list[str] = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page()
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.route("http://**/*", lambda route: route.abort())
        page.route("https://**/*", lambda route: route.abort())
        page.goto(SOURCE.as_uri())
        page.evaluate("document.fonts.ready")
        emblems = page.evaluate(EXTRACT)
        assert len(emblems) == 32
        for emblem in emblems:
            for part in [emblem, *emblem["layers"]]:
                svg = part.pop("svg")
                for scale in manifest["scales"]:
                    name = f'{part["id"]}@{scale}x.png'
                    data = page.evaluate(RASTER, {"svg": svg, "size": ART_SIZE * scale})
                    img = Image.open(io.BytesIO(base64.b64decode(data))).convert("RGBA")
                    assert img.size == (ART_SIZE * scale,) * 2
                    alpha = img.getchannel("A")
                    lo, hi = alpha.getextrema()
                    assert lo == 0 and hi > 0, name
                    assert alpha.getbbox() is not None, name
                    # The padded canvas must keep every ornament off its edge.
                    x0, y0, x1, y1 = alpha.getbbox()
                    assert x0 > 0 and y0 > 0 and x1 < img.width and y1 < img.height, name
                    img.save(OUTPUT / name, optimize=True)
                    expected.add(name)
            manifest["emblems"].append(emblem)
            print(f'{emblem["id"]}: base + {len(emblem["layers"])} animation layers', flush=True)
        browser.close()
    assert not errors, errors
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    stale = {p.name for p in OUTPUT.iterdir()} - expected
    assert not stale, f"Unexpected output files (remove obsolete exports explicitly): {stale}"
    print(f"Exported {len(expected) - 1} PNGs; 32 bases at 1x/2x/3x, separate animation layers.")


if __name__ == "__main__":
    main()
