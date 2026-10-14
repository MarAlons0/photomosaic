#!/usr/bin/env python3
"""Build a Photomosaic library from a folder of photos.

Turns a folder of exported photos (e.g. from Photos.app: select photos → File →
Export) into a ready-to-play library next to index.html:

    library/
      manifest.js       window.PHOTO_MANIFEST = {...}  (includes tiny inline thumbnails)
      mid/<id>.jpg      ~320 px tiles
      full/<id>.jpg     screen-sized versions, loaded only when a photo fills the screen

manifest.js is a script (not JSON) and the tiny thumbnails are inline data: URIs,
so index.html can open straight from disk (file://) — which is what a screen-saver
wrapper does — and still analyse colours without browser cross-origin errors.

Re-running is incremental: photos already processed are skipped, and photos no
longer in the source folder are dropped from the manifest (and deleted with --prune).

Captions: each photo's date and GPS position are read from its EXIF data. On a Mac,
positions are turned into place names with Apple's map service (tools/geocode.swift),
one lookup per ~1 km area, cached in places.json so later builds only look up new
areas. Use --no-places to skip the lookups (captions then show dates only).

Usage:
    python3 tools/build_library.py ~/Pictures/MosaicExport
    python3 tools/build_library.py ~/Pictures/NatureExport --out library-nature --prune
        (then open index.html?lib=library-nature)

Requires Pillow (pip install Pillow). HEIC needs pillow-heif (pip install pillow-heif),
or export JPEGs from Photos instead.
"""
import argparse
import base64
import subprocess
import hashlib
import io
import json
import os
import random
import sys
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor, as_completed

try:
    from PIL import Image, ImageOps
except ImportError:
    sys.exit("Pillow is required:  pip3 install Pillow")

try:
    from pillow_heif import register_heif_opener
    register_heif_opener()
    HEIF = True
except ImportError:
    HEIF = False

EXTS = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff", ".bmp", ".gif"}
if HEIF:
    EXTS |= {".heic", ".heif"}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_NAME = "index.json"
PLACES_NAME = "places.json"


def photo_id(path):
    st = os.stat(path)
    key = f"{os.path.abspath(path)}|{st.st_size}|{int(st.st_mtime)}"
    return hashlib.sha1(key.encode()).hexdigest()[:16]


def find_photos(src):
    found = []
    for dirpath, dirnames, filenames in os.walk(src):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in filenames:
            if not name.startswith(".") and os.path.splitext(name)[1].lower() in EXTS:
                found.append(os.path.join(dirpath, name))
    return sorted(found)


def process(path, pid, out, full_px, mid_px, tiny_px):
    """Write mid/full JPEGs for one photo and return its manifest entry."""
    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im).convert("RGB")
        full = im.copy()
    full.thumbnail((full_px, full_px), Image.LANCZOS)
    full.save(os.path.join(out, "full", pid + ".jpg"), quality=85, optimize=True)

    mid = full.copy()
    mid.thumbnail((mid_px, mid_px), Image.LANCZOS)
    mid.save(os.path.join(out, "mid", pid + ".jpg"), quality=82, optimize=True)

    tiny = mid.copy()
    tiny.thumbnail((tiny_px, tiny_px), Image.LANCZOS)
    buf = io.BytesIO()
    tiny.save(buf, format="JPEG", quality=72, optimize=True)

    return {
        "id": pid,
        "n": os.path.basename(path),
        "w": full.width,
        "h": full.height,
        "m": f"mid/{pid}.jpg",
        "f": f"full/{pid}.jpg",
        "t": "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode(),
    }


