/*
 * Page wiring: intro screen, photo loading, settings panel, keyboard shortcuts.
 *
 * URL parameters (handy for screen-saver use):
 *   ?grid=60&duration=22&hold=3&tint=0.2&spacing=3   override settings
 *   ?direction=in|out|alternate                     zoom direction
 *   ?demo=1      start straight away with demo scenes
 *   ?saver=1     never show the intro; use the built library, else the demo
 *   ?lib=NAME    use the library built into folder NAME (default: library)
 */
(function (PM) {
  'use strict';

  PM.VERSION = '0.5.1'; // keep in sync with VERSION and the ?v= on index.html's script tags

  const DEFAULTS = { direction: 'in', grid: 100, duration: 22, hold: 3, tint: 0.2, spacing: 3 };
  const DIRECTIONS = ['in', 'out', 'alternate'];
  const RANGES = {
    grid: [20, 200, 10],
    duration: [6, 90, 1],
    hold: [0, 15, 0.5],
    tint: [0, 0.6, 0.05],
    spacing: [0, 8, 1],
  };
  const STORE_KEY = 'photomosaic.settings';
  const params = new URLSearchParams(location.search);

  const settings = { ...DEFAULTS };
  try { Object.assign(settings, JSON.parse(localStorage.getItem(STORE_KEY) || '{}')); } catch (e) { /* storage blocked */ }
  for (const k of Object.keys(DEFAULTS)) {
    if (params.has(k) && !isNaN(+params.get(k))) settings[k] = +params.get(k);
  }
  for (const k of Object.keys(RANGES)) {
    const [lo, hi] = RANGES[k];
    settings[k] = Math.min(hi, Math.max(lo, +settings[k] || DEFAULTS[k]));
  }
  if (params.has('direction')) settings.direction = params.get('direction');
  if (!DIRECTIONS.includes(settings.direction)) settings.direction = DEFAULTS.direction;
  const save = () => { try { localStorage.setItem(STORE_KEY, JSON.stringify(settings)); } catch (e) { /* ignore */ } };

  const $ = sel => document.querySelector(sel);
  const canvas = $('#stage');
  const intro = $('#intro');
  const progress = $('#progress');
  const panel = $('#panel');
  const hud = $('#hud');
  let player = null;

  $('#version').textContent = 'v' + PM.VERSION;

  /* ---------- loading ---------- */

  function setProgress(text) {
    progress.hidden = !text;
    progress.textContent = text || '';
  }

  async function begin(loader, label) {
    document.querySelectorAll('#intro button').forEach(b => (b.disabled = true));
    setProgress(label + '…');
    try {
      const photos = await loader((done, total) => setProgress(`${label}… ${done} / ${total}`));
      if (photos.length < 2) throw new Error('Need at least 2 photos — found ' + photos.length + '.');
      setProgress('Building first mosaic…');
      await new Promise(r => setTimeout(r, 30));
      if (player) player.stop();
      player = PM.player = new PM.Player(canvas, photos, settings);
      await player.start();
      intro.hidden = true;
      setProgress('');
      if (photos.length < 150) toast(`Only ${photos.length} photos — mosaics look much better with a few hundred.`);
      wake();
    } catch (e) {
      console.error(e);
      setProgress('⚠︎ ' + e.message);
    } finally {
      document.querySelectorAll('#intro button').forEach(b => (b.disabled = false));
    }
  }

  const useFiles = files => begin(cb => PM.Library.fromFiles(files, cb), `Reading ${files.length} files`);
  const useDemo = () => begin(cb => PM.Library.demo(360, cb), 'Painting demo scenes');
  const useManifest = () => begin(cb => PM.Library.fromManifest(window.PHOTO_MANIFEST, cb), 'Loading library');

  $('#pick-folder').onclick = () => $('#folder-input').click();
  $('#pick-files').onclick = () => $('#files-input').click();
  $('#folder-input').onchange = e => e.target.files.length && useFiles([...e.target.files]);
  $('#files-input').onchange = e => e.target.files.length && useFiles([...e.target.files]);
  $('#use-demo').onclick = useDemo;

  // Load <lib>/manifest.js as a script (works from file://, unlike fetch). A missing
  // file just means no built library.
  function loadManifest(lib) {
    return new Promise(resolve => {
      const el = document.createElement('script');
      el.src = lib + '/manifest.js';
      el.onload = el.onerror = () => resolve(window.PHOTO_MANIFEST && Array.isArray(window.PHOTO_MANIFEST.photos));
      document.head.appendChild(el);
    });
  }
  const lib = /^[\w-]+(\/[\w-]+)*$/.test(params.get('lib') || '') ? params.get('lib') : 'library';

  // Drag & drop of files and folders.
  async function walk(entry, out) {
    if (entry.isFile) {
      await new Promise(res => entry.file(f => { if (PM.Library.isImageFile(f)) out.push(f); res(); }, res));
    } else if (entry.isDirectory) {
      const reader = entry.createReader();
      for (;;) {
        const batch = await new Promise(res => reader.readEntries(res, () => res([])));
        if (!batch.length) break;
        for (const e of batch) await walk(e, out);
      }
    }
  }
  window.addEventListener('dragover', e => { e.preventDefault(); intro.classList.add('drop'); });
  window.addEventListener('dragleave', e => { if (!e.relatedTarget) intro.classList.remove('drop'); });
  window.addEventListener('drop', async e => {
    e.preventDefault();
    intro.classList.remove('drop');
    const entries = [...e.dataTransfer.items].map(i => i.webkitGetAsEntry && i.webkitGetAsEntry()).filter(Boolean);
    const files = [];
    if (entries.length) for (const en of entries) await walk(en, files);
    else files.push(...[...e.dataTransfer.files].filter(PM.Library.isImageFile));
    if (files.length) { intro.hidden = false; useFiles(files); }
  });

  /* ---------- settings panel ---------- */

  const fmt = {
    grid: v => `${v} × ${v}`,
    duration: v => `${v} s`,
    hold: v => `${v} s`,
    tint: v => `${Math.round(v * 100)}%`,
    spacing: v => (v ? `${v} cells` : 'off'),
  };
  for (const k of Object.keys(RANGES)) {
    const input = $(`#set-${k}`), out = $(`#val-${k}`);
    const [lo, hi, step] = RANGES[k];
    Object.assign(input, { min: lo, max: hi, step, value: settings[k] });
    out.textContent = fmt[k](settings[k]);
    input.oninput = () => { settings[k] = +input.value; out.textContent = fmt[k](settings[k]); save(); };
    if (k === 'grid' || k === 'spacing') input.onchange = () => player && player.restart();
  }
  // Direction applies from the next photo, so the current zoom isn't interrupted.
  const dirSelect = $('#set-direction');
  dirSelect.value = settings.direction;
  dirSelect.onchange = () => { settings.direction = dirSelect.value; save(); };

  $('#reset').onclick = () => {
    Object.assign(settings, DEFAULTS);
    dirSelect.value = settings.direction;
    for (const k of Object.keys(RANGES)) { $(`#set-${k}`).value = settings[k]; $(`#val-${k}`).textContent = fmt[k](settings[k]); }
    save();
    if (player) player.restart();
  };

  const togglePanel = force => { panel.hidden = force == null ? !panel.hidden : !force; };
  $('#btn-settings').onclick = () => togglePanel();
  $('#btn-next').onclick = () => player && player.next();
  $('#btn-pause').onclick = () => togglePause();
  $('#btn-full').onclick = () => toggleFullscreen();
  $('#btn-load').onclick = () => { togglePanel(false); intro.hidden = false; };

  function togglePause() {
    if (!player) return;
    player.paused = !player.paused;
    $('#btn-pause').textContent = player.paused ? '▶︎' : '❚❚';
    toast(player.paused ? 'Paused' : 'Playing');
  }

  function toggleFullscreen() {
    const el = document.documentElement;
    if (document.fullscreenElement || document.webkitFullscreenElement) {
      (document.exitFullscreen || document.webkitExitFullscreen).call(document);
    } else {
      (el.requestFullscreen || el.webkitRequestFullscreen).call(el);
    }
  }

  window.addEventListener('keydown', e => {
    if (!player || !intro.hidden || ['INPUT', 'SELECT'].includes(e.target.tagName)) return;
    if (e.key === ' ') { e.preventDefault(); togglePause(); }
    else if (e.key === 'f' || e.key === 'F') toggleFullscreen();
    else if (e.key === 's' || e.key === 'S') togglePanel();
    else if (e.key === 'n' || e.key === 'ArrowRight') player.next();
    else if (e.key === 'Escape') togglePanel(false);
    wake();
  });

  /* ---------- auto-hiding controls ---------- */

  let idleTimer = 0;
  function wake() {
    document.body.classList.remove('idle');
    clearTimeout(idleTimer);
    idleTimer = setTimeout(() => { if (panel.hidden && intro.hidden) document.body.classList.add('idle'); }, 2500);
  }
  window.addEventListener('mousemove', wake);
  hud.addEventListener('mouseenter', wake);

  let toastTimer = 0;
  function toast(msg) {
    const t = $('#toast');
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('show'), 2600);
  }

  let resizeTimer = 0;
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { if (player) { player.resize(); player.restart(); } }, 250);
  });

  /* ---------- autostart ---------- */

  loadManifest(lib).then(manifestOk => {
    if (manifestOk) {
      const b = $('#use-library');
      b.hidden = false;
      b.textContent = `Use built library (${window.PHOTO_MANIFEST.photos.length} photos)`;
      b.onclick = useManifest;
    }
    if (params.get('demo') === '1') useDemo();
    else if (params.get('saver') === '1') manifestOk ? useManifest() : useDemo();
    else if (manifestOk) useManifest();
  });
})(window.PM);
