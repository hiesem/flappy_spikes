"""Export only the approved STATIC emblem bases (PRD J6, J8 round 3).

uv run --with pillow --with pyoxipng --with playwright==1.58.0 python tool/export_emblems.py

J7 paints ALL animation in code. Remove each outermost SMIL target subtree,
including the sweep polygon, rays, glow, twinkles, and flickering motifs; never
freeze these into the base. The bird is omitted for the equipped look overlay.
No shapes are redrawn. The 320-unit canvas preserves the source ornaments and
places the plate at (160,160); J7 must draw it into [-160,-160,160,160].

Optional review-only contact sheets (not committed or bundled):
  ... python tool/export_emblems.py --contact-dir /tmp/p26-J8-review
"""
from __future__ import annotations

import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
from pathlib import Path
import shutil
import zipfile

import oxipng
from PIL import Image, ImageChops, ImageDraw
from playwright.sync_api import sync_playwright

APP = Path(__file__).resolve().parent.parent
SOURCE = APP / 'docs/p26/design/levels_v26/emblems.html'
OUTPUT = APP / 'assets/emblems'
ART_SIZE = 320

EXTRACT = r"""() => {
 const fonts = [...document.styleSheets].flatMap(s => [...s.cssRules])
   .filter(r => r.type === CSSRule.FONT_FACE_RULE).map(r => r.cssText).join('\n');
 return Array.from({length:32}, (_,i) => {
  const n=i+1, holder=document.createElement('div');
  holder.innerHTML=emblemSVG(n,320,{bird:false});
  const svg=holder.firstElementChild;
  svg.setAttribute('xmlns','http://www.w3.org/2000/svg');
  svg.setAttribute('viewBox','-160 -160 320 320');
  const style=document.createElementNS(svg.namespaceURI,'style');
  style.textContent=fonts;svg.prepend(style);
  const targets=[...new Set([...svg.querySelectorAll('animate,animateTransform')].map(a=>a.parentElement))];
  const roots=targets.filter(e=>!targets.some(p=>p!==e&&p.contains(e)));
  if(!roots.length)throw new Error(`emblem ${n}: no animation targets found`);
  // Mark the entire animated paint target before removing it. Checking only for
  // SMIL tags would miss the original bug: a frozen target left in the image.
  roots.forEach(e=>e.setAttribute('data-export-animated','true'));
  roots.forEach(e=>e.remove());
  if(svg.querySelector('[data-export-animated],animate,animateTransform'))
    throw new Error(`emblem ${n}: animated paint subtree survived`);
  if(roots.some(e=>svg.contains(e)))
    throw new Error(`emblem ${n}: animated target was not removed`);
  return {id:`emblem_${String(n).padStart(2,'0')}`,name:LV[i].name,
    hiddenAnimatedGroups:roots.length,svg:svg.outerHTML};
 });
}"""
RASTER = r"""async ({svg,size}) => {
 const im=new Image();
 im.src='data:image/svg+xml;base64,'+btoa(unescape(encodeURIComponent(svg)));
 await im.decode();
 const canvas=document.createElement('canvas');canvas.width=canvas.height=size;
 canvas.getContext('2d').drawImage(im,0,0,size,size);
 return canvas.toDataURL('image/png').split(',')[1];
}"""


def path_for(key: str, scale: int) -> Path:
    folder = OUTPUT if scale == 1 else OUTPUT / f'{scale}.0x'
    return folder / f'{key}.png'


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    alpha = img.getchannel('A')
    assert alpha.getextrema()[0] == 0 and alpha.getbbox(), path
    x0, y0, x1, y1 = alpha.getbbox()
    assert x0 > 0 and y0 > 0 and x1 < img.width and y1 < img.height, path
    if img.getcolors(256) is not None:
        palette = img.quantize(colors=256, method=Image.Quantize.FASTOCTREE)
        if all(hi == 0 for _, hi in ImageChops.difference(img, palette.convert('RGBA')).getextrema()):
            palette.save(path, optimize=True)
            return
    img.save(path, optimize=True)


