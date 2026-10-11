# Bug: loading can hang at 0% — `await img.decode()` never settles

**Found:** 2026-10-08, while integrating this engine into the Looking4Nature gallery.
**Status:** **fixed upstream in v0.6.2** (see *Upstream fix* below); also fixed in the gallery's own loader.
**Severity:** hangs the whole load, silently — no error, no timeout, progress stuck at 0%.

## Symptom

The page loads, the progress text appears, and nothing further happens. No console error, no
failed request, no partial progress — the counter never advances past 0 and the mosaic never
starts. Reloading in a foreground tab usually works, which makes it look intermittent.

## Where

`js/library.js`:

```js
function loadImg(url) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.decoding = 'async';
    // Decode off the main thread now, so the first drawImage doesn't stall a frame.
    img.onload = () => (img.decode ? img.decode() : Promise.resolve()).then(() => resolve(img), () => resolve(img));
    img.onerror = () => reject(new Error('Could not load ' + url.slice(0, 80)));
    img.src = url;
  });
}
```

## Why it hangs

`HTMLImageElement.decode()` resolves when the image has been decoded **for rendering**. In a
document that is not being rendered — a background tab, a hidden window, or a browser under device
emulation — the decode is never scheduled, so the promise neither resolves nor rejects. It simply
stays pending forever.

`loadImg` awaits that promise before resolving, and `pool()` runs a fixed number of workers:

```js
const worker = async () => {
  while (next < items.length) {
    const i = next++;
    try { await fn(items[i], i); } catch (e) { console.warn(e); }   // ← never returns
    done++;
    ...
```

Each worker that hits a stuck decode is parked permanently. With `pool(..., 8, ...)` in
`fromManifest`, the first eight photos are enough to consume every worker, and the load stops dead.
`Promise.all` over the workers never settles, so `fromManifest` never returns and the caller has
nothing to time out on.

Note the failure is **not** in the network: the images download fine. The bug is strictly in waiting
for the decode.

## Evidence

Reproduced against a 718-photo library under mobile device emulation (Chromium, 375×812):

| | |
|---|---|
| Time waited | 35+ s |
| Progress bar | `0%`, never moved |
| Cloudinary image requests issued | 9 |
| Those requests' status | **all complete**, `duration` ≈ 2 ms, `transferSize` 0 (served from cache) |
| `responseEnd` | ≈ 42 ms for every one |

So eight images had fully arrived within 42 ms, and the loader was still at zero more than half a
minute later. Fronting the tab did not release them — once a decode is stuck it stays stuck.

After capping the decode wait, the identical page started in **~1 second**.

## Why it matters here

The risk is highest in exactly this project's headline use case. `?saver=1` under
[WebViewScreenSaver](https://github.com/liquidx/webviewscreensaver) renders into a host whose
rendering lifecycle is not a normal foreground tab, and a screen saver starts precisely when the
machine is idle and the page may not be composited yet.

`README.md` currently carries this caveat:

> Not yet verified inside WebViewScreenSaver on this Mac — if the page stays blank from `file://`,
> serve the folder instead…

**A stuck decode produces exactly that symptom** — a blank page that is not an error. It is worth
ruling this bug out before concluding anything about `file://` when that verification is done
(the open 🔴 High backlog item). They may be the same problem.

## Suggested fix

Keep the up-front decode as an optimisation, but never let it block the pipeline:

```js
// decode() is a courtesy, not a requirement: decoding up front keeps the first
// drawImage from stalling a frame. But it never settles in a document that is not
// being rendered (background tab, hidden window, device emulation), and pool() runs
// a fixed set of workers — so a few stuck decodes halt the entire load at 0%.
// Cap the wait and carry on with the image, which has already loaded.
function decoded(img, ms = 2000) {
  if (!img.decode) return Promise.resolve(img);
  return Promise.race([
    img.decode().catch(() => {}),
    new Promise(r => setTimeout(r, ms)),
  ]).then(() => img);
}

function loadImg(url) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.decoding = 'async';
    img.onload = () => decoded(img).then(resolve);
    img.onerror = () => reject(new Error('Could not load ' + url.slice(0, 80)));
    img.src = url;
  });
}
```

`img.decoding = 'async'` already tells the browser not to block on decode at draw time, so the
fallback path stays smooth; the timeout only costs a possible single-frame hitch on the first draw
of an image whose decode was still pending.

Worth considering alongside it: `pool()` currently has no way to survive a worker that never
returns. A per-item timeout there would make any future stall degrade (skip a photo) instead of
hanging the whole load.

## Verifying the fix

Device emulation is the most reliable reproduction — it stalls every time, where a background tab is
timing-dependent:

1. Open the page in Chrome with DevTools → device toolbar on (any phone preset), hard-reloaded.
2. Before the fix: progress sits at 0% indefinitely while
   `performance.getEntriesByType('resource')` shows the image requests already complete.
3. After the fix: the first mosaic appears in about a second.

## Already fixed downstream

The Looking4Nature gallery vendors `core.js`, `library.js` and `player.js` verbatim and adds its own
`public/photomosaic/cloudinary-loader.js`. That loader hit this bug, and carries the fix above
(shipped as gallery v0.9.1). The vendored `library.js` there is **unchanged**, so applying the fix
upstream and re-copying will bring the two back into line.

That loader also sets `img.crossOrigin = 'anonymous'`, which this project's `loadImg` does not —
needed because `PM.gridFeatures` calls `getImageData`, and a cross-origin image taints the canvas.
Not a bug here (upstream loads same-origin files and `data:` URIs), but worth knowing if remote
image sources are ever supported directly.

## Upstream fix (v0.6.2)

Applied in `js/library.js`, with one change from the suggestion above: instead of capping the
`decode()` wait at 2 s, `loadImg` **no longer calls `decode()` at all**.

Reason: the cap fixes the hang but not the cost. In a non-rendering document *every* decode waits out
the full cap, so with 8 workers loading runs at ~4 photos/s — measured **30 of 4,425** photos after
10 s under device emulation, i.e. ~18 minutes to start. Dropping the up-front decode loses nothing:

- micros/tiles (≤ 320 px) decode in ~1 ms on first draw;
- full-size photos, where an up-front decode does prevent a dropped frame, are already converted
  with `createImageBitmap(img)` in the hires loader — it decodes off-thread and doesn't depend on
  rendering.

Also added the per-item timeout suggested above: `pool()` gives up on an item after 30 s (warning in
the console), and the loaders return a snapshot of their results so a late finisher can't join a
running player half-initialised.

The fix also matters after start-up: the player's on-demand loads (tiny/mid/hires) go through
`loadImg` too, and each stuck decode used to occupy one of its 6 loading slots permanently.

**Verified** (Chromium, browser pane): under mobile emulation the old code stalled at
"Loading library…" with 0 photos after 10 s; the fixed code loaded all 4,425 and was playing within
~10 s, with full-size bitmaps and 320 px tiles continuing to load (no stuck slots). The old code also
hung in a normal 1440×900 window simply because the pane was hidden while loading.

**For the gallery:** re-copy the upstream `library.js` (not the capped-wait version above), and
consider the same change in `cloudinary-loader.js` — with ~700 photos the 2 s cap would also cost
minutes whenever the page loads hidden.
