# Photomosaic — Backlog
_Last updated: 2026-10-05_

## 🔴 High
- [ ] **Rotating tile pool** — each cycle draws its tiles from a fresh random subset (~1,500) of the library, so large libraries (e.g. a 6,500-photo shared album) stay fast and every photo eventually appears. `[feature]`
  - replaces the fixed `--limit` sample in `build_library.py` as the way to handle big libraries
- [ ] **Lazy-load tile images** — keep only tiny thumbnails in memory and load the 320 px versions when tiles get large on screen, capping memory at a few hundred MB regardless of library size. `[feature]`
- [ ] **Verify in WebViewScreenSaver** — confirm `file://…/index.html?saver=1` runs as a macOS screen saver; fall back to a localhost server if not. `[chore]`

## 🟡 Medium
- [ ] **Matcher in a Web Worker** — keep mosaic building off the main thread for 200-row grids; less urgent once the rotating pool caps the match size. `[feature]`
- [ ] **Smarter zoom target** — prefer tiles whose photo is visually interesting (faces, contrast) rather than a random central cell. `[idea]`
- [ ] **Direct Photos export helper** — script using `osxphotos` to export an album straight into `library/`. `[feature]`
- [ ] **AppleTV version** — I would like to be able to run the program from my AppleTV, ideally not via airplay `[feature]`
  - tvOS has no browser/web view, so this means a native Swift app (an app you open — tvOS doesn't allow third-party screen savers); needs a paid developer account to stay installed beyond 7 days
  - likely photo source: the Mac's `library/` served over the home network; check whether tvOS apps can read iCloud Photos at all

## 🟢 Low / Nice to have
- [ ] **Zoom-out mode** — reverse direction (photo shrinks into a tile of a bigger mosaic). `[idea]`
- [ ] **Photo caption** — optionally show the filename/date of the photo filling the screen. `[feature]`
- [ ] **Native `.saver` bundle** — Swift/ScreenSaver.framework port for smoother playback. `[idea]`
- [ ] **Favicon kit** — replace the inline SVG icon with the standard kit per `FAVICON.md`. `[chore]`

## ✅ Shipped
- [x] **Try it with a real Photos export** — 618 photos, defaults tuned — v0.2.0
- [x] **Softer reveal + finer grids** — tile-size-based crossfade, grids up to 200 — v0.2.0
- [x] **Recursive mosaic zoom player** — v0.1.0
- [x] **Photomosaic matcher** — v0.1.0
- [x] **Library builder script** — v0.1.0