def optimize_png(path: Path) -> None:
    before = Image.open(path).convert('RGBA')
    oxipng.optimize(str(path), level=2)
    after = Image.open(path).convert('RGBA')
    assert before.size == after.size
    assert all(hi == 0 for _, hi in ImageChops.difference(before, after).getextrema()), path


def contacts(emblems: list[dict], folder: Path) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    for scale in [.29, .32]:
        side = round(ART_SIZE * scale)
        sheet = Image.new('RGB', (8 * 180, 4 * 148), '#eeeeee')
        draw = ImageDraw.Draw(sheet)
        for i, emblem in enumerate(emblems):
            with Image.open(path_for(emblem['id'], 1)) as full:
                small = full.convert('RGBA').resize((side, side), Image.Resampling.LANCZOS)
            x, y = (i % 8) * 180, (i // 8) * 148
            sheet.paste(small, (x + (180-side)//2, y), small)
            draw.text((x+3, y+107), f"{i+1:02} {emblem['name']}", fill='#14204a')
        sheet.save(folder / f'emblems_contact_{str(scale).replace(".", "_")}.png', optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--contact-dir', type=Path)
    args = parser.parse_args()
    # This also deletes obsolete slices. Only exporter-owned output is replaced.
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir(parents=True)
    manifest = dict(source=str(SOURCE.relative_to(APP)),
                    sourceSha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                    artSize=ART_SIZE, plateCentre=[160,160],
                    drawBounds=[-160,-160,160,160], scales=[1,2,3],
                    birdIncluded=False, pose='static-only; all animated target subtrees removed',
                    emblems=[])
    errors = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page()
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.route('http://**/*', lambda route: route.abort())
        page.route('https://**/*', lambda route: route.abort())
        page.goto(SOURCE.as_uri())
        page.evaluate('document.fonts.ready')
        emblems = page.evaluate(EXTRACT)
        assert len(emblems) == 32
        for emblem in emblems:
            svg = emblem.pop('svg')
            for scale in manifest['scales']:
                data = page.evaluate(RASTER, {'svg':svg,'size':ART_SIZE*scale})
                img = Image.open(io.BytesIO(base64.b64decode(data))).convert('RGBA')
                assert img.size == (ART_SIZE*scale,)*2
                # Independent source-colour probe, not sampled from an exported
                # reference: HATCHLING's blank plate is #F6EBD2 (source J6 art).
                # The former neutral sweep crosses this patch and brightens it.
                if emblem['id'] == 'emblem_01':
                    for y in range(158*scale,162*scale):
                        for x in range(158*scale,162*scale):
                            assert img.getpixel((x,y)) == (246,235,210,255), (scale,x,y)
                save(img, path_for(emblem['id'],scale))
            manifest['emblems'].append(emblem)
            print(f"{emblem['id']}: removed {emblem['hiddenAnimatedGroups']} animated groups", flush=True)
        browser.close()
    assert not errors, errors
    (OUTPUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    files = list(OUTPUT.rglob('*.png'))
    assert len(files) == 96
    before = sum(p.stat().st_size for p in files)
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(optimize_png,files))
    packed = io.BytesIO()
    with zipfile.ZipFile(packed,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for p in files:
            archive.write(p,p.relative_to(OUTPUT))
    report = dict(pngCount=len(files),preOptimizationBytes=before,
                  rawBytes=sum(p.stat().st_size for p in files),zipBytes=len(packed.getvalue()),
                  lossless=True,pose=manifest['pose'],
                  removedAnimatedGroups=sum(e['hiddenAnimatedGroups'] for e in emblems),
                  sweepProbe='HATCHLING central 4x4 art-unit patch equals source plate #F6EBD2 at all densities',
                  note='Only static bases are bundled. J7 owns every animated effect. ZIP is incremental PNG payload, not signed AAB size.')
    (APP/'tool/emblems_export_report.json').write_text(json.dumps(report,indent=2)+'\n')
    if args.contact_dir:
        contacts(emblems,args.contact_dir)
    print(json.dumps(report),flush=True)


if __name__ == '__main__':
    main()
