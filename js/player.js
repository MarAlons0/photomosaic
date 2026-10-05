/*
 * The zoom player.
 *
 * One "cycle": photo A fills the screen, then the camera zooms into A's mosaic
 * until a single tile (photo B) fills the screen. B then becomes the next A.
 *
 * Camera: a pure zoom about a fixed point. World space is the screen itself
 * (W x H canvas px), the mosaic is an N x N grid whose cells have the screen's
 * aspect ratio, so the target cell at top-left t fills the screen at scale N.
 * The fixed point f satisfies f + N*(t - f) = 0, i.e. f = N*t / (N - 1),
 * giving screen = f + s*(world - f) for s from 1 to N. Scale is interpolated
 * in log space so the zoom feels constant-speed.
 *
 * Zoom-out cycles play the same camera path backwards: photo b fills the
 * screen as a tile, and the camera pulls back until a's mosaic resolves into a.
 * Either way, the last frame of a cycle is the first frame of the next.
 *
 * Scaling to big libraries:
 *   - Rotating pool: each mosaic is built from POOL_SIZE photos dealt from a
 *     shuffled deck, so match cost is bounded and every photo comes round.
 *   - Lazy levels: only each photo's 64 px micro is resident. Larger versions
 *     are requested as tiles grow on screen and kept in per-size LRU caches.
 */
