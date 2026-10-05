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
 */
(function (PM) {
  'use strict';

  const HIRES_CACHE = 24;
  const RECENT = 12;

  const smooth = t => t * t * (3 - 2 * t);
  const lerp = (a, b, t) => a + (b - a) * t;
  const easeInOut = u => (1 - Math.cos(Math.PI * u)) / 2;

  // How strongly photo A is laid over its own mosaic at zoom progress p.
  // 1 = only the photo; fades to the "tint" cheat, then to 0 as tile B takes over.
  function overlayAlpha(p, tint) {
    if (p < 0.06) return 1;
    if (p < 0.4) return lerp(1, tint, smooth((p - 0.06) / 0.34));
    if (p < 0.72) return tint;
    if (p < 0.94) return lerp(tint, 0, smooth((p - 0.72) / 0.22));
    return 0;
  }

  PM.Player = class {
    constructor(canvas, photos, settings) {
      this.canvas = canvas;
      this.ctx = canvas.getContext('2d', { alpha: false });
      this.photos = photos;
      this.settings = settings;
      this.hires = new Map();      // photo index -> { promise, level }
      this.pinned = new Set();
      this.recent = [];
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
      this.W = Math.round(window.innerWidth * dpr);
      this.H = Math.round(window.innerHeight * dpr);
      this.canvas.width = this.W;
      this.canvas.height = this.H;
      this.aspect = this.W / this.H;
      for (const p of this.photos) {
        for (const l of p.levels) l.crop = PM.cover(l.w, l.h, this.aspect);
        const [aw, ah] = PM.dims(p.analysis);
        p.feat = PM.gridFeatures(p.analysis, PM.cover(aw, ah, this.aspect), 1, 8);
      }
    }

    async start(first) {
      const a = first == null ? (Math.random() * this.photos.length) | 0 : first;
      await this.ensureHires(a).catch(() => {});
      this.startCycle(a);
      if (!this.running) {
        this.running = true;
        this.last = performance.now();
        requestAnimationFrame(this._frame);
      }
    }

    stop() { this.running = false; }

    // Rebuild the current cycle (after a resize or a grid-size change).
    restart() { if (this.cycle) this.startCycle(this.cycle.a); }

    next() { if (this.cycle) this.startCycle(this.cycle.b); }

    /* ---------- hi-res images, loaded on demand ---------- */

    ensureHires(i) {
      const hit = this.hires.get(i);
      if (hit) {
        this.hires.delete(i);
        this.hires.set(i, hit);
        return hit.promise;
      }
      const p = this.photos[i];
      const entry = { level: null };
      entry.promise = p.loadHires(this.W, this.H).then(({ src, tainted }) => {
        const [w, h] = PM.dims(src);
        entry.level = { src, w, h, crop: PM.cover(w, h, this.aspect), tainted, hires: true };
        if (this.hires.get(i) === entry) {
          p.levels = p.levels.filter(l => !l.hires).concat(entry.level);
        } else if (src.close) {
          src.close();
        }
      });
      this.hires.set(i, entry);
      this._evict();
      return entry.promise;
    }

    _evict() {
      for (const [i, entry] of this.hires) {
        if (this.hires.size <= HIRES_CACHE) break;
        if (this.pinned.has(i)) continue;
        this.hires.delete(i);
        const p = this.photos[i];
        p.levels = p.levels.filter(l => !l.hires);
        if (entry.level && entry.level.src.close) entry.level.src.close();
      }
    }

    /* ---------- cycles ---------- */

    startCycle(a) {
      const { photos, W, H } = this;
      const N = this.settings.grid;
      const A = photos[a];

      // Analyse A from the sharpest version we're allowed to read pixels from.
      const readable = A.levels.filter(l => l.hires && !l.tainted).pop();
      let cells;
      if (readable) {
        cells = PM.gridFeatures(readable.src, readable.crop, N, 2);
      } else {
        const [aw, ah] = PM.dims(A.analysis);
        cells = PM.gridFeatures(A.analysis, PM.cover(aw, ah, this.aspect), N, 2);
      }

      let pool = photos.map((_, i) => i);
      if (pool.length > 1) pool = pool.filter(i => i !== a);
      const assign = PM.buildMosaic(cells, N, pool, photos.map(p => p.feat), {
        spacing: this.settings.spacing,
        penalty: 60,
      });

      // Zoom into a cell near the middle whose photo hasn't been shown lately.
      this.recent.push(a);
      const keep = Math.min(RECENT, Math.floor(photos.length / 2));
      while (this.recent.length > keep) this.recent.shift();
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
      const col = cell % N, row = (cell / N) | 0;
      const b = assign[cell];

      this.cycle = { a, b, N, assign, cell, tx: (col * W) / N, ty: (row * H) / N };
      this.elapsed = 0;

      // Hi-res for B (fills the screen at the end) and the tiles around it.
      this.pinned = new Set([a, b]);
      const near = [];
      for (let r = row - 1; r <= row + 1; r++) {
        for (let c = col - 1; c <= col + 1; c++) {
          if (r >= 0 && c >= 0 && r < N && c < N) near.push(assign[r * N + c]);
        }
      }
      near.forEach(i => this.pinned.add(i));
      this.ensureHires(b).catch(e => console.warn(e));
      near.forEach(i => this.ensureHires(i).catch(e => console.warn(e)));
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
        if (u >= 1) this.startCycle(this.cycle.b);
        else p = easeInOut(u);
      }
      this.draw(p);
      requestAnimationFrame(this._frame);
    }

    draw(p) {
      const { ctx, W, H, photos } = this;
      const { N, assign, tx, ty, a } = this.cycle;
      const s = Math.pow(N, p);
      const fx = (N * tx) / (N - 1), fy = (N * ty) / (N - 1);
      const X = wx => fx + s * (wx - fx);
      const Y = wy => fy + s * (wy - fy);
      const alpha = overlayAlpha(p, this.settings.tint);

      // World-space rectangle currently on screen.
      const wx0 = fx - fx / s, wx1 = fx + (W - fx) / s;
      const wy0 = fy - fy / s, wy1 = fy + (H - fy) / s;

      ctx.fillStyle = '#000';
      ctx.fillRect(0, 0, W, H);
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'medium';

      if (alpha < 1) {
        const cw = W / N, ch = H / N;
        const c0 = Math.max(0, Math.floor(wx0 / cw)), c1 = Math.min(N - 1, Math.ceil(wx1 / cw) - 1);
        const r0 = Math.max(0, Math.floor(wy0 / ch)), r1 = Math.min(N - 1, Math.ceil(wy1 / ch) - 1);
        for (let r = r0; r <= r1; r++) {
          // Snap tile edges to whole pixels so neighbours share edges (no hairline seams).
          const y0 = Math.round(Y(r * ch)), y1 = Math.round(Y((r + 1) * ch));
          for (let c = c0; c <= c1; c++) {
            const x0 = Math.round(X(c * cw)), x1 = Math.round(X((c + 1) * cw));
            const tw = x1 - x0;
            const levels = photos[assign[r * N + c]].levels;
            let l = levels[levels.length - 1];
            for (const cand of levels) if (cand.crop[2] >= tw * 0.85) { l = cand; break; }
            const k = l.crop;
            ctx.drawImage(l.src, k[0], k[1], k[2], k[3], x0, y0, tw, y1 - y0);
          }
        }
      }

      if (alpha > 0) {
        // Photo A over its mosaic: fully at the start, then as a faint colour cheat.
        const levels = photos[a].levels;
        const l = levels[levels.length - 1];
        const [sx, sy, sw, sh] = l.crop;
        const vx0 = Math.max(0, wx0), vx1 = Math.min(W, wx1);
        const vy0 = Math.max(0, wy0), vy1 = Math.min(H, wy1);
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
