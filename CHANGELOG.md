# Changelog

All notable changes to Photomosaic are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/);
this project adheres to [Semantic Versioning](https://semver.org/) per `VERSIONING.md`.

## [0.1.0] – 2026-10-05
### Added
- **Recursive mosaic zoom player** (`index.html`): a photo dissolves into a mosaic of other photos, the camera zooms into one tile until it fills the screen, and the cycle repeats seamlessly.
- **Photomosaic matcher**: 2×2-quadrant CIELAB features, nearest-match tiles, no-repeat spacing and a reuse penalty; cells and tiles share the screen's aspect ratio.
- **Three photo sources**: pick or drop a folder/photos in the browser, a pre-built library, or procedurally painted demo scenes.
- **`tools/build_library.py`**: turns a Photos export into `library/` (inline thumbnails + tile and full-size JPEGs); incremental, with `--prune` and `--limit`.
- Settings panel (grid size, zoom duration, pause per photo, colour blend, repeat spacing), URL overrides, keyboard shortcuts, `?saver=1` / `?demo=1` modes for screen-saver wrappers.
