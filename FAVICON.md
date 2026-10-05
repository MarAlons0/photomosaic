# Favicon Standard

How favicons are set up across all projects. Copy this to any new app and follow it.

---

## The core problem (read this first)

Browsers fetch icons in **two independent ways**, and they don't behave the same:

1. **Browser tab** — uses the `<link rel="icon">` tags in your `<head>`.
2. **Bookmarks / Favorites (especially Safari)** — largely **ignores** your `<link>` tags
   and instead requests `/favicon.ico` and `/apple-touch-icon.png` from the **site root**.

If the root paths return 404, the bookmark shows a generic letter placeholder even though
the tab icon looks fine. **This is the #1 cause of "favicon works in the tab but not the bookmark."**

So every app must satisfy **both**: correct `<link>` tags **and** real files served at the site root.

---

## Required files

Generate these from a single square source image (≥512px ideally) and place them in the
static/public folder:

| File | Size | Purpose |
|------|------|---------|
| `favicon.ico` | multi-res 16/32/48 | Tab icon, legacy, root request |
| `favicon-16.png` | 16×16 | Tab icon (small) |
| `favicon-32.png` | 32×32 | Tab icon (retina) |
| `apple-touch-icon.png` | 180×180 | Safari/iOS bookmarks & Favorites |

**Pitfall — oversized source:** Do not point the tab `<link rel="icon">` at a huge PNG
(e.g. 1024×1024). Safari often silently fails to render an oversized image as a tab favicon.
Use the 16/32 PNGs.

**Pitfall — illegible detail:** A detailed illustration (intricate logo, busy scene) that
looks great at 180px collapses into an indistinct blob — often a vague "O" — at 16/32px.
The bookmark (apple-touch, 180px) can keep the full art, but the **tab icons should be a
simplified, high-contrast mark**: crop to the single most recognizable element and boost
contrast before downscaling. Two different images for two different jobs is fine and normal.

### Generating the kit

Use Pillow (any project venv that has it works):

```python
from PIL import Image
img = Image.open("source.png").convert("RGBA")
# square the canvas if needed, then:
img.resize((16,16)).save("favicon-16.png")
img.resize((32,32)).save("favicon-32.png")
img.resize((180,180)).save("apple-touch-icon.png")
img.save("favicon.ico", sizes=[(16,16),(32,32),(48,48)])
```

---

## The `<link>` block (put in your base template `<head>`)

```html
<link rel="icon" type="image/png" sizes="32x32" href="/static/favicon-32.png?v=1">
<link rel="icon" type="image/png" sizes="16x16" href="/static/favicon-16.png?v=1">
<link rel="icon" href="/static/favicon.ico?v=1" sizes="any">
<link rel="apple-touch-icon" sizes="180x180" href="/static/apple-touch-icon.png?v=1">
```

(Use `url_for('static', ...)` in Flask/Jinja; plain root paths in static sites.)

**Two rules that matter for refreshes:**
1. **List the PNG icons *before* the `.ico`.** Browsers often pick the first usable
   icon; putting the crisp versioned PNGs first makes them win over a hard-cached `.ico`.
2. **Add a `?v=N` cache-buster to every icon URL and bump `N` whenever you change an icon.**
   Without it, Safari clings to the old image. Note Safari *also* auto-requests the bare
   `/favicon.ico` (no query) for tabs — that copy is cached hard, so a stale tab icon may
   still need a hard reload (Cmd+Shift+R) even after a `?v` bump.

(Use `url_for('static', ...)` in Flask/Jinja; plain root paths in static sites.)

---

## Serving icons at the site root (the part people forget)

### Flask
Add explicit root routes — `<link>` tags alone are **not** enough for Safari bookmarks:

```python
from flask import send_from_directory

@app.route('/favicon.ico')
def favicon():
    return send_from_directory(app.static_folder, 'favicon.ico', mimetype='image/x-icon')

@app.route('/apple-touch-icon.png')
@app.route('/apple-touch-icon-precomposed.png')
def apple_touch_icon():
    return send_from_directory(app.static_folder, 'apple-touch-icon.png', mimetype='image/png')
```

### Astro / Netlify / static sites
Place `favicon.ico`, `favicon-16.png`, `favicon-32.png`, and `apple-touch-icon.png` in the
`public/` folder. Astro copies `public/` to the site root on build, so they resolve at
`/favicon.ico` etc. automatically.

### GitHub Pages **project** sites (`user.github.io/repo/`)
Root requests resolve to `user.github.io/favicon.ico`, which belongs to a *different* repo,
so root serving is unreliable. Rely on the `<link>` tags with paths relative to the project
subpath. (Acceptable — tab icons work; bookmark icons are best-effort here.)

---

## Verifying

Check that the root paths actually return `200` with the right content type:

```python
import urllib.request
for p in ["/favicon.ico", "/apple-touch-icon.png"]:
    r = urllib.request.urlopen("https://yourapp.example.com" + p)
    print(p, r.status, r.headers.get("Content-Type"))
```

Or with a Flask test client locally:

```python
c = create_app().test_client()
print(c.get("/favicon.ico").status_code)        # expect 200 image/x-icon
print(c.get("/apple-touch-icon.png").status_code)  # expect 200 image/png
```

---

## Safari caches aggressively — clearing stuck icons

Safari caches bookmark icons **including failures**. After fixing the server, existing
bookmarks will still look broken until you reset the cache. Either:

- **Per bookmark:** delete it and re-add — Safari only fetches the icon on first save.
- **Fleet-wide:** quit Safari, then:
  ```bash
  rm -rf ~/Library/Safari/Touch\ Icons\ Cache ~/Library/Safari/Favicon\ Cache
  ```
  Reopen Safari and revisit each site. Tab icons refresh with a hard reload (Cmd+Shift+R).

This is usually why a "fix" appears not to work — the server is correct, but Safari never re-fetched.
