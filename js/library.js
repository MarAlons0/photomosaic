/*
 * Photo libraries. Every loader returns an array of "photo" objects:
 *
 *   {
 *     name,
 *     micro,     64 px canvas, always in memory: tile features, far-zoom drawing, fallback
 *     levels,    loaded versions [{src, w, h, crop, kind, tainted}], smallest first;
 *                starts as [micro] and is managed by the player's cache
 *     load: {    on-demand versions, each -> Promise<{src, tainted}>
 *       tiny(),        ~128 px
 *       mid(),         ~320 px
 *       hires(W, H),   big enough to fill a W x H screen
 *     }
 *   }
 *
 * Only `micro` is kept for every photo, so memory stays bounded however big the
 * library is. `tainted` marks images whose pixels the browser won't let us read
 * (file:// images other than data: URIs); those can be drawn but not analysed.
 *
 * Three sources:
 *   fromFiles     - photos picked or dropped in the browser (File objects)
 *   fromManifest  - a library built by tools/build_library.py (works from file://)
 *   demo          - procedurally painted scenes, for trying the effect without photos
 */
(function (PM) {
  'use strict';

  const MID = 320;    // long edge of the tile image
  const TINY = 128;   // long edge of the small tile image
  const MICRO = 64;   // long edge of the always-loaded version
  const MAX_PHOTOS = 10000;

  const IMAGE_RE = /\.(jpe?g|png|webp|heic|heif|avif|gif|bmp|tiff?)$/i;

  function canvasOf(w, h) {
    const c = document.createElement('canvas');
    c.width = Math.max(1, Math.round(w));
    c.height = Math.max(1, Math.round(h));
    return c;
  }

  // Downscale with repeated halving, which looks far better than one big drawImage step.
  function stepDown(src, w, h) {
    let [cw, ch] = PM.dims(src);
    let cur = src;
    while (cw / 2 >= w && ch / 2 >= h) {
      cw = Math.round(cw / 2); ch = Math.round(ch / 2);
      const c = canvasOf(cw, ch);
      const g = c.getContext('2d');
      g.imageSmoothingQuality = 'high';
      g.drawImage(cur, 0, 0, cw, ch);
      cur = c;
    }
    const out = canvasOf(w, h);
    const g = out.getContext('2d');
    g.imageSmoothingQuality = 'high';
    g.drawImage(cur, 0, 0, out.width, out.height);
    return out;
  }

  async function resize(src, w, h) {
    w = Math.max(1, Math.round(w)); h = Math.max(1, Math.round(h));
    try {
      const bmp = await createImageBitmap(src, { resizeWidth: w, resizeHeight: h, resizeQuality: 'high' });
      if (bmp.width === w && bmp.height === h) return bmp;
      bmp.close();
    } catch (e) { /* resize options unsupported: fall through */ }
    return stepDown(src, w, h);
  }

  function fitLong(src, longEdge) {
    const [w, h] = PM.dims(src);
    const s = Math.min(1, longEdge / Math.max(w, h));
    return [w * s, h * s];
  }

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

  async function decodeFile(file) {
    try {
      return await createImageBitmap(file, { imageOrientation: 'from-image' });
    } catch (e) {
      // e.g. HEIC in Safari decodes via <img> but not createImageBitmap.
      const url = URL.createObjectURL(file);
      try { return await loadImg(url); } finally { setTimeout(() => URL.revokeObjectURL(url), 0); }
    }
  }

  PM.release = src => { if (src && src.close) src.close(); };

  async function coverSize(src, W, H) {
    const [w, h] = PM.dims(src);
    const s = Math.max(W / w, H / h);
    return s >= 1 ? src : resize(src, w * s, h * s);
  }

  function toJpeg(src) {
    let c = src;
    if (!(src instanceof HTMLCanvasElement)) {
      const [w, h] = PM.dims(src);
      c = canvasOf(w, h);
      c.getContext('2d').drawImage(src, 0, 0);
    }
    return new Promise(resolve => c.toBlob(resolve, 'image/jpeg', 0.85));
  }

  // Run fn over items with limited concurrency, reporting progress.
  async function pool(items, limit, fn, onProgress) {
    let next = 0, done = 0;
    const worker = async () => {
      while (next < items.length) {
        const i = next++;
        try { await fn(items[i], i); } catch (e) { console.warn(e); }
        done++;
        if (onProgress && (done % 10 === 0 || done === items.length)) onProgress(done, items.length);
      }
    };
    await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  }

  async function microOf(src) {
    const [w, h] = fitLong(src, MICRO);
    return stepDown(src, w, h);
  }

  function makePhoto(name, micro, load) {
    const [w, h] = PM.dims(micro);
    return { name, micro, levels: [{ src: micro, w, h, crop: [0, 0, w, h], kind: 'micro', tainted: false }], load };
  }

  function sample(arr, max) {
    if (arr.length <= max) return arr;
    const a = arr.slice();
    for (let i = a.length - 1; i > 0; i--) {
      const j = (Math.random() * (i + 1)) | 0;
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a.slice(0, max);
  }

  const clean = src => ({ src, tainted: false });

  PM.Library = {
    isImageFile(f) { return /^image\//.test(f.type) || IMAGE_RE.test(f.name); },

    // Decodes each photo once, keeping a 64 px canvas plus a compressed 320 px JPEG.
    async fromFiles(fileList, onProgress) {
      const files = sample([...fileList].filter(PM.Library.isImageFile), MAX_PHOTOS);
      const photos = [];
      await pool(files, 4, async file => {
        const full = await decodeFile(file);
        const [w, h] = fitLong(full, MID);
        const mid = await resize(full, w, h);
        if (mid !== full) PM.release(full);
        const [micro, blob] = await Promise.all([microOf(mid), toJpeg(mid)]);
        PM.release(mid);
        photos.push(makePhoto(file.name, micro, {
          async tiny() {
            const bmp = await createImageBitmap(blob);
            const [tw, th] = fitLong(bmp, TINY);
            const t = await resize(bmp, tw, th);
            if (t !== bmp) PM.release(bmp);
            return clean(t);
          },
          async mid() { return clean(await createImageBitmap(blob)); },
          async hires(W, H) {
            const big = await decodeFile(file);
            const src = await coverSize(big, W, H);
            if (src !== big) PM.release(big);
            return clean(src);
          },
        }));
      }, onProgress);
      return photos;
    },

    async fromManifest(manifest, onProgress) {
      const base = manifest.base || 'library/';
      const fromDisk = location.protocol === 'file:';
      const photos = [];
      await pool(manifest.photos, 8, async e => {
        const micro = await microOf(await loadImg(e.t));  // data: URI, so safe to read pixels from
        photos.push(makePhoto(e.n, micro, {
          async tiny() { return clean(await loadImg(e.t)); },
          async mid() { return { src: await loadImg(base + e.m), tainted: fromDisk }; },
          async hires() {
            // An ImageBitmap keeps its decoded pixels; an <img> may be re-decoded on
            // first draw, which stalls the zoom for tens of ms at full size.
            const img = await loadImg(base + e.f);
            let src = img;
            try { src = await createImageBitmap(img); } catch (err) { /* keep the <img> */ }
            return { src, tainted: fromDisk };
          },
        }));
      }, onProgress);
      return photos;
    },

    // Scenes are vector-painted, so every size is rendered fresh on demand.
    async demo(count, onProgress) {
      const photos = [];
      const SW = 600, SH = 400;
      const render = (seed, w, h) => {
        const c = canvasOf(w, h);
        PM.drawScene(c.getContext('2d'), c.width, c.height, seed);
        return c;
      };
      for (let i = 0; i < count; i++) {
        const seed = i + 1;
        const at = long => render(seed, long, (long * SH) / SW);
        photos.push(makePhoto('Demo scene ' + seed, await microOf(at(MID)), {
          async tiny() { return clean(at(TINY)); },
          async mid() { return clean(at(MID)); },
          async hires(W, H) {
            const s = Math.max(W / SW, H / SH);
            return clean(render(seed, SW * s, SH * s));
          },
        }));
        if (i % 20 === 19) { onProgress(i + 1, count); await new Promise(r => setTimeout(r)); }
      }
      return photos;
    },
  };

  /* ---------- Procedural demo scenes (nature-ish, deterministic per seed) ---------- */

  function rng(seed) {
    let a = seed * 9973 + 7;
    return () => {
      a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  const hsl = (h, s, l, a = 1) => `hsla(${((h % 360) + 360) % 360},${s}%,${l}%,${a})`;

  function vgrad(g, y0, y1, stops) {
    const gr = g.createLinearGradient(0, y0, 0, y1);
    stops.forEach((c, i) => gr.addColorStop(i / (stops.length - 1), c));
    return gr;
  }

  function glow(g, x, y, r, color, alpha = 1) {
    const gr = g.createRadialGradient(x, y, 0, x, y, r);
    gr.addColorStop(0, color);
    gr.addColorStop(1, 'rgba(0,0,0,0)');
    g.globalAlpha = alpha;
    g.fillStyle = gr;
    g.fillRect(x - r, y - r, r * 2, r * 2);
    g.globalAlpha = 1;
  }

  function ridge(g, R, base, rough, color) {
    g.fillStyle = color;
    g.beginPath();
    g.moveTo(0, 400);
    let y = base + (R() - 0.5) * rough;
    for (let x = 0; x <= 600; x += 15) {
      y += (R() - 0.5) * rough * 0.45;
      y = Math.min(Math.max(y, base - rough), base + rough);
      g.lineTo(x, y);
    }
    g.lineTo(600, 400);
    g.fill();
  }

  // Paint scene `seed` into a w x h context (designed on a 600x400 canvas).
  PM.drawScene = function (g, w, h, seed) {
    const R = rng(seed);
    const kind = Math.floor(R() * 9);
    const hue = R() * 360;
    g.save();
    g.scale(w / 600, h / 400);

    if (kind === 0) { // mountains under a coloured sky
      g.fillStyle = vgrad(g, 0, 300, [hsl(hue, 55, 22), hsl(hue + 25, 65, 55), hsl(hue + 50, 75, 80)]);
      g.fillRect(0, 0, 600, 400);
      glow(g, 80 + R() * 440, 60 + R() * 140, 70, hsl(hue + 60, 100, 92), 0.9);
      const layers = 3 + Math.floor(R() * 2);
      for (let i = 0; i < layers; i++) {
        ridge(g, R, 170 + i * 55, 90 - i * 15, hsl(hue + 180 + i * 10, 25 + i * 5, 55 - i * 13));
      }
    } else if (kind === 1) { // sunset over the sea
      const warm = R() < 0.7 ? R() * 50 : 180 + R() * 120;
      g.fillStyle = vgrad(g, 0, 240, [hsl(warm + 250, 50, 25), hsl(warm + 10, 80, 55), hsl(warm + 40, 95, 75)]);
      g.fillRect(0, 0, 600, 240);
      g.fillStyle = vgrad(g, 240, 400, [hsl(warm + 20, 60, 45), hsl(warm + 230, 45, 15)]);
      g.fillRect(0, 240, 600, 160);
      const sx = 120 + R() * 360;
      glow(g, sx, 235, 120, hsl(warm + 45, 100, 85), 0.8);
      g.fillStyle = hsl(warm + 45, 100, 88);
      g.beginPath(); g.arc(sx, 240, 28 + R() * 20, Math.PI, 0); g.fill();
      for (let y = 248; y < 400; y += 9) {
        const wd = 60 * (1 - (y - 240) / 220) + 10;
        g.fillStyle = hsl(warm + 40, 90, 75, 0.5);
        g.fillRect(sx - wd / 2 + (R() - 0.5) * 20, y, wd, 2);
      }
    } else if (kind === 2) { // flower macro with bokeh
      g.fillStyle = vgrad(g, 0, 400, [hsl(hue + 120, 40, 25), hsl(hue + 100, 45, 12)]);
      g.fillRect(0, 0, 600, 400);
      for (let i = 0; i < 18; i++) glow(g, R() * 600, R() * 400, 20 + R() * 60, hsl(hue + 90 + R() * 60, 60, 60), 0.5);
      const cx = 200 + R() * 200, cy = 140 + R() * 120, n = 5 + Math.floor(R() * 9), len = 90 + R() * 60;
      const ph = hue + R() * 40;
      for (let i = 0; i < n; i++) {
        g.save();
        g.translate(cx, cy);
        g.rotate((i / n) * Math.PI * 2 + R() * 0.2);
        g.fillStyle = vgrad(g, 0, len, [hsl(ph, 80, 75), hsl(ph + 15, 85, 50)]);
        g.beginPath(); g.ellipse(0, len / 2, len / 4.5, len / 2, 0, 0, Math.PI * 2); g.fill();
        g.restore();
      }
      g.fillStyle = hsl(45 + R() * 20, 90, 45);
      g.beginPath(); g.arc(cx, cy, len / 4.5, 0, Math.PI * 2); g.fill();
    } else if (kind === 3) { // forest
      const season = [120, 100, 35, 160][Math.floor(R() * 4)];
      g.fillStyle = vgrad(g, 0, 250, [hsl(205, 60, 55), hsl(195, 55, 82)]);
      g.fillRect(0, 0, 600, 400);
      ridge(g, R, 230, 40, hsl(season + 20, 20, 60));
      for (let row = 0; row < 4; row++) {
        const y = 230 + row * 45, size = 50 + row * 30;
        for (let i = 0; i < 16 - row * 3; i++) {
          const x = R() * 640 - 20;
          g.fillStyle = hsl(season + R() * 30 - 15, 45 + R() * 20, 38 - row * 7 + R() * 10);
          g.beginPath(); g.moveTo(x, y - size); g.lineTo(x - size / 3, y + 20); g.lineTo(x + size / 3, y + 20); g.fill();
        }
      }
    } else if (kind === 4) { // aurora night
      g.fillStyle = vgrad(g, 0, 400, [hsl(230, 50, 6), hsl(220, 45, 18)]);
      g.fillRect(0, 0, 600, 400);
      g.fillStyle = 'rgba(255,255,255,0.8)';
      for (let i = 0; i < 120; i++) g.fillRect(R() * 600, R() * 300, 1.4, 1.4);
      const ah = [140, 120, 290, 170][Math.floor(R() * 4)];
      for (let b = 0; b < 3; b++) {
        g.strokeStyle = hsl(ah + b * 20, 90, 60, 0.35);
        g.lineWidth = 30 + R() * 40;
        g.beginPath();
        const y0 = 80 + R() * 120;
        g.moveTo(-20, y0);
        g.bezierCurveTo(150, y0 - 80 + R() * 160, 400, y0 - 80 + R() * 160, 620, y0 + (R() - 0.5) * 100);
        g.stroke();
      }
      ridge(g, R, 330, 40, hsl(220, 30, 5));
    } else if (kind === 6) { // out-of-focus bokeh, any colour
      const l = 15 + R() * 55;
      g.fillStyle = vgrad(g, 0, 400, [hsl(hue, 50, l + 10), hsl(hue + 40, 55, l)]);
      g.fillRect(0, 0, 600, 400);
      for (let i = 0; i < 26; i++) glow(g, R() * 600, R() * 400, 25 + R() * 90, hsl(hue + R() * 80 - 40, 70, 50 + R() * 40), 0.55);
    } else if (kind === 7) { // lone tree on a hill
      g.fillStyle = vgrad(g, 0, 400, [hsl(hue, 45, 70), hsl(hue + 30, 50, 88)]);
      g.fillRect(0, 0, 600, 400);
      const gh = R() * 140;
      g.fillStyle = hsl(80 + R() * 60, 40, 35);
      g.beginPath(); g.ellipse(300, 470, 420, 160, 0, 0, Math.PI * 2); g.fill();
      const tx = 180 + R() * 240;
      g.fillStyle = hsl(25, 30, 18);
      g.fillRect(tx - 9, 150, 18, 170);
      for (let i = 0; i < 9; i++) {
        g.fillStyle = hsl(gh + R() * 40, 50, 25 + R() * 25);
        g.beginPath(); g.arc(tx + (R() - 0.5) * 150, 140 + (R() - 0.5) * 100, 45 + R() * 30, 0, Math.PI * 2); g.fill();
      }
    } else if (kind === 8) { // mountain lake with reflection
      const sky = vgrad(g, 0, 220, [hsl(hue, 50, 35), hsl(hue + 20, 60, 75)]);
      g.fillStyle = sky; g.fillRect(0, 0, 600, 220);
      g.save(); g.beginPath(); g.rect(0, 0, 600, 220); g.clip();
      ridge(g, R, 150, 70, hsl(hue + 160, 25, 30));
      g.restore();
      // Mirror the top half into the water (canvas drawn onto itself, in device px).
      const cv = g.canvas, k = cv.height / 400;
      g.save();
      g.setTransform(1, 0, 0, -1, 0, 440 * k);
      g.drawImage(cv, 0, 0, cv.width, 220 * k, 0, 0, cv.width, 220 * k);
      g.restore();
      g.fillStyle = hsl(hue + 200, 40, 20, 0.35);
      g.fillRect(0, 220, 600, 180);
    } else { // dunes / desert
      const dh = 20 + R() * 25;
      g.fillStyle = vgrad(g, 0, 200, [hsl(200 + R() * 20, 70, 50), hsl(195, 60, 80)]);
      g.fillRect(0, 0, 600, 400);
      for (let i = 0; i < 5; i++) {
        const base = 170 + i * 50, amp = 20 + R() * 25, phs = R() * 6, fr = 0.008 + R() * 0.01;
        g.fillStyle = hsl(dh + i * 3, 65 - i * 4, 62 - i * 8);
        g.beginPath(); g.moveTo(0, 400);
        for (let x = 0; x <= 600; x += 10) g.lineTo(x, base + Math.sin(x * fr + phs) * amp);
        g.lineTo(600, 400); g.fill();
      }
    }
    g.restore();
  };
})(window.PM);
