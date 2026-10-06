# Photomosaic — Backlog
_Last updated: 2026-10-06_

## 🔴 High
- [ ] **Verify in WebViewScreenSaver** — confirm `file://…/index.html?saver=1` runs as a macOS screen saver; fall back to a localhost server if not. `[chore]`

## 🟡 Medium
- [ ] **Matcher in a Web Worker** — keep mosaic building off the main thread for 200-row grids; less urgent once the rotating pool caps the match size. `[feature]`
- [ ] **Smarter zoom target** — prefer tiles whose photo is visually interesting (faces, contrast) rather than a random central cell. `[idea]`
- [ ] **Direct Photos export helper** — script using `osxphotos` to export an album straight into `library/`. `[feature]`

## 🟢 Low / Nice to have
- [ ] **Photo caption** — optionally show the location/date of the photo filling the screen. `[feature]`
- [ ] **Native `.saver` bundle** — Swift/ScreenSaver.framework port for smoother playback. `[idea]`
- [ ] **Favicon kit** — replace the inline SVG icon with the standard kit per `FAVICON.md`. `[chore]`

## ✅ Shipped
- [x] **AppleTV version** — native tvOS app reading iCloud Photos; see [docs/appletv.md](docs/appletv.md) — v0.5.0
- [x] **Zoom-out mode** — plus Alternate — v0.4.0
- [x] **Rotating tile pool** — v0.3.0
- [x] **Lazy-load tile images** — v0.3.0
- [x] **Try it with a real Photos export** — 618 photos, defaults tuned — v0.2.0
- [x] **Softer reveal + finer grids** — tile-size-based crossfade, grids up to 200 — v0.2.0
- [x] **Recursive mosaic zoom player** — v0.1.0
- [x] **Photomosaic matcher** — v0.1.0
- [x] **Library builder script** — v0.1.0
