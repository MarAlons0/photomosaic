# Photomosaic — Backlog
_Last updated: 2026-10-05_

## 🔴 High
- [ ] **Try it with a real Photos export** — judge mosaic quality and pacing with a few hundred real photos; tune defaults. `[chore]`
- [ ] **Verify in WebViewScreenSaver** — confirm `file://…/index.html?saver=1` runs as a macOS screen saver; fall back to a localhost server if not. `[chore]`

## 🟡 Medium
- [ ] **Matcher in a Web Worker** — keep mosaic building off the main thread for 2000+ photo libraries / 120-row grids. `[feature]`
- [ ] **Smarter zoom target** — prefer tiles whose photo is visually interesting (faces, contrast) rather than a random central cell. `[idea]`
- [ ] **Direct Photos export helper** — script using `osxphotos` to export an album straight into `library/`. `[feature]`

## 🟢 Low / Nice to have
- [ ] **Zoom-out mode** — reverse direction (photo shrinks into a tile of a bigger mosaic). `[idea]`
- [ ] **Photo caption** — optionally show the filename/date of the photo filling the screen. `[feature]`
- [ ] **Native `.saver` bundle** — Swift/ScreenSaver.framework port for smoother playback. `[idea]`
- [ ] **Favicon kit** — replace the inline SVG icon with the standard kit per `FAVICON.md`. `[chore]`

## ✅ Shipped
- [x] **Recursive mosaic zoom player** — v0.1.0
- [x] **Photomosaic matcher** — v0.1.0
- [x] **Library builder script** — v0.1.0
