"""Export O96's approved recommended icons without rebuilding the approval page.

Run: python3 design/achievements/build_v26.py
Requires Pillow and Node with Playwright (in tools/node_modules in this checkout
or an ancestor workspace, or supplied with --playwright-module).
The approval page owns all artwork and variant selection via #export=<size>.
"""

import argparse
import base64
import io
import json
from pathlib import Path
import shutil
import subprocess

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
KEYS = {
    "bullseye", "sky_high", "bird_of_prey", "birdwatcher", "second_wind",
    "albatross", "three_little_birds", "iron_beak", "flawless", "top_bird",
}
EXPORT_JS = r"""
const { chromium } = require(process.argv[1]);
(async () => {
  const browser = await chromium.launch({
    headless: true, executablePath: process.argv[3] || undefined,
  });
  try {
    const page = await browser.newPage({deviceScaleFactor: 1});
    const errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    const exports = [];
    for (const size of [160, 512, 1024]) {
      // A query change forces a document reload; a hash change alone keeps
      // window.EXPORT from the previous size and does not rerun the page.
      await page.goto(process.argv[2] + '?size=' + size + '#export=' + size);
      await page.waitForFunction(() => Array.isArray(window.EXPORT));
      const icons = await page.evaluate(() => window.EXPORT);
      const sceneErrors = icons.flatMap(icon => icon.errors);
      if (errors.length || sceneErrors.length) {
        throw new Error([...errors, ...sceneErrors].join('\n'));
      }
      exports.push({size, icons});
    }
    process.stdout.write(JSON.stringify(exports));
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--playwright-module", type=Path)
    parser.add_argument("--chromium", default=shutil.which("chromium"),
                        help="Chromium executable (defaults to system Chromium)")
    args = parser.parse_args()
    module = args.playwright_module or next(
        (p / "tools/node_modules/playwright" for p in (ROOT, *ROOT.parents)
         if (p / "tools/node_modules/playwright/package.json").is_file()), None
    )
    if module is None:
        parser.error("Playwright not found; supply --playwright-module")
    page = ROOT / "docs/p26/design/approvals_v26/achievement_icons.html"
    result = subprocess.run(
        ["node", "-e", EXPORT_JS, str(module.resolve()), page.as_uri(),
         args.chromium or ""],
        check=True, stdout=subprocess.PIPE, text=True,
    )
    exports = json.loads(result.stdout)
    destinations = {
        160: ROOT / "assets/images/achievements",
        512: ROOT / "store/achievements/play",
        1024: ROOT / "store/achievements/ios",
    }
    # Validate the complete render before writing any assets.
    pending = []
    for batch in exports:
        size, icons = batch["size"], batch["icons"]
        if len(icons) != len(KEYS) or {icon["id"] for icon in icons} != KEYS:
            raise ValueError("Approval page does not contain the ten PRD J9 keys")
        for icon in icons:
            prefix, data = icon["png"].split(",", 1)
            if prefix != "data:image/png;base64" or icon["errors"]:
                raise ValueError(f"Invalid render for {icon['id']}")
            png = base64.b64decode(data, validate=True)
            image = Image.open(io.BytesIO(png))
            image.load()
            if image.size != (size, size):
                raise ValueError(f"Wrong size for {icon['id']}: {image.size}")
            if image.convert("RGBA").getchannel("A").getextrema() != (255, 255):
                raise ValueError(f"Expected opaque artwork for {icon['id']}")
            if size == 1024:
                output = io.BytesIO()
                image.convert("RGB").save(output, format="PNG", optimize=True)
                png = output.getvalue()
            pending.append((destinations[size] / f"ach_{icon['id']}.png", png))
    if len(pending) != 30:
        raise ValueError("Expected 30 exported icons")
    for path, png in pending:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(png)
    print("Exported 10 approved icons: 160 in-game, 512 Play, 1024 iOS RGB (30 PNGs).")


if __name__ == "__main__":
    main()