def read_meta(path):
    """(date "YYYY-MM-DD" or None, (lat, lon) or None) from a photo's EXIF data."""
    try:
        with Image.open(path) as im:
            ex = im.getexif()
            taken = ex.get_ifd(0x8769).get(36867) or ex.get(306)
            date = taken[:10].replace(":", "-") if taken and taken[:4].isdigit() else None
            g = ex.get_ifd(0x8825)
            pos = None
            if 2 in g and 4 in g:
                dms = lambda v: float(v[0]) + float(v[1]) / 60 + float(v[2]) / 3600
                lat = dms(g[2]) * (-1 if g.get(1) == "S" else 1)
                lon = dms(g[4]) * (-1 if g.get(3) == "W" else 1)
                if abs(lat) > 0.0001 or abs(lon) > 0.0001:   # 0,0 = no real fix
                    pos = (lat, lon)
            return date, pos
    except Exception:
        return None, None


def tidy(place):
    """Same rule as the helper, for names cached before it: "Singapore, SG, Singapore" -> "Singapore"."""
    parts = [x.strip() for x in place.split(",")]
    return parts[0] if len(parts) > 1 and parts[0] == parts[-1] else place


def area_key(pos):
    """Photos within roughly a kilometre share one place lookup (same rule as the Apple TV app)."""
    return f"{pos[0]:.2f},{pos[1]:.2f}"


