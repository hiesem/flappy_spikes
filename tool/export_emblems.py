"""Export approved SVGs, ordered animation slices and D2 contact sheets (J8).

uv run --with pillow --with pyoxipng --with playwright==1.58.0 python tool/export_emblems.py

No drawings are recreated. The source function supplies all shapes and fonts.
The 320-unit canvas preserves ALBATROSS's wings; its plate is at (160,160).
Full images are independent, unsliced SVG renders. Slice SVGs prune only atomic
paint nodes, retaining all ancestor transforms, clips, masks and definitions.
Contiguous static nodes form one slice; each SMIL target forms its own slice.
Numbered slices composite bottom-to-top, including static slices BETWEEN effects.

The comparison pose is deterministic and visible: animated transforms are neutral
(rotation/translation 0, scale 1), opacity is its animation's maximum. Both flame
alternatives are retained, with their original timing in the manifest. This is a
per-target peak pose, not a single shared animation timestamp. The untouched SVG
structure in that pose is the full-render reference. Only premultiplied RGBA
rounding at antialiased edges may differ when slices are composited (<= 4/255 across the ordered stack).

All density sets remain lossless. The export report records raw/ZIP payload size,
plus contact sheets at exact 0.29x and 0.32x art scales for the D2 human art check.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

import oxipng
import base64
import hashlib
import io
import json
import shutil
import zipfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw
from playwright.sync_api import sync_playwright

APP = Path(__file__).resolve().parent.parent
SOURCE = APP / 'docs/p26/design/levels_v26/emblems.html'
OUTPUT = APP / 'assets/emblems'
ART_SIZE = 320
TOLERANCE = 4

EXTRACT = r"""() => {
 const fonts = [...document.styleSheets].flatMap(s => [...s.cssRules])
   .filter(r => r.type === CSSRule.FONT_FACE_RULE).map(r => r.cssText).join('\n');
 const result = [];
 for(let n=1;n<=32;n++) {
  const holder=document.createElement('div');
  holder.innerHTML=emblemSVG(n,320,{bird:false});
  const svg=holder.firstElementChild;
  svg.setAttribute('xmlns','http://www.w3.org/2000/svg');
  svg.setAttribute('viewBox','-160 -160 320 320');
  const style=document.createElementNS(svg.namespaceURI,'style');
  style.textContent=fonts;svg.prepend(style);
  const targets=[...new Set([...svg.querySelectorAll('animate,animateTransform')].map(a=>a.parentElement))];
  const roots=targets.filter(e=>!targets.some(p=>p!==e&&p.contains(e)));
  const atoms=[];
  function walk(e) {
   if(['defs','style','mask','clipPath','linearGradient','radialGradient'].includes(e.tagName))return;
   if(roots.includes(e)||!['svg','g'].includes(e.tagName)) {atoms.push(e);return;}
   [...e.children].forEach(walk);
  }
  walk(svg);
  const parts=[];
  atoms.forEach((node,index)=>{
   node.setAttribute('data-export-atom',String(index));
   const animated=roots.includes(node);
   if(animated||!parts.length||parts.at(-1).kind==='animated')
     parts.push({kind:animated?'animated':'static',atoms:[],animations:[]});
   const part=parts.at(-1);part.atoms.push(index);
   if(animated)part.animations=[...node.querySelectorAll('animate,animateTransform')].map(a=>({
    tag:a.tagName,...Object.fromEntries([...a.attributes].map(x=>[x.name,x.value]))}));
  });
  // Freeze exactly the same full SVG and slices into the documented peak pose.
  for(const a of [...svg.querySelectorAll('animate,animateTransform')]) {
   const p=a.parentElement;
   if(a.tagName==='animateTransform') {
    const type=a.getAttribute('type');
    p.setAttribute('transform',type==='scale'?'scale(1)':type==='rotate'?'rotate(0)':'translate(0 0)');
   } else if(a.getAttribute('attributeName')==='opacity') {
    p.setAttribute('opacity',String(Math.max(...a.getAttribute('values').split(';').map(Number))));
   }
   a.remove();
  }
  const id=`emblem_${String(n).padStart(2,'0')}`;
  const slices=parts.map((part,i)=>{
   const copy=svg.cloneNode(true);
   for(const e of copy.querySelectorAll('[data-export-atom]'))
     if(!part.atoms.includes(Number(e.getAttribute('data-export-atom'))))e.remove();
   return {id:`${id}_s${String(i+1).padStart(2,'0')}`,kind:part.kind,
     animations:part.animations,svg:copy.outerHTML};
  });
  result.push({id,name:LV[n-1].name,svg:svg.outerHTML,slices});
 }
 return result;
}"""
RASTER = r"""async ({svg,size}) => {
 const im=new Image();
 im.src='data:image/svg+xml;base64,'+btoa(unescape(encodeURIComponent(svg)));
 await im.decode();
 const canvas=document.createElement('canvas');canvas.width=canvas.height=size;
 canvas.getContext('2d').drawImage(im,0,0,size,size);
 return canvas.toDataURL('image/png').split(',')[1];
}"""


def path_for(key: str, scale: int, layer: bool = False) -> Path:
    folder = OUTPUT / 'layers' if layer else OUTPUT
    if scale > 1:
        folder /= f'{scale}.0x'
    return folder / f'{key}.png'


def render(page, svg: str, scale: int) -> Image.Image:
    data = page.evaluate(RASTER, {'svg': svg, 'size': ART_SIZE * scale})
    return Image.open(io.BytesIO(base64.b64decode(data))).convert('RGBA')


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    alpha = img.getchannel('A')
    assert alpha.getextrema()[0] == 0 and alpha.getbbox(), path
    x0, y0, x1, y1 = alpha.getbbox()
    assert x0 > 0 and y0 > 0 and x1 < img.width and y1 < img.height, path
    # Lossless indexed PNG when the entire RGBA palette fits (no quantisation).
    if img.getcolors(256) is not None:
        palette = img.quantize(colors=256, method=Image.Quantize.FASTOCTREE)
        if all(hi == 0 for _, hi in ImageChops.difference(img, palette.convert('RGBA')).getextrema()):
            palette.save(path, optimize=True)
            return
    img.save(path, optimize=True)


def premultiplied(image: Image.Image) -> Image.Image:
    # RGB in fully transparent pixels is undefined; compare coverage-weighted RGB.
    alpha = image.getchannel('A')
    return Image.merge('RGBA', (*[ImageChops.multiply(image.getchannel(b), alpha) for b in 'RGB'], alpha))


def optimize_png(path: Path) -> None:
    before = Image.open(path).convert('RGBA')
    oxipng.optimize(str(path), level=2)
    after = Image.open(path).convert('RGBA')
    assert before.size == after.size
    assert all(hi == 0 for _, hi in ImageChops.difference(before, after).getextrema()), path


def write_report(emblems: list[dict]) -> dict:
    files = list(OUTPUT.rglob('*.png'))
    before = sum(p.stat().st_size for p in files)
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(optimize_png, files))
    raw = sum(p.stat().st_size for p in files)
    packed = io.BytesIO()
    with zipfile.ZipFile(packed, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for p in files:
            archive.write(p, p.relative_to(OUTPUT))
    # Art-package payload budget; release verification still measures the actual
    # signed AAB, including native libraries and Dart code, outside J8's scope.
    budget = 16 * 1024 * 1024
    assert len(packed.getvalue()) <= budget
    report = dict(pngCount=len(files), preOptimizationBytes=before,
                  rawBytes=raw, zipBytes=len(packed.getvalue()),
                  compressedBudgetBytes=budget,
                  allAssetsBytes=sum(p.stat().st_size for p in (APP/'assets').rglob('*') if p.is_file()),
                  maxCompositeError=max(max(e['rebuildMaxError']) for e in emblems),
                  contactScales=[.29, .32], lossless=True,
                  legibilityReview='Both contact sheets visually inspected in J8 round 2: silhouettes and main motifs remain distinguishable; fine ribbon numerals are small in the approved source. Bird centres intentionally empty.',
                  note='ZIP is incremental asset payload, not a signed AAB measurement; all 3 density sets retained.')
    (APP / 'tool/emblems_export_report.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


def main() -> None:
    # Only exporter-owned output is replaced. Old J8 paths are removed explicitly.
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    old = APP / 'assets/levels/emblems'
    if old.exists():
        shutil.rmtree(old)
    OUTPUT.mkdir(parents=True)
    manifest = dict(source=str(SOURCE.relative_to(APP)),
                    sourceSha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                    artSize=ART_SIZE, plateCentre=[160, 160], scales=[1, 2, 3],
                    birdIncluded=False, pose='per-target peak; neutral transforms',
                    compositeTolerance=TOLERANCE, emblems=[])
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
            full_svg = emblem.pop('svg')
            slice_svgs = [s.pop('svg') for s in emblem['slices']]
            diffs = []
            for scale in manifest['scales']:
                full = render(page, full_svg, scale)
                save(full, path_for(emblem['id'], scale))
                rebuilt = Image.new('RGBA', full.size)
                for part, svg in zip(emblem['slices'], slice_svgs, strict=True):
                    layer = render(page, svg, scale)
                    save(layer, path_for(part['id'], scale, True))
                    rebuilt = Image.alpha_composite(rebuilt, layer)
                diff = ImageChops.difference(premultiplied(full), premultiplied(rebuilt))
                maximum = max(hi for _, hi in diff.getextrema())
                assert maximum <= TOLERANCE, (emblem['id'], scale, maximum)
                diffs.append(maximum)
            emblem['rebuildMaxError'] = diffs
            manifest['emblems'].append(emblem)
            print(f"{emblem['id']}: {len(emblem['slices'])} slices, max errors {diffs}", flush=True)
        browser.close()
    assert not errors, errors
    (OUTPUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    # Review-only contact sheets stay in tool/, outside the bundled asset folders.
    for scale in [.29, .32]:
        side = round(ART_SIZE * scale)
        sheet = Image.new('RGB', (8 * 180, 4 * 148), '#eeeeee')
        draw = ImageDraw.Draw(sheet)
        for i, emblem in enumerate(emblems):
            with Image.open(path_for(emblem['id'], 1)) as full:
                small = full.convert('RGBA').resize((side, side), Image.Resampling.LANCZOS)
            x, y = (i % 8) * 180, (i // 8) * 148
            sheet.paste(small, (x + (180-side)//2, y), small)
            draw.text((x + 3, y + 107), f"{i+1:02} {emblem['name']}", fill='#14204a')
        sheet.save(APP / f'tool/emblems_contact_{str(scale).replace(".", "_")}.png', optimize=True)
    print(json.dumps(write_report(emblems)), flush=True)


if __name__ == '__main__':
    main()
