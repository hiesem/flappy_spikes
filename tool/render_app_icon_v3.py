#!/usr/bin/env python3
"""App icon v3 ("icon10"; was icon8): renders every app-icon file from one picture.

Source of truth: ``assets/icon/app_icon_src.png`` (a copy of the workspace's
``icon_concepts/v3/icon10.png``, 1254 x 1254, full-bleed). Pass another
picture as the first argument to replace the source first.

  assets/icon/ic_background.png    432 x 432  adaptive layer: the full picture (108 dp)
  assets/icon/ic_foreground.png    432 x 432  empty (transparent)
  assets/icon/ic_monochrome.png    432 x 432  themed-icon silhouette
  assets/icon/splash_icon.png      288 x 288  full picture, 22 % corners
  assets/icon/splash_android12.png 960 x 960  background + foreground
  assets/images/app_icon.png      1024 x 1024 full picture, no alpha (iOS)
  docs/p23/play_icon_512.png       512 x 512  Play listing icon, no alpha

Android adaptive icon (owner, 2026-10-19 after testing 38, option "M"): the
whole picture exactly fills the 72 dp view of the 108 dp canvas (one layer,
no fade), so a rounded-square launcher shows the original uncropped and a
circle only trims its corners (outer spike and wing tips). The monochrome
icon uses the same scale.

Android 12+ splash (unchanged from 38, "shrink to fit"): the picture is scaled to
``PICTURE_DP`` of the 108 dp canvas so the bird (wing tips, feet) and the
three spike tips lie inside the 66 dp safe-zone circle. Its outer
``FEATHER_DP`` fade into the background layer, which extends the picture's
own blue outward (mask-weighted push-pull fill of the background pixels)
and eases into ``SPLASH`` towards the canvas edge, so no square edge shows.

Needs Pillow + numpy + scipy (system Python has no PIL; use a venv):

  python3 -m venv /tmp/v && /tmp/v/bin/pip install pillow numpy scipy
  /tmp/v/bin/python tool/render_app_icon_v3.py [path/to/icon10.png]

Then: ``dart run flutter_launcher_icons`` and
``dart run flutter_native_splash:create`` (and set UIStatusBarHidden back to
true in ios/Runner/Info.plist, PORT-IOS §1).
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "icon", "app_icon_src.png")

PX_PER_DP = 16  # working resolution: 108 dp -> 1728 px
CANVAS_DP = 108
PICTURE_DP = 65.0  # picture edge on the 108 dp canvas (Android 12 splash)
VIEW_DP = 72  # the part of the 108 dp canvas launchers show
FEATHER_DP = 3.5  # fade band at the picture border
# Splash / outer colour: the deep blue of the picture's corners.
SPLASH = (0x2C, 0xA4, 0xF4)  # icon10 corner blue (was #003ADC)
# Android 12 splash: radius (dp) where the fade into SPLASH starts.
A12_FADE_FROM_DP = 32.0

# The three crystal spikes in source pixels (bases on the top edge).
SPIKES = [
    [(62, 0), (412, 0), (276, 230)],
    [(440, 0), (812, 0), (626, 250)],
    [(840, 0), (1192, 0), (978, 230)],
]


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def push_pull(img, w):
    """Fills pixels with weight 0 from their neighbours, smoothly.

    img: HxWx3 float, w: HxW weights in [0, 1]. Classic mask-weighted image
    pyramid: average down until everything is covered, then interpolate up
    and keep the known pixels at every level.
    """
    if min(w.shape) <= 2 or w.min() > 0.999:
        return img
    h, wd = w.shape
    h2, w2 = (h + 1) // 2, (wd + 1) // 2
    pad_i = np.zeros((h2 * 2, w2 * 2, 3))
    pad_w = np.zeros((h2 * 2, w2 * 2))
    pad_i[:h, :wd] = img * w[..., None]
    pad_w[:h, :wd] = w
    si = pad_i.reshape(h2, 2, w2, 2, 3).sum((1, 3))
    sw = pad_w.reshape(h2, 2, w2, 2).sum((1, 3))
    low = si / np.maximum(sw, 1e-9)[..., None]
    low_w = np.minimum(sw, 1.0)
    low = push_pull(low, low_w)
    up = np.asarray(
        Image.fromarray(np.clip(low, 0, 255).astype(np.uint8)).resize(
            (w2 * 2, h2 * 2), Image.BILINEAR
        ),
        dtype=float,
    )[:h, :wd]
    # Higher-precision upsample than uint8 would be nicer; the result is
    # blurred afterwards anyway.
    return img * w[..., None] + up * (1 - w[..., None])


def spike_mask(size):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    k = size / 1254
    for tri in SPIKES:
        d.polygon([(x * k, y * k) for x, y in tri], fill=255)
    return np.asarray(m, dtype=float) / 255


def background_mask(src):
    """1 where the source pixel is plain background blue."""
    a = np.asarray(src, dtype=float)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    bg = (b > 170) & (r < 70) & (b - r > 120)
    bg &= spike_mask(src.size[0]) < 0.5
    bg = ndimage.binary_erosion(bg, iterations=4)
    return bg


def adaptive_layers(src, picture_dp=None):
    """Returns (background RGB, foreground RGBA) at working resolution."""
    n = CANVAS_DP * PX_PER_DP
    p = int(round((picture_dp or PICTURE_DP) * PX_PER_DP))
    o = (n - p) // 2
    pic = src.resize((p, p), Image.LANCZOS)
    bgm = Image.fromarray((background_mask(src) * 255).astype(np.uint8)).resize(
        (p, p), Image.BILINEAR
    )
    img = np.zeros((n, n, 3))
    w = np.zeros((n, n))
    img[o : o + p, o : o + p] = np.asarray(pic, dtype=float)
    w[o : o + p, o : o + p] = (np.asarray(bgm, dtype=float) / 255) ** 4
    fill = push_pull(img, w)
    fill = ndimage.gaussian_filter(fill, sigma=(1.5 * PX_PER_DP, 1.5 * PX_PER_DP, 0))

    # Distance (dp) outside the picture square, euclidean.
    yy, xx = np.mgrid[0:n, 0:n] + 0.5
    dx = np.maximum(np.maximum(o - xx, xx - (o + p)), 0)
    dy = np.maximum(np.maximum(o - yy, yy - (o + p)), 0)
    out = np.hypot(dx, dy) / PX_PER_DP
    # Ease into the splash colour from the picture edge to the canvas edge.
    t = smoothstep(out / ((CANVAS_DP - (picture_dp or PICTURE_DP)) / 2 * 1.2))[..., None]
    back = fill * (1 - t) + np.array(SPLASH, dtype=float) * t

    # Foreground: the picture, its border feathered.
    f = FEATHER_DP * PX_PER_DP
    inside = np.minimum(
        np.minimum(xx - o, o + p - xx), np.minimum(yy - o, o + p - yy)
    )
    alpha = smoothstep(inside / f)
    fore = np.zeros((n, n, 4))
    fore[..., :3] = img
    fore[..., 3] = alpha * 255
    return back, fore


def monochrome(src):
    """White bird + spikes silhouette, eyes cut out (as the 17C mono)."""
    a = np.asarray(src, dtype=float)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    bird = (r - b > 40) & (r > 120)
    bird = ndimage.binary_opening(bird, iterations=2)
    lab, k = ndimage.label(bird)
    sizes = ndimage.sum(bird, lab, range(1, k + 1))
    keep = [i + 1 for i, s in enumerate(sizes) if s > 2000]
    bird = np.isin(lab, keep)
    bird = ndimage.binary_closing(bird, iterations=24)
    bird = ndimage.binary_fill_holes(bird)
    # Eyes: the white sclera + pupils, filled.
    white = (r > 200) & (g > 200) & (b > 200)
    white = ndimage.binary_opening(white, iterations=3)
    lab, k = ndimage.label(white)
    sizes = ndimage.sum(white, lab, range(1, k + 1))
    order = np.argsort(sizes)[::-1][:2] + 1
    # Each eye = the ellipse in its sclera's bounding box (the iris breaks
    # the white ring, so hole filling does not work).
    hulls = Image.new("L", src.size, 0)
    for i in order:
        ys, xs = np.nonzero(lab == i)
        ImageDraw.Draw(hulls).ellipse(
            (xs.min(), ys.min(), xs.max(), ys.max()), fill=255
        )
    eyes = np.asarray(hulls) > 127
    sil = bird.astype(float)
    sil = ndimage.gaussian_filter(sil, 3)
    sil = smoothstep((sil - 0.35) / 0.3)
    sil *= 1 - smoothstep((ndimage.gaussian_filter(eyes.astype(float), 2) - 0.35) / 0.3)
    sil = np.maximum(sil, spike_mask(src.size[0]))
    return sil


def place(layer, n, p, mode):
    """Puts a picture-sized layer onto the 108 dp canvas (n px)."""
    canvas = Image.new(mode, (n, n), 0)
    o = (n - p) // 2
    canvas.paste(layer.resize((p, p), Image.LANCZOS), (o, o))
    return canvas


def rounded(im, frac):
    s = im.size[0]
    m = Image.new("L", (s * 4, s * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, s * 4 - 1, s * 4 - 1), radius=int(s * 4 * frac), fill=255
    )
    out = im.convert("RGBA")
    out.putalpha(m.resize((s, s), Image.LANCZOS))
    return out


def save_rgb(img, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.convert("RGB").resize((size, size), Image.LANCZOS).save(path, optimize=True)


def main():
    if len(sys.argv) > 1:
        shutil.copyfile(sys.argv[1], SRC)
    src = Image.open(SRC).convert("RGB")
    assert src.size[0] == src.size[1], "the picture must be square"
    icon = os.path.join(ROOT, "assets", "icon")

    back, fore = adaptive_layers(src)
    n = back.shape[0]
    back_im = Image.fromarray(np.clip(back, 0, 255).round().astype(np.uint8))
    fore_im = Image.fromarray(np.clip(fore, 0, 255).round().astype(np.uint8), "RGBA")
    # The launcher icon: the whole picture exactly fills the 72 dp the
    # launcher shows (crisp, no fade); outside it (seen only in launcher
    # animations) the background extends its blue.
    n = CANVAS_DP * PX_PER_DP
    p72 = VIEW_DP * PX_PER_DP
    ext, _ = adaptive_layers(src, picture_dp=VIEW_DP)
    layer = Image.fromarray(np.clip(ext, 0, 255).round().astype(np.uint8))
    layer.paste(src.resize((p72, p72), Image.LANCZOS), ((n - p72) // 2,) * 2)
    layer.resize((432, 432), Image.LANCZOS).save(
        os.path.join(icon, "ic_background.png"), optimize=True
    )
    Image.new("RGBA", (432, 432), (0, 0, 0, 0)).save(
        os.path.join(icon, "ic_foreground.png"), optimize=True
    )

    mono = Image.fromarray((monochrome(src) * 255).round().astype(np.uint8))
    mono = place(mono, n, VIEW_DP * PX_PER_DP, "L")
    white = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    white.putalpha(mono)
    white.resize((432, 432), Image.LANCZOS).save(
        os.path.join(icon, "ic_monochrome.png"), optimize=True
    )

    full = back_im.convert("RGBA")
    full.alpha_composite(fore_im)
    # Android 12+ shows the centre 72 dp in a circle on SPLASH: ease the rim
    # into SPLASH so the circle edge does not show.
    yy, xx = np.mgrid[0:n, 0:n] + 0.5
    r = np.hypot(xx - n / 2, yy - n / 2) / PX_PER_DP
    t = smoothstep((r - A12_FADE_FROM_DP) / (36 - A12_FADE_FROM_DP))[..., None]
    a12 = np.asarray(full.convert("RGB"), dtype=float)
    a12 = a12 * (1 - t) + np.array(SPLASH, dtype=float) * t
    save_rgb(
        Image.fromarray(a12.round().astype(np.uint8)),
        os.path.join(icon, "splash_android12.png"),
        960,
    )

    rounded(src.resize((288, 288), Image.LANCZOS), 0.22).save(
        os.path.join(icon, "splash_icon.png"), optimize=True
    )
    save_rgb(src, os.path.join(ROOT, "assets", "images", "app_icon.png"), 1024)
    play = os.path.join(ROOT, "docs", "p23", "play_icon_512.png")
    save_rgb(src, play, 512)
    assert os.path.getsize(play) < 1024 * 1024
    print("icon v3 files rendered; splash #%02X%02X%02X" % SPLASH)


if __name__ == "__main__":
    main()
