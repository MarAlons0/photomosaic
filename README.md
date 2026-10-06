# Photomosaic

A browser-based tribute to the Mac OS X Leopard **Mosaic** screen saver: a photo fills the screen,
dissolves into a mosaic made of your other photos, and the camera dives into one tile until *that*
photo fills the screen — and the cycle repeats forever. It can also run in reverse (each photo
shrinks into a tile of the next) or alternate between the two.

No build step, no server, no dependencies in the browser. Plain HTML + JavaScript.

## Quick start

1. Open `index.html` in Safari or Chrome.
2. Pick **Try it with demo scenes**, or **Choose a folder of photos…** (a few hundred works best).
3. Press **F** for fullscreen.

| Key | Action |
|-----|--------|
| `F` | fullscreen |
| `Space` | pause / resume |
| `N` / `→` | jump to the next photo |
| `S` | settings panel |

Settings (grid size, zoom speed, pause per photo, colour blend, repeat spacing) are remembered in the
browser and can also be set by URL: `index.html?grid=150&duration=30&hold=4&tint=0.15&spacing=3`.

## Using your Photos library

Picking a folder in the browser works, but it has to decode every photo each time. For daily use,
pre-build a library once:

1. **Export from Photos** – make an album (or smart album, e.g. *Favorites*), select all, then
   *File → Export → Export N Photos…* as **JPEG**, size *Medium* or *Large*, into a folder such as
   `~/Pictures/MosaicExport`.
2. **Build the library** (needs Pillow: `pip3 install Pillow`):

   ```bash
   python3 tools/build_library.py ~/Pictures/MosaicExport
   ```

   This writes `library/` next to `index.html` (ignored by git). Re-running is incremental; add
   `--prune` to delete photos you removed from the export folder.
3. Open `index.html` — it starts automatically with the library.

HEIC exports need `pip3 install pillow-heif`; exporting as JPEG avoids that.

### Several libraries

Build each into its own folder and pick one with `?lib=`:

```bash
python3 tools/build_library.py ~/Pictures/NatureExport --out library-nature
```

then open `index.html?lib=library-nature` (combine with other parameters, e.g. `?lib=library-nature&saver=1`).

### Big libraries and shared albums

There's no photo limit: thousands of photos are fine (tested with 6,500). Each mosaic is built from
the next 1,500 photos of a shuffled deck, so every photo gets its turn, and only a 64 px version of
each photo stays in memory — larger versions load as their tiles grow on screen.

**iCloud shared albums** export the same way: in Photos open *Shared Albums → (album)*, select all,
*File → Export*. Photos may need to download them first. Shared-album photos are stored at about
2048 px, so the final full-screen photo is slightly soft on a Retina display.

## As a screen saver (macOS)

[WebViewScreenSaver](https://github.com/liquidx/webviewscreensaver) is an open-source screen saver
that shows a web page:

```bash
brew install --cask webviewscreensaver
```

In *System Settings → Screen Saver → WebViewScreenSaver → Options*, add the URL:

```
file:///Users/<you>/Documents/Claude-code-projects/Photomosaic/index.html?saver=1
```

`?saver=1` skips the intro screen and uses the built library (or the demo scenes if there is none).

> Not yet verified inside WebViewScreenSaver on this Mac — if the page stays blank from `file://`,
> serve the folder instead (`python3 -m http.server 8765` from this directory) and use
> `http://localhost:8765/?saver=1`.

## Apple TV

A native tvOS version lives in [`tvos/`](tvos/). It reads photos straight from iCloud Photos on the
Apple TV (shared albums included), so it needs no Mac or export. Build and install it with Xcode and a
free Apple ID (installs last 7 days) — see [docs/appletv.md](docs/appletv.md). On the remote: Back opens
settings, click pauses, swipe right skips ahead, and Play/Pause controls any music playing in the
background.

## How it works

- **Matching.** Every photo is summarised by the average CIELAB colour of its four quadrants
  (12 numbers), cropped to the screen's aspect ratio. The target photo is cut into an N×N grid of
  cells with the same description, and each cell gets the nearest photo. Cells are filled in random
  order; a photo can't repeat within *repeat spacing* cells, and each reuse adds a small penalty so
  more of the library gets used.
- **Seamless zoom.** Cells have the same aspect ratio as the screen, so one tile at scale N is exactly
  a full-screen photo. The camera is a pure zoom about the fixed point `f = N·t / (N−1)` (t = the target
  tile's corner), interpolated in log space so it feels constant-speed. When the zoom ends, the tile *is*
  the next photo — the next cycle starts from the identical frame.
- **Zoom out.** The same camera path played backwards: the current photo is placed in the central
  cell of the next photo's mosaic whose colours suit it best, and the camera pulls back until that
  mosaic resolves into the next photo. Either direction ends on exactly the frame the next cycle
  starts with, so they can alternate seamlessly.
- **Colour blend.** The big photo is faded over its own mosaic (fully at first, then faintly) — the
  classic photomosaic trick that makes the large image read clearly.
- **Level of detail.** Each photo exists at ~64 px (always loaded), ~128 px, ~320 px and full screen
  size; the renderer picks the smallest that is sharp enough for each tile's on-screen size and loads
  bigger versions on demand into size-limited caches. While tiles are tiny, the whole mosaic is drawn
  from one pre-rendered texture. Full-size images load only for the next photo and its neighbours.
- **Rotating pool.** Mosaics are matched against at most 1,500 photos, dealt from a shuffled deck, so
  build time stays well under a second however large the library is.

## Files

```
index.html               page, styles, controls
js/core.js               colour math, feature extraction, mosaic matching
js/library.js            loaders: picked files, built library, demo scenes
js/player.js             zoom camera + renderer
js/app.js                UI, settings, keyboard, autostart
tools/build_library.py   Photos export → library/
```

Project conventions: [VERSIONING.md](VERSIONING.md), [BACKLOG_FORMAT.md](BACKLOG_FORMAT.md),
[FAVICON.md](FAVICON.md) (synced from `project-dashboard` — edit the masters there).
