/*
 * Photomosaic core: colour math, feature extraction and tile matching.
 *
 * Every image is described by a 12-number feature: the mean CIELAB colour of
 * its four quadrants (2x2 grid x L,a,b). Matching a mosaic cell to a photo is a
 * nearest-neighbour search over those features, with two anti-repetition rules:
 * a photo can't reappear within `spacing` cells of itself, and every reuse adds
 * a small penalty so the whole library gets a chance.
 */
window.PM = window.PM || {};

(function (PM) {
  'use strict';

  PM.FEAT = 12;

  // sRGB byte -> linear light, so averages are physically meaningful.
  const LIN = new Float32Array(256);
  for (let i = 0; i < 256; i++) {
    const c = i / 255;
    LIN[i] = c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  }
  const f = t => (t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116);

  function linToLab(R, G, B, out, o) {
    const X = (0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047;
    const Y = 0.2126 * R + 0.7152 * G + 0.0722 * B;
    const Z = (0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883;
    const fx = f(X), fy = f(Y), fz = f(Z);
    out[o] = 116 * fy - 16;
    out[o + 1] = 500 * (fx - fy);
    out[o + 2] = 200 * (fy - fz);
  }

  PM.dims = src => [src.naturalWidth || src.width, src.naturalHeight || src.height];

  // Centred "object-fit: cover" crop of a w x h image to the given aspect: [sx, sy, sw, sh].
  PM.cover = function (w, h, aspect) {
    if (w / h > aspect) {
      const sw = h * aspect;
      return [(w - sw) / 2, 0, sw, h];
    }
    const sh = w / aspect;
    return [0, (h - sh) / 2, w, sh];
  };

  let scratch = null, sctx = null;

  /*
   * Features for an n x n grid laid over `crop` of `src` (Float32Array of n*n*12).
   * Each quadrant is averaged over px*px samples. n = 1 describes a whole tile.
   * Throws if `src` is cross-origin tainted.
   */
  PM.gridFeatures = function (src, crop, n, px) {
    if (!scratch) {
      scratch = document.createElement('canvas');
      sctx = scratch.getContext('2d', { willReadFrequently: true });
    }
    const size = n * 2 * px;
    if (scratch.width !== size) { scratch.width = size; scratch.height = size; }
    sctx.imageSmoothingEnabled = true;
    sctx.imageSmoothingQuality = 'high';
    sctx.clearRect(0, 0, size, size);
    sctx.drawImage(src, crop[0], crop[1], crop[2], crop[3], 0, 0, size, size);
    const d = sctx.getImageData(0, 0, size, size).data;

    const out = new Float32Array(n * n * 12);
    const inv = 1 / (px * px);
    for (let cy = 0; cy < n; cy++) {
      for (let cx = 0; cx < n; cx++) {
        for (let q = 0; q < 4; q++) {
          const x0 = (cx * 2 + (q & 1)) * px;
          const y0 = (cy * 2 + (q >> 1)) * px;
          let R = 0, G = 0, B = 0;
          for (let y = y0; y < y0 + px; y++) {
            let i = (y * size + x0) * 4;
            for (let x = 0; x < px; x++, i += 4) {
              R += LIN[d[i]]; G += LIN[d[i + 1]]; B += LIN[d[i + 2]];
            }
          }
          linToLab(R * inv, G * inv, B * inv, out, (cy * n + cx) * 12 + q * 3);
        }
      }
    }
    return out;
  };

  /*
   * Assign a photo to every cell of an n x n mosaic.
   *   cells - Float32Array(n*n*12) target features
   *   pool  - photo indices allowed as tiles
   *   feats - per-photo 12-float features (indexed by photo index)
   *   opts  - { spacing: no-repeat radius in cells, penalty: cost per reuse }
   * Returns Int32Array(n*n) of photo indices, row-major.
   */
  PM.buildMosaic = function (cells, n, pool, feats, opts) {
    const total = n * n, P = pool.length;
    const spacing = opts.spacing | 0;
    const penalty = opts.penalty == null ? 30 : opts.penalty;

    const F = new Float32Array(P * 12);
    pool.forEach((pi, k) => F.set(feats[pi], k * 12));

    const local = new Int32Array(total).fill(-1);
    const uses = new Float32Array(P);
    const stamp = new Int32Array(P).fill(-1);

    // Fill cells in random order so no region systematically gets first pick.
    const order = new Int32Array(total);
    for (let i = 0; i < total; i++) order[i] = i;
    for (let i = total - 1; i > 0; i--) {
      const j = (Math.random() * (i + 1)) | 0;
      const t = order[i]; order[i] = order[j]; order[j] = t;
    }

    for (let it = 0; it < total; it++) {
      const cell = order[it];
      const cx = cell % n, cy = (cell / n) | 0;

      if (spacing > 0) {
        const y0 = Math.max(0, cy - spacing), y1 = Math.min(n - 1, cy + spacing);
        const x0 = Math.max(0, cx - spacing), x1 = Math.min(n - 1, cx + spacing);
        for (let y = y0; y <= y1; y++) {
          for (let x = x0; x <= x1; x++) {
            const a = local[y * n + x];
            if (a >= 0) stamp[a] = it;
          }
        }
      }

      const co = cell * 12;
      let best = -1, bd = Infinity;
      for (let k = 0; k < P; k++) {
        if (stamp[k] === it) continue;
        let d = uses[k] * penalty;
        if (d >= bd) continue;
        const ko = k * 12;
        for (let j = 0; j < 12; j++) {
          const e = cells[co + j] - F[ko + j];
          d += e * e;
        }
        if (d < bd) { bd = d; best = k; }
      }
      // Library smaller than the no-repeat neighbourhood: fall back to anything.
      if (best < 0) best = (Math.random() * P) | 0;
      local[cell] = best;
      uses[best]++;
    }

    const assign = new Int32Array(total);
    for (let i = 0; i < total; i++) assign[i] = pool[local[i]];
    return assign;
  };
})(window.PM);
