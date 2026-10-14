"""Export the 48 approved achievement icons (PRD-2.3.1 §12.6).

Run from the app root (needs Pillow + Playwright's Chromium):

    uv run --with pillow --with playwright==1.58.0 python \
        tool/export_achievement_icons.py [--design ../design/achievements] \
        [--approved ../design/_backup_2.3.1/achievements/achievements.html]

It opens the design page ``achievements.html#export=<size>`` headless (the
page renders every icon with its own art at ``size``; ``drawIcon`` takes a
scale, no art changes) and writes:

* ``store/achievements/play/ach_<key>.png``  512 x 512 (Play Console)
* ``store/achievements/ios/ach_<key>.png``  1024 x 1024, RGB (no alpha),
  72 dpi (App Store Connect)
* ``assets/images/achievements/ach_<key>.png``  160 x 160 (the in-game
  toast; quantised to PNG8 when a file is over 25 KB)

Every export is checked pixel-wise against the approved page (the backup
copy's own ``drawIcon`` at 512): the 512 export must match it, the 160 /
1024 ones must match it after resampling, and no icon may be blank. A scene
that throws is a build failure.
"""

from __future__ import annotations

import argparse
import base64
import io
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

SIZES = {"play": 512, "ios": 1024, "toast": 160}
TOAST_MAX = 25 * 1024


def png_of(data_url: str) -> Image.Image:
    return Image.open(io.BytesIO(base64.b64decode(data_url.split(",", 1)[1])))


def render(page, html: Path, size: int) -> list[dict]:
    page.goto("about:blank")  # a hash-only change would not reload the page
    page.goto(f"{html.as_uri()}#export={size}")
    page.wait_for_function("window.EXPORT !== undefined", timeout=120_000)
    errors = page.evaluate("window.EXPORT_ERRORS")
    if errors:
        sys.exit(f"scene errors at {size}: {errors}")
    return page.evaluate("window.EXPORT")


def approved(page, html: Path) -> dict[str, Image.Image]:
    """The approved page's own drawing of every icon at 512."""
    page.goto(html.as_uri())
    page.evaluate("document.fonts.ready")
    page.wait_for_timeout(500)
    out = page.evaluate(
        """() => { const cv = document.createElement('canvas');
        cv.width = cv.height = 512; const r = [];
        for (const it of ACH.flatMap(s => s.items)) { drawIcon(cv, it);
          r.push({id: it.id, png: cv.toDataURL('image/png')}); }
        return r; }"""
    )
    return {o["id"]: png_of(o["png"]).convert("RGBA") for o in out}


def diff(a: Image.Image, b: Image.Image) -> tuple[float, int]:
    """Mean and max per-channel difference (RGB)."""
    d = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
    st = ImageStat.Stat(d)
    return sum(st.mean) / 3, max(hi for _, hi in d.getextrema())


def main() -> None:
    here = Path(__file__).resolve().parent
    app = here.parent
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--design", type=Path,
                    default=app.parent / "design/achievements")
    ap.add_argument("--approved", type=Path,
                    default=app.parent / "design/_backup_2.3.1/achievements/achievements.html")
    ap.add_argument("--app", type=Path, default=app)
    a = ap.parse_args()
    if not (a.design / "achievements.html").exists():
        # The worktree layout: the design folder sits next to the main checkout.
        sys.exit(f"design page not found in {a.design}; pass --design")
    page_html = (a.design / "achievements.html").resolve()
    out_play = a.app / "store/achievements/play"
    out_ios = a.app / "store/achievements/ios"
    out_toast = a.app / "assets/images/achievements"
    for d in (out_play, out_ios, out_toast):
        d.mkdir(parents=True, exist_ok=True)

    from playwright.sync_api import sync_playwright

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page(viewport={"width": 1400, "height": 1000})
        msgs: list[str] = []
        page.on("console", lambda m: msgs.append(m.text) if m.type == "error" else None)
        ref = approved(page, a.approved.resolve())
        renders = {k: render(page, page_html, s) for k, s in SIZES.items()}
        browser.close()
    if msgs:
        sys.exit(f"console errors: {msgs[:5]}")

    ids = [o["id"] for o in renders["play"]]
    if len(ids) != 48 or len(set(ids)) != 48 or set(ids) != set(ref):
        sys.exit(f"expected the 48 approved ids, got {len(ids)}")
    report = []
    for kind, size in SIZES.items():
        for o in renders[kind]:
            key = o["id"]
            img = png_of(o["png"]).convert("RGBA")
            if img.size != (size, size):
                sys.exit(f"{key} {kind}: size {img.size}")
            # Not blank: a real scene has contrast.
            if max(ImageStat.Stat(img.convert("L")).stddev) < 10:
                sys.exit(f"{key} {kind}: blank")
            r = ref[key]
            if size == 512:
                mean, hi = diff(img, r)
                if hi > 0:
                    sys.exit(f"{key} 512: differs from the approved page (max {hi})")
            else:
                # Compared at the smaller of the two sizes.
                if size < 512:
                    mean, hi = diff(img, r.resize(img.size, Image.LANCZOS))
                else:
                    mean, hi = diff(img.resize((512, 512), Image.LANCZOS), r)
                if mean > 4.0:
                    sys.exit(f"{key} {size}: mean diff {mean:.2f} vs approved")
            report.append((key, kind, round(mean, 2), hi))
            name = f"ach_{key}.png"
            if kind == "play":
                img.save(out_play / name, optimize=True)
            elif kind == "ios":
                flat = Image.new("RGB", img.size, (0, 0, 0))
                flat.paste(img, mask=img.getchannel("A"))
                flat.save(out_ios / name, optimize=True, dpi=(72, 72))
            else:
                path = out_toast / name
                img.save(path, optimize=True)
                if path.stat().st_size > TOAST_MAX:
                    img.quantize(256, method=Image.FASTOCTREE).save(path, optimize=True)
    worst = max(report, key=lambda r: r[2])
    print(f"exported {len(report)} files (48 x {len(SIZES)}); worst mean diff "
          f"{worst[2]} ({worst[0]} {worst[1]})")


if __name__ == "__main__":
    main()
