# Mac app

_Status: shipped in v0.10.0 · 2026-11-19_

A native macOS version of the Apple TV app: it reads an album (or the newest photos) straight from
the Photos library, so unlike the browser version it needs no export, library build or local server.
Made to share with friends who keep their photos in Apple Photos.

## How it's built

One Xcode project, [`tvos/PhotomosaicTV.xcodeproj`](../tvos/PhotomosaicTV.xcodeproj), two targets:

| Folder | Target(s) | What's in it |
|---|---|---|
| `tvos/Shared/` | both | player (Metal), photo library (PhotoKit), planner and matcher, smart framing (Vision), captions, textures and caches, memory log, watermark, screen shape |
| `tvos/PhotomosaicTV/` | PhotomosaicTV | tvOS app: remote handling, settings screen, background cache release |
| `tvos/PhotomosaicMac/` | Photomosaic | macOS app: window and full screen, keys and menus, settings sheet, keeping the display awake |

**Screen shape.** The Apple TV is 16:9; most Macs are 16:10. `Screen.aspect` is set once at launch
(the display the app starts on) and drives the atlas slot size (96×54 at 16:9, 96×60 at 16:10), the
photo crops and the cached texture sizes. A window of another shape shows the mosaic with black bars.

**Files.** The Mac app isn't sandboxed, so its framing results and memory log go in
`~/Library/Caches/com.marioalonso.Photomosaic/` rather than straight in Caches.

**Album choice** (both apps): the album set in settings; by default "Portfolio", else the largest
shared album, else the largest library album (100+ photos), else **Recent photos** — the newest
5,000 photos of the library, also offered at the top of the album list.

## Keys

F full screen (Esc leaves it) · Space or click pause · N or → next photo · S or ⌘, settings.
The Mac's display stays awake while the mosaic plays (not while paused). The pointer hides until
the mouse moves.

## Building and sharing

```bash
tvos/build-mac.sh
```

builds a universal (Apple silicon + Intel) Release copy for macOS 14+ into `dist/` (git-ignored):
`dist/Photomosaic.app` and `dist/Photomosaic-<version>.zip` to send.

The app is **signed ad hoc** ("Sign to Run Locally"): no Apple ID or developer account, and it never
expires. On another Mac, Gatekeeper blocks it the first time; the person allows it once in
**System Settings → Privacy & Security → Open Anyway**, then grants Photos access. Each new build is
a new signature, so updating repeats both steps. A paid Apple Developer account would allow Developer
ID signing and notarization, removing them.
