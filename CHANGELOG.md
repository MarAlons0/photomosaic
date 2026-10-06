# Changelog

All notable changes to Photomosaic are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/);
this project adheres to [Semantic Versioning](https://semver.org/) per `VERSIONING.md`.

## [0.5.1] – 2026-10-06
### Fixed
- Apple TV: the system screen saver could start during playback. The app now re-asserts "keep the screen awake" whenever it becomes active and every minute while running.

## [0.5.0] – 2026-10-06
### Added
- **Apple TV app** (`tvos/`): a native Swift/Metal version of the player that reads photos straight from iCloud Photos on the Apple TV — including shared albums such as Nature — with no Mac, server or export. See [docs/appletv.md](docs/appletv.md).
  - Zoom in / out / alternate with seamless cycles; the next mosaic is built in the background while the current zoom plays.
  - Micros in a GPU texture atlas (one draw call for all small tiles); 480 px and full-size versions stream from iCloud on demand.
  - Settings screen on the remote's Back button: album picker, direction, grid size, zoom duration, pause, colour blend — remembered between launches. Play/Pause pauses (with a badge), click skips ahead.
  - Layered parallax app icon and Top Shelf images (`tvos/tools/make_icons.py`, abstract artwork).

## [0.4.0] – 2026-10-05
### Added
- **Zoom-out mode**: each photo shrinks into a tile of the next photo's mosaic, which then resolves into that photo — the reverse of the original dive. **Alternate** switches direction every cycle. Set it in the settings panel (*Direction*) or with `?direction=in|out|alternate`.
- The outgoing photo is placed in the central cell whose colours best suit it, so it blends into the new mosaic; tiles that appear large when zooming out are pre-loaded during the pause.

### Changed
- The photo for the next mosaic is chosen (and pre-loaded) a cycle ahead.

## [0.3.0] – 2026-10-05
### Added
- **Big-library support** (tested with 6,500 photos): each mosaic is built from the next 1,500 photos of a shuffled deck (**rotating pool**), so build time stays bounded (~0.3 s at 150 × 150) and every photo comes round.
- **Lazy loading**: only a 64 px version of each photo stays in memory; 128 px, 320 px and full-size versions load as tiles grow on screen, held in size-limited LRU caches.
- **`?lib=<folder>`** picks a library built with `build_library.py --out <folder>`, so several libraries (e.g. a shared album) can live side by side.

### Changed
- `build_library.py` no longer caps libraries at 1,500 photos by default (`--limit` is still available).
- Script URLs carry the version (`?v=`), so browsers pick up new releases instead of running cached code.

### Fixed
- Dropped frames when full-size photos first appear late in the zoom: they're now decoded up front (`ImageBitmap`) and pre-uploaded to the GPU.

## [0.2.0] – 2026-10-05
### Changed
- **Softer photo → mosaic reveal**: the crossfade now follows on-screen tile size instead of time, dissolving the photo while tiles grow from their starting size to ~40 px — so the mosaic emerges from barely-visible specks rather than popping in.
- **Finer grids**: grid size now goes up to 200 × 200 (default 100, was 60), so tiles start much smaller.

### Added
- Pre-rendered mosaic texture: while tiles are small, the whole mosaic is drawn as one image, keeping fine grids smooth (~1–2 ms per frame at 150 × 150).

## [0.1.0] – 2026-10-05
### Added
- **Recursive mosaic zoom player** (`index.html`): a photo dissolves into a mosaic of other photos, the camera zooms into one tile until it fills the screen, and the cycle repeats seamlessly.
- **Photomosaic matcher**: 2×2-quadrant CIELAB features, nearest-match tiles, no-repeat spacing and a reuse penalty; cells and tiles share the screen's aspect ratio.
- **Three photo sources**: pick or drop a folder/photos in the browser, a pre-built library, or procedurally painted demo scenes.
- **`tools/build_library.py`**: turns a Photos export into `library/` (inline thumbnails + tile and full-size JPEGs); incremental, with `--prune` and `--limit`.
- Settings panel (grid size, zoom duration, pause per photo, colour blend, repeat spacing), URL overrides, keyboard shortcuts, `?saver=1` / `?demo=1` modes for screen-saver wrappers.
