#!/usr/bin/env python3
"""PRD-2.3 §9: renders the 17C app icon files from the workspace generator.

Source of truth: ``icon_concepts/gen6.py`` (workspace root, outside git),
variant ``r6c``; ``python3 gen6.py --layers <dir>`` writes the layer SVGs.
This script turns them into the app assets:

  assets/icon/ic_background.png    432 x 432  adaptive background (108 dp)
  assets/icon/ic_foreground.png    432 x 432  bird in the 66 dp safe zone
  assets/icon/ic_monochrome.png    432 x 432  themed-icon silhouette
  assets/icon/splash_icon.png      288 x 288  full design, 22 % corners
  assets/icon/splash_android12.png 960 x 960  background + foreground (§0.8)
  assets/images/app_icon.png      1024 x 1024 full design, no alpha
  docs/p23/play_icon_512.png       512 x 512  Play listing icon, no alpha

Needs ``rsvg-convert`` and Pillow (system Python has no PIL; use a venv):

  python3 -m venv /tmp/v && /tmp/v/bin/pip install pillow
  /tmp/v/bin/python tool/render_app_icon.py [path/to/icon_concepts]

Then: ``dart run flutter_launcher_icons`` and
``dart run flutter_native_splash:create``.
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_GEN = os.path.join(ROOT, "..", "..", "icon_concepts")


def render(svg, out, size):
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), svg, "-o", out],
        check=True,
    )


def opaque(path):
    """Drops the alpha channel (the design is full-bleed, so nothing is lost)."""
    im = Image.open(path).convert("RGBA")
    assert im.getextrema()[3][0] == 255, f"{path} has transparent pixels"
    im.convert("RGB").save(path, optimize=True)


def main():
    gen_dir = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_GEN)
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(
            [sys.executable, os.path.join(gen_dir, "gen6.py"), "--layers", tmp],
            check=True,
        )
        svg = lambda name: os.path.join(tmp, f"17c_{name}.svg")
        icon = os.path.join(ROOT, "assets", "icon")
        os.makedirs(icon, exist_ok=True)
        for layer in ("background", "foreground", "monochrome"):
            render(svg(layer), os.path.join(icon, f"ic_{layer}.png"), 432)
        render(svg("rounded"), os.path.join(icon, "splash_icon.png"), 288)
        render(svg("adaptive"), os.path.join(icon, "splash_android12.png"), 960)
        app = os.path.join(ROOT, "assets", "images", "app_icon.png")
        render(svg("full"), app, 1024)
        opaque(app)
        play_dir = os.path.join(ROOT, "docs", "p23")
        os.makedirs(play_dir, exist_ok=True)
        play = os.path.join(play_dir, "play_icon_512.png")
        render(svg("full"), play, 512)
        opaque(play)
        assert os.path.getsize(play) < 1024 * 1024
    print("17C icon files rendered.")


if __name__ == "__main__":
    main()
