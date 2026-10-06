# Apple TV version — design

_Status: shipped in v0.5.0; captions added in v0.6.0 · 2026-10-06_

Goal: run Photomosaic natively on Apple TV, reading photos straight from iCloud Photos (including
the **Nature** shared album) — no Mac, no server, no AirPlay.

## Constraints

- **tvOS has no browser or web view**, so the HTML player can't run there. This is a native Swift
  app; the algorithms port over, the code doesn't.
- **Third-party screen savers aren't allowed on tvOS.** It's an app you open (it can keep the screen
  awake while running).
- **Signing:** starting with a free Apple ID — Xcode installs the app on the Apple TV, and the
  install expires after **7 days** (re-run from Xcode to renew). The paid Developer Program
  ($99/yr) lifts this and enables TestFlight; revisit once the app is in daily use.
- **Local storage on tvOS is limited and purgeable** — no large persistent caches; everything is
  loaded on demand from the photo library.

## Photo source: PhotoKit on the Apple TV

The app asks for Photos access, then fetches assets with PhotoKit (`PHAssetCollection` /
`PHImageManager`). Shared albums are `PHAssetCollectionSubtype.albumCloudShared`.

**Answered by the probe (2026-10-06, Apple TV 4K 3rd gen "Sala", tvOS 27):** yes — with full
Photos access the app sees the whole library (31,902 photos) and every shared album, including
**Nature (4,425 photos)**. 60 thumbnails (320 px) loaded in under a second with no failures. The
Apple TV must have iCloud Photos and Shared Albums turned on (it already did — the built-in screen
saver uses Nature).

Fallback if shared albums aren't available: copy the album's photos into a regular iCloud album, or
serve `library/` from the Mac over the home network (the web player's format already fits).

## Architecture (milestone 2+)

| Web player (`js/`) | tvOS app |
|---|---|
| `core.js` — CIELAB quadrant features, matcher | `Matcher.swift` — same maths, on a background queue |
| `library.js` — loaders, lazy levels | `PhotoSource.swift` — PhotoKit fetch + `PHCachingImageManager` |
| `player.js` — camera, texture, LOD caches | `MosaicRenderer.swift` — Metal |
| `app.js` — settings, keys | SwiftUI shell + Siri Remote (play/pause, swipe = next, menu = settings) |

**Rendering (Metal):** the camera maths are unchanged (zoom about `f = N·t/(N−1)`, log-space scale,
in/out/alternate). All 64 px micros live in one texture atlas (4096² holds ~6,000 tiles), so the
far-zoom phase is a single instanced draw; 320 px and full-size versions are separate textures
requested from PhotoKit as tiles grow, in LRU caches like the web player. 4K output (3840×2160).

**Settings:** direction, grid size, zoom duration, pause, colour blend — stored in `UserDefaults`.
Album picker on first launch.

## Milestones

1. ✅ **Probe** — minimal app: request Photos access, list albums (incl. shared) with counts, show one
   thumbnail. Answers the open question on real hardware.
2. ✅ **Port matcher + texture** — build mosaics from the chosen album; show a static mosaic.
   On Sala: all 4,425 Nature micros load in ~20 s; a 100×100 4K mosaic builds in ~2 s (CPU tile
   drawing dominates — Metal in milestone 3 replaces it).
3. ✅ **Zoom player** — Metal renderer, in/out/alternate, seamless cycles.
   Micros in a 96×54-slot atlas (one instanced draw for all small tiles); 480 px and full-size
   textures on demand; the next cycle is planned in the background. Shaders compile at launch
   (`Shaders.swift`), so building needs no Metal Toolchain download. Smooth on Sala.
4. ✅ **Polish** — remote controls, settings screen (Back), album picker, persisted settings,
   idle timer disabled while playing, pause badge, layered app icon + Top Shelf.

## Photo captions (v0.6.0)

`Captions.swift`: date from `PHAsset.creationDate`; place from `PHAsset.location`, reverse-geocoded
with `CLGeocoder` (one request at a time, cached per photo). The player shows the caption only during
the pause (`u == 0`) and prefetches the next photo's place when a cycle starts. Many shared-album
photos carry no location (about 1 in 10 of the exported Nature files had GPS), so those show the date
only; the settings screen reports the album's actual count.

## Building & installing (no Xcode clicks needed)

```bash
cd tvos
xcodebuild -project PhotomosaicTV.xcodeproj -scheme PhotomosaicTV -destination 'id=<Apple TV UDID>' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device <UDID> <DerivedData>/Build/Products/Debug-appletvos/PhotomosaicTV.app
xcrun devicectl device process launch --device <UDID> com.marioalonso.PhotomosaicTV
```

`xcrun devicectl list devices` shows the UDID. Free-team installs expire after 7 days — re-run the
install to renew. The project file is hand-written (Xcode 27's new-project flow made a Mac app); it
uses a folder-synchronised group, so any `.swift` file added to `tvos/PhotomosaicTV/` is built.

## Repo layout

```
tvos/PhotomosaicTV.xcodeproj
tvos/PhotomosaicTV/          Swift sources (folder-synchronised group: new files are picked up automatically)
```