(function (PM) {
  'use strict';

  const POOL_SIZE = 1500;
  const RECENT = 12;
  const TEX_MAX = 4096;      // max side of the pre-rendered mosaic texture
  const REVEAL_END = 40;     // CSS px tile width by which the mosaic is fully revealed
  const CAPS = { tiny: 3000, mid: 800, hires: 14 };  // cached versions per size
  const CONCURRENCY = 6;

  const clamp01 = t => Math.min(1, Math.max(0, t));
  const smooth = t => t * t * (3 - 2 * t);
  const lerp = (a, b, t) => a + (b - a) * t;
  const easeInOut = u => (1 - Math.cos(Math.PI * u)) / 2;

  /*
   * How strongly photo A is laid over its own mosaic.
   * The reveal follows on-screen tile size (log scale), not time: the photo
   * dissolves while tiles grow from their starting size to REVEAL_END px, so
   * with a fine grid the mosaic emerges from barely-visible specks. It settles
   * at the "tint" cheat, then fades to 0 as tile B takes over the screen.
   */
  function overlayAlpha(p, tileCss, tileCss0, tint) {
    const a0 = Math.log(Math.max(tileCss0, 2));
    const a1 = Math.log(Math.max(tileCss0 * 3, REVEAL_END));
    const reveal = smooth(clamp01((Math.log(tileCss) - a0) / (a1 - a0)));
    const handoff = 1 - smooth(clamp01((p - 0.72) / 0.22));
    return lerp(1, tint, reveal) * handoff;
  }

  // Smallest loaded version of a photo that is sharp enough to draw w px wide.
  function pickLevel(levels, w) {
    for (const l of levels) if (l.crop[2] >= w * 0.85) return l;
    return levels[levels.length - 1];
  }

  function shuffled(n) {
    const a = new Int32Array(n);
    for (let i = 0; i < n; i++) a[i] = i;
    for (let i = n - 1; i > 0; i--) {
      const j = (Math.random() * (i + 1)) | 0;
      const t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }

  PM.Player = class {
    constructor(canvas, photos, settings) {
      this.canvas = canvas;
      this.ctx = canvas.getContext('2d', { alpha: false });
      this.photos = photos;
      this.settings = settings;
      this.cache = { tiny: new Map(), mid: new Map(), hires: new Map() };  // photo index -> entry
      this.qHigh = [];
      this.qLow = [];
      this.active = 0;
      this.warm = [];              // freshly loaded full-size images to pre-upload
      this.pinned = new Set();
      this.recent = [];
      this.deck = null;
      this.deckPos = 0;
      this.paused = false;
      this.elapsed = 0;
      this.cycle = null;
      this.running = false;
      this._frame = this._frame.bind(this);
      this.resize();
    }

    /* ---------- setup ---------- */

    resize() {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.dpr = dpr;
      this.W = Math.round(window.innerWidth * dpr);
      this.H = Math.round(window.innerHeight * dpr);
      this.canvas.width = this.W;
      this.canvas.height = this.H;
      this.aspect = this.W / this.H;
      // Tile widths (device px) at which a sharper version is worth loading. Tied to
      // screen width so the number of tiles on screen at that moment stays bounded.
      this.tinyAt = Math.max(56, this.W / 50);
      this.midAt = Math.max(110, this.W / 22);
      for (const p of this.photos) {
        for (const l of p.levels) l.crop = PM.cover(l.w, l.h, this.aspect);
        const [mw, mh] = PM.dims(p.micro);
        p.feat = PM.gridFeatures(p.micro, PM.cover(mw, mh, this.aspect), 1, 8);
      }
    }

    async start(first) {
      const shown = first == null ? (Math.random() * this.photos.length) | 0 : first;
      this.upcoming = this.pickUpcoming(shown);
      this.pinned = new Set([shown, this.upcoming]);
      await Promise.all([
        this.request(shown, 'hires', true),
        this.request(shown, 'tiny', true),
        this.request(this.upcoming, 'tiny', true),
        this.request(this.upcoming, 'hires', true),
      ]);
      this.beginCycle(shown);
      if (!this.running) {
        this.running = true;
        this.last = performance.now();
        requestAnimationFrame(this._frame);
      }
    }

    stop() { this.running = false; }

    // Rebuild the current cycle (after a resize or a grid-size change).
    restart() {
      const c = this.cycle;
      if (c) this.beginCycle(c.shown, true, c.dir === 'out' ? c.a : undefined);
    }

    next() { if (this.cycle) this.beginCycle(this.cycle.end); }

    // Direction of the next cycle: 'in', 'out', or alternating between them.
    _direction(restarting) {
      const d = this.settings.direction;
      if (d === 'alternate') {
        if (!this.cycle) return 'in';
        if (restarting) return this.cycle.dir;
        return this.cycle.dir === 'in' ? 'out' : 'in';
      }
      return d === 'out' ? 'out' : 'in';
    }

    // Start a cycle that opens on photo `shown` filling the screen.
    beginCycle(shown, restarting = false, mosaicPhoto) {
      if (this._direction(restarting) === 'out') this.startCycleOut(shown, mosaicPhoto);
      else this.startCycle(shown);
    }

    /* ---------- on-demand image versions ---------- */

    // Load (or touch, if already cached) one size of photo i. Never rejects.
    request(i, kind, high = false) {
      const m = this.cache[kind];
      const hit = m.get(i);
      if (hit) {
        m.delete(i);
        m.set(i, hit);
        return hit.promise;
      }
      const p = this.photos[i];
      const entry = { level: null, failed: false };
      entry.promise = new Promise(resolve => {
        const run = async () => {
          try {
            const { src, tainted } = await p.load[kind](this.W, this.H);
            if (m.get(i) !== entry) { PM.release(src); return; }  // evicted while loading
            const [w, h] = PM.dims(src);
            entry.level = { src, w, h, kind, tainted, crop: PM.cover(w, h, this.aspect) };
            p.levels = p.levels.filter(l => l.kind !== kind).concat(entry.level)
              .sort((x, y) => x.crop[2] - y.crop[2]);
            if (kind === 'hires') this.warm.push(src);
          } catch (e) {
            entry.failed = true;  // stays cached so we don't retry every frame
            console.warn(e);
          } finally {
            resolve();
          }
        };
        (high ? this.qHigh : this.qLow).push(run);
      });
      m.set(i, entry);
      this._evict(kind);
      this._pump();
      return entry.promise;
    }

    _pump() {
      while (this.active < CONCURRENCY) {
        // High priority first (next photo, analysis); otherwise newest request first,
        // since it's the most likely to still be on screen.
        const run = this.qHigh.shift() || this.qLow.pop();
        if (!run) return;
        this.active++;
        run().then(() => { this.active--; this._pump(); });
      }
    }

    _evict(kind) {
      const m = this.cache[kind];
      for (const [i, entry] of m) {
        if (m.size <= CAPS[kind]) break;
        if (this.pinned.has(i)) continue;
        m.delete(i);
        if (entry.level) {
          const p = this.photos[i];
          p.levels = p.levels.filter(l => l !== entry.level);
          PM.release(entry.level.src);
        }
      }
    }

    /* ---------- cycles ---------- */

    // The next POOL_SIZE photos from a shuffled deck (reshuffled when used up).
    drawPool(a) {
      const n = this.photos.length;
      if (n - 1 <= POOL_SIZE) {
        const all = [];
        for (let i = 0; i < n; i++) if (i !== a || n === 1) all.push(i);
        return all;
      }
      const picked = new Set();
      while (picked.size < POOL_SIZE) {
        if (!this.deck || this.deckPos >= n) { this.deck = shuffled(n); this.deckPos = 0; }
        const i = this.deck[this.deckPos++];
        if (i !== a) picked.add(i);
      }
      return [...picked];
    }

    // A random photo to build the next mosaic from, avoiding recently shown ones.
    pickUpcoming(exclude) {
      const n = this.photos.length;
      for (let t = 0; t < 50; t++) {
        const i = (Math.random() * n) | 0;
        if (i !== exclude && !this.recent.includes(i)) return i;
      }
      return (exclude + 1 + ((Math.random() * (n - 1)) | 0)) % n;
    }

    _remember(i) {
      this.recent.push(i);
      const keep = Math.min(RECENT, Math.floor(this.photos.length / 2));
      while (this.recent.length > keep) this.recent.shift();
    }

    // Features of photo y's N x N cells, and its mosaic.
    _mosaicOf(y, N) {
      // Analyse from the sharpest version we're allowed to read pixels from
      // (micro is always readable, so this never comes up empty).
      const readable = this.photos[y].levels.filter(l => !l.tainted).pop();
      const cells = PM.gridFeatures(readable.src, readable.crop, N, 2);
      const assign = PM.buildMosaic(cells, N, this.drawPool(y), this.photos.map(p => p.feat), {
        spacing: this.settings.spacing,
        penalty: 60,
      });
      return { cells, assign };
    }

    // Install a cycle and fetch what it needs: full size for both photos and the
    // tiles around the target cell, plus the upcoming photo for analysis.
    _install(dir, a, b, N, assign, cell) {
      const { W, H } = this;
      const col = cell % N, row = (cell / N) | 0;
      this.cycle = {
        dir, a, b, N, assign, cell,
        shown: dir === 'out' ? b : a,   // fills the screen when the cycle starts
        end: dir === 'out' ? a : b,     // ... and when it ends
        tx: (col * W) / N, ty: (row * H) / N,
      };
      this.elapsed = 0;
      this.buildTexture();

      const near = [];
      for (let r = row - 1; r <= row + 1; r++) {
        for (let c = col - 1; c <= col + 1; c++) {
          if (r >= 0 && c >= 0 && r < N && c < N) near.push(assign[r * N + c]);
        }
      }
      this.upcoming = this.pickUpcoming(this.cycle.end);
      this.pinned = new Set([a, b, this.upcoming, ...near]);
      this.request(a, 'hires', true);
      this.request(b, 'hires', true);
      near.forEach(i => this.request(i, 'hires', true));
      this.request(this.cycle.end, 'tiny', true);
      this.request(this.upcoming, 'tiny', true);
    }

    // Zoom in: photo a dissolves into its mosaic; dive into a tile b.
    startCycle(a) {
      const N = this.settings.grid;
      const { assign } = this._mosaicOf(a, N);

      // Zoom into a cell near the middle whose photo hasn't been shown lately.
      this._remember(a);
      const lo = Math.floor(N * 0.2), hi = Math.ceil(N * 0.8);
      const central = [], fresh = [];
      for (let r = lo; r < hi; r++) {
        for (let c = lo; c < hi; c++) {
          const i = r * N + c;
          central.push(i);
          if (!this.recent.includes(assign[i])) fresh.push(i);
        }
      }
      const choices = fresh.length ? fresh : central;
      const cell = choices[(Math.random() * choices.length) | 0];
      this._install('in', a, assign[cell], N, assign, cell);
    }

    // Zoom out: photo x, filling the screen, turns out to be one tile of photo y's
    // mosaic; pull back until y's tiles blend into y itself.
    startCycleOut(x, y = this.upcoming) {
      if (y == null || y === x) y = this.pickUpcoming(x);
      const N = this.settings.grid;
      const { cells, assign } = this._mosaicOf(y, N);

      // Put x in a central cell whose colours suit it (random among the best few).
      const fx = this.photos[x].feat;
      const lo = Math.floor(N * 0.2), hi = Math.ceil(N * 0.8);
      const scored = [];
      for (let r = lo; r < hi; r++) {
        for (let c = lo; c < hi; c++) {
          const i = r * N + c;
          let d = 0;
          for (let j = 0; j < 12; j++) { const e = cells[i * 12 + j] - fx[j]; d += e * e; }
          scored.push([d, i]);
        }
      }
      scored.sort((p, q) => p[0] - q[0]);
      const cell = scored[(Math.random() * Math.min(5, scored.length)) | 0][1];
      assign[cell] = x;

      this._remember(x);
      this._install('out', y, x, N, assign, cell);
      this.prefetch();
    }

    /*
     * Zooming out, tiles first appear large, so load their sharper versions up front
     * (during the pause on the photo) instead of as they grow. Mid-size requests are
     * queued last so they load first.
     */
    prefetch() {
      const { W, H } = this;
      const { N, assign, tx, ty } = this.cycle;
      const fx = (N * tx) / (N - 1), fy = (N * ty) / (N - 1);
      const cw = W / N, ch = H / N;
      for (const [kind, at] of [['tiny', this.tinyAt], ['mid', this.midAt]]) {
        const s = Math.min(N, Math.max(1, at / cw));
        const c0 = Math.max(0, Math.floor((fx - fx / s) / cw)), c1 = Math.min(N - 1, Math.ceil((fx + (W - fx) / s) / cw) - 1);
        const r0 = Math.max(0, Math.floor((fy - fy / s) / ch)), r1 = Math.min(N - 1, Math.ceil((fy + (H - fy) / s) / ch) - 1);
        for (let r = r0; r <= r1; r++) {
          for (let c = c0; c <= c1; c++) this.request(assign[r * N + c], kind);
        }
      }
    }

    /*
     * Pre-render the whole mosaic into one canvas. While tiles are small on
     * screen, one drawImage of this texture replaces thousands of per-tile
     * draws, which is what makes fine grids (small starting tiles) affordable.
     */
    buildTexture() {
      const { N, assign } = this.cycle;
      const tw = Math.max(2, Math.floor(Math.min(48, TEX_MAX / N, (TEX_MAX * this.aspect) / N)));
      const th = Math.max(2, Math.round(tw / this.aspect));
      if (!this.tex) this.tex = document.createElement('canvas');
      this.tex.width = N * tw;
      this.tex.height = N * th;
      const g = this.tex.getContext('2d', { alpha: false });
      g.imageSmoothingEnabled = true;
      g.imageSmoothingQuality = 'high';
      for (let r = 0; r < N; r++) {
        for (let c = 0; c < N; c++) {
          const l = pickLevel(this.photos[assign[r * N + c]].levels, tw);
          const k = l.crop;
          g.drawImage(l.src, k[0], k[1], k[2], k[3], c * tw, r * th, tw, th);
        }
      }
      this.texTile = tw;
    }

    /* ---------- animation ---------- */

    _frame(now) {
      if (!this.running) return;
      const dt = Math.min(0.1, (now - this.last) / 1000);
      this.last = now;
      if (!this.paused) this.elapsed += dt;

      const { hold, duration } = this.settings;
      let p = 0;
      if (this.elapsed > hold) {
        const u = (this.elapsed - hold) / duration;
        if (u >= 1) this.beginCycle(this.cycle.end);
        else p = easeInOut(u);
      }
      this.draw(this.cycle.dir === 'out' ? 1 - p : p);
      requestAnimationFrame(this._frame);
    }

    draw(p) {
      const { ctx, W, H, photos } = this;
      const { N, assign, tx, ty, a } = this.cycle;
      const s = Math.pow(N, p);
      const fx = (N * tx) / (N - 1), fy = (N * ty) / (N - 1);
      const X = wx => fx + s * (wx - fx);
      const Y = wy => fy + s * (wy - fy);
      const tile = (W / N) * s; // on-screen tile width, device px
      const alpha = overlayAlpha(p, tile / this.dpr, W / N / this.dpr, this.settings.tint);

      // World-space rectangle currently on screen, and its part inside the mosaic.
      const wx0 = fx - fx / s, wx1 = fx + (W - fx) / s;
      const wy0 = fy - fy / s, wy1 = fy + (H - fy) / s;
      const vx0 = Math.max(0, wx0), vx1 = Math.min(W, wx1);
      const vy0 = Math.max(0, wy0), vy1 = Math.min(H, wy1);

      // Draw one newly loaded full-size image into a corner (immediately painted over)
      // so the browser uploads it to the GPU now rather than mid-zoom, where a few
      // first draws at once would drop frames.
      const warm = this.warm.shift();
      if (warm) try { ctx.drawImage(warm, 0, 0, 1, 1); } catch (e) { /* evicted and closed meanwhile */ }

      ctx.fillStyle = '#000';
      ctx.fillRect(0, 0, W, H);
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'medium';

      if (alpha < 1 && tile <= this.texTile * 1.25) {
        // Small tiles: draw the visible part of the pre-rendered mosaic in one go.
        const tex = this.tex, kx = tex.width / W, ky = tex.height / H;
        ctx.drawImage(
          tex,
          vx0 * kx, vy0 * ky, (vx1 - vx0) * kx, (vy1 - vy0) * ky,
          X(vx0), Y(vy0), (vx1 - vx0) * s, (vy1 - vy0) * s
        );
      } else if (alpha < 1) {
        // Sharper version worth having at this tile size (micro needs no request).
        const want = tile > this.midAt ? 'mid' : tile > this.tinyAt ? 'tiny' : null;
        const cw = W / N, ch = H / N;
        const c0 = Math.max(0, Math.floor(wx0 / cw)), c1 = Math.min(N - 1, Math.ceil(wx1 / cw) - 1);
        const r0 = Math.max(0, Math.floor(wy0 / ch)), r1 = Math.min(N - 1, Math.ceil(wy1 / ch) - 1);
        for (let r = r0; r <= r1; r++) {
          // Snap tile edges to whole pixels so neighbours share edges (no hairline seams).
          const y0 = Math.round(Y(r * ch)), y1 = Math.round(Y((r + 1) * ch));
          for (let c = c0; c <= c1; c++) {
            const x0 = Math.round(X(c * cw)), x1 = Math.round(X((c + 1) * cw));
            const tw = x1 - x0;
            const idx = assign[r * N + c];
            const l = pickLevel(photos[idx].levels, tw);
            const k = l.crop;
            ctx.drawImage(l.src, k[0], k[1], k[2], k[3], x0, y0, tw, y1 - y0);
            if (want) this.request(idx, want);
          }
        }
      }

      if (alpha > 0) {
        // Photo A over its mosaic: fully at the start, then as a faint colour cheat.
        const levels = photos[a].levels;
        const l = levels[levels.length - 1];
        const [sx, sy, sw, sh] = l.crop;
        ctx.globalAlpha = alpha;
        ctx.drawImage(
          l.src,
          sx + (vx0 / W) * sw, sy + (vy0 / H) * sh, ((vx1 - vx0) / W) * sw, ((vy1 - vy0) / H) * sh,
          X(vx0), Y(vy0), (vx1 - vx0) * s, (vy1 - vy0) * s
        );
        ctx.globalAlpha = 1;
      }
    }
  };
})(window.PM);