def look_up_places(keys, places, places_path):
    """Fill `places` for `keys` using tools/geocode.swift; saves progress as it goes."""
    if sys.platform != "darwin":
        print("Place names need macOS (Apple's map service); captions will show dates only.")
        return
    helper = os.path.join(ROOT, "tools", "geocode.swift")
    print(f"Looking up {len(keys)} places (Apple limits the rate: about {len(keys) * 1.5 / 60:.0f}+ min)…")
    try:
        proc = subprocess.Popen(["swift", "-suppress-warnings", helper], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    except FileNotFoundError:
        print("Swift isn't installed (comes with Xcode); captions will show dates only.")
        return
    for k in keys:
        lat, lon = map(float, k.split(","))
        proc.stdin.write(f"{k}\t{lat}\t{lon}\n")
    proc.stdin.close()
    done = failed = 0
    for line in proc.stdout:
        key, _, name = line.rstrip("\n").partition("\t")
        done += 1
        if name == "!":
            failed += 1                      # not cached: retried on the next build
        else:
            places[key] = name
        if done % 25 == 0 or done == len(keys):
            print(f"  {done}/{len(keys)}", flush=True)
            with open(places_path, "w") as f:
                json.dump(places, f, ensure_ascii=False, indent=0)
    proc.wait()
    if failed:
        print(f"{failed} places couldn't be looked up; run the build again later to retry them.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", help="folder of photos (searched recursively)")
    ap.add_argument("--out", default=os.path.join(ROOT, "library"),
                    help="output folder (default: library/ next to index.html)")
    ap.add_argument("--limit", type=int, default=0,
                    help="max photos; a random sample is taken if there are more (default: no limit — "
                         "the player rotates through big libraries by itself)")
    ap.add_argument("--full", type=int, default=2880, help="long edge of full-size images (default 2880)")
    ap.add_argument("--mid", type=int, default=320, help="long edge of tile images (default 320)")
    ap.add_argument("--tiny", type=int, default=128, help="long edge of inline thumbnails (default 128)")
    ap.add_argument("--prune", action="store_true", help="delete files for photos no longer in the source")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--no-places", action="store_true",
                    help="don't look up place names (captions show dates only)")
    args = ap.parse_args()

    src = os.path.expanduser(args.source)
    if not os.path.isdir(src):
        sys.exit(f"Not a folder: {src}")
    out = os.path.abspath(os.path.expanduser(args.out))
    os.makedirs(os.path.join(out, "mid"), exist_ok=True)
    os.makedirs(os.path.join(out, "full"), exist_ok=True)

    paths = find_photos(src)
    if not paths:
        sys.exit(f"No photos found in {src}" + ("" if HEIF else " (HEIC needs: pip3 install pillow-heif)"))
    if args.limit and len(paths) > args.limit:
        random.seed(0)  # stable sample between runs
        paths = sorted(random.sample(paths, args.limit))
    print(f"{len(paths)} photos in {src}")

    cache_path = os.path.join(out, CACHE_NAME)
    try:
        with open(cache_path) as f:
            cache = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        cache = {}

    wanted = {photo_id(p): p for p in paths}
    entries, todo = {}, []
    for pid, path in wanted.items():
        e = cache.get(pid)
        if e and os.path.exists(os.path.join(out, e["m"])) and os.path.exists(os.path.join(out, e["f"])):
            entries[pid] = e
        else:
            todo.append((pid, path))

    if todo:
        print(f"Processing {len(todo)} new photos ({len(entries)} already done)…")
        failed = 0
        with ProcessPoolExecutor(max_workers=args.jobs) as pool:
            futures = {pool.submit(process, path, pid, out, args.full, args.mid, args.tiny): path
                       for pid, path in todo}
            for i, fut in enumerate(as_completed(futures), 1):
                try:
                    e = fut.result()
                    entries[e["id"]] = e
                except Exception as exc:  # unreadable / unsupported file
                    failed += 1
                    print(f"  skipped {os.path.basename(futures[fut])}: {exc}", file=sys.stderr)
                if i % 25 == 0 or i == len(todo):
                    print(f"  {i}/{len(todo)}", flush=True)
        if failed:
            print(f"{failed} photos could not be read.")
    else:
        print("Nothing new to process.")

    if args.prune:
        keep = {os.path.basename(e[k]) for e in entries.values() for k in ("m", "f")}
        removed = 0
        for sub in ("mid", "full"):
            for name in os.listdir(os.path.join(out, sub)):
                if name not in keep:
                    os.remove(os.path.join(out, sub, name))
                    removed += 1
        if removed:
            print(f"Pruned {removed} stale files.")

    with open(cache_path, "w") as f:
        json.dump(entries, f)

    # Captions: date and place for every photo (read fresh each build; EXIF only, no decoding).
    ids = list(entries)
    with ThreadPoolExecutor(16) as ex:
        meta = dict(zip(ids, ex.map(lambda pid: read_meta(wanted[pid]), ids)))
    places_path = os.path.join(out, PLACES_NAME)
    try:
        with open(places_path) as f:
            places = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        places = {}
    needed = sorted({area_key(pos) for _, pos in meta.values() if pos} - set(places))
    if needed and not args.no_places:
        look_up_places(needed, places, places_path)
    with open(places_path, "w") as f:
        json.dump(places, f, ensure_ascii=False, indent=0)

    photos = []
    for pid, e in entries.items():
        p = {k: v for k, v in e.items() if k != "id"}
        date, pos = meta[pid]
        if date:
            p["d"] = date
        if pos and places.get(area_key(pos)):
            p["p"] = tidy(places[area_key(pos)])
        photos.append(p)
    dated = sum("d" in p for p in photos)
    placed = sum("p" in p for p in photos)
    print(f"Captions: {dated} photos with a date, {placed} with a place name.")
    rel = os.path.relpath(out, ROOT).replace(os.sep, "/")
    manifest = {"version": 1, "base": rel.rstrip("/") + "/", "photos": photos}
    with open(os.path.join(out, "manifest.js"), "w") as f:
        f.write("// Generated by tools/build_library.py — do not edit.\n")
        f.write("window.PHOTO_MANIFEST = ")
        json.dump(manifest, f, separators=(",", ":"), ensure_ascii=False)
        f.write(";\n")

    size = os.path.getsize(os.path.join(out, "manifest.js")) / 1e6
    print(f"Wrote {len(photos)} photos to {out}/manifest.js ({size:.1f} MB)")
    if rel.startswith(".."):
        print("Note: the player only finds libraries inside the Photomosaic folder.")
    elif rel != "library":
        print(f"Open it with: index.html?lib={rel}")


if __name__ == "__main__":
    main()
