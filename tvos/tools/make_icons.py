#!/usr/bin/env python3
"""Generate the tvOS app icon (layered, for the parallax effect) and Top Shelf images.

Abstract artwork only — a grid of nature-coloured tiles behind one framed "photo" tile —
so no personal photos end up in the repo. Writes into PhotomosaicTV/Assets.xcassets.

    python3 tvos/tools/make_icons.py
"""
import json
import os
import random

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "PhotomosaicTV", "Assets.xcassets")
BRAND = os.path.join(ASSETS, "App Icon & Top Shelf Image.brandassets")
INFO = {"author": "xcode", "version": 1}

PALETTE = [  # forest, meadow, sky, water, bark, autumn, sunset
    (34, 85, 51), (60, 120, 60), (110, 160, 80), (150, 190, 110), (90, 140, 190), (140, 180, 220),
    (60, 100, 140), (120, 90, 60), (90, 70, 50), (200, 150, 70), (210, 110, 60), (230, 190, 120),
]


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def tile_grid(w, h, cols, seed, darken=1.0):
    """Mosaic background: screen-shaped tiles with subtle gradients."""
    rnd = random.Random(seed)
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    tw = w / cols
    th = tw * 9 / 16
    rows = int(h / th) + 1
    for r in range(rows):
        for c in range(cols):
            base = rnd.choice(PALETTE)
            jitter = [max(0, min(255, int((v + rnd.randint(-25, 25)) * darken))) for v in base]
            x0, y0 = round(c * tw), round(r * th)
            x1, y1 = round((c + 1) * tw), round((r + 1) * th)
            top = tuple(min(255, v + 25) for v in jitter)
            for y in range(y0, y1):  # vertical gradient per tile
                t = (y - y0) / max(1, y1 - y0)
                d.line([(x0, y), (x1, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, jitter)))
    return img


def landscape(w, h):
    """The 'photo' tile: sky, sun, hills, lake."""
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=(int(90 + 140 * t), int(140 + 80 * t), int(210 - 20 * t)))
    r = h * 0.13
    d.ellipse([w * 0.68 - r, h * 0.28 - r, w * 0.68 + r, h * 0.28 + r], fill=(255, 236, 180))
    d.polygon([(0, h * 0.62), (w * 0.22, h * 0.38), (w * 0.45, h * 0.6), (w * 0.62, h * 0.45),
               (w, h * 0.66), (w, h), (0, h)], fill=(70, 110, 90))
    d.polygon([(0, h * 0.75), (w * 0.35, h * 0.6), (w * 0.7, h * 0.72), (w, h * 0.68), (w, h), (0, h)],
              fill=(45, 90, 55))
    d.rectangle([0, h * 0.85, w, h], fill=(70, 120, 160))
    return img


def front_layer(w, h):
    """Transparent layer with one framed, shadowed photo tile in the middle."""
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pw = int(w * 0.46)
    ph = int(pw * 9 / 16)
    x, y = (w - pw) // 2, (h - ph) // 2
    border = max(2, w // 120)
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rectangle([x - border, y - border + h // 40, x + pw + border, y + ph + border + h // 40],
                                     fill=(0, 0, 0, 150))
    layer = Image.alpha_composite(layer, shadow.filter(ImageFilter.GaussianBlur(w // 60)))
    ImageDraw.Draw(layer).rectangle([x - border, y - border, x + pw + border, y + ph + border],
                                    fill=(255, 255, 255, 255))
    layer.paste(landscape(pw, ph), (x, y))
    return layer


def imageset(path, files, idiom="tv"):
    images = [{"idiom": idiom, "scale": scale, "filename": name} for scale, name in files]
    write_json(os.path.join(path, "Contents.json"), {"images": images, "info": INFO})


def imagestack(name, size, scales):
    """An imagestack with Front and Back layers at the given scales."""
    stack = os.path.join(BRAND, name + ".imagestack")
    w, h = size
    for layer_name, make in (("Front", front_layer), ("Back", lambda W, H: tile_grid(W, H, 9, 7, 0.75))):
        content = os.path.join(stack, layer_name + ".imagestacklayer", "Content.imageset")
        os.makedirs(content, exist_ok=True)
        files = []
        for scale in scales:
            k = int(scale[0])
            fname = f"{layer_name.lower()}@{scale}.png"
            make(w * k, h * k).save(os.path.join(content, fname))
            files.append((scale, fname))
        imageset(content, files)
        write_json(os.path.join(stack, layer_name + ".imagestacklayer", "Contents.json"), {"info": INFO})
    write_json(os.path.join(stack, "Contents.json"),
               {"info": INFO, "layers": [{"filename": "Front.imagestacklayer"},
                                         {"filename": "Back.imagestacklayer"}]})


def top_shelf(name, size):
    path = os.path.join(BRAND, name + ".imageset")
    os.makedirs(path, exist_ok=True)
    w, h = size
    files = []
    for scale in ("1x", "2x"):
        k = int(scale[0])
        bg = tile_grid(w * k, h * k, 24, 11, 0.8).convert("RGBA")
        fl = front_layer(h * k * 16 // 9, h * k)
        bg.alpha_composite(fl, ((w * k - fl.width) // 2, 0))
        fname = f"{name.lower().replace(' ', '-')}@{scale}.png"
        bg.convert("RGB").save(os.path.join(path, fname))
        files.append((scale, fname))
    imageset(path, files)


def main():
    write_json(os.path.join(ASSETS, "Contents.json"), {"info": INFO})
    imagestack("App Icon", (400, 240), ("1x", "2x"))
    imagestack("App Icon - App Store", (1280, 768), ("1x",))
    top_shelf("Top Shelf Image", (1920, 720))
    top_shelf("Top Shelf Image Wide", (2320, 720))
    write_json(os.path.join(BRAND, "Contents.json"), {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon",
             "size": "1280x768"},
            {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide",
             "size": "2320x720"},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image",
             "size": "1920x720"},
        ],
        "info": INFO,
    })
    print("Wrote", os.path.relpath(ASSETS))


if __name__ == "__main__":
    main()
