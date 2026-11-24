# Move the online Photomosaic to its own host

Target: **https://photomosaic.looking4nature.com/** (confirm the subdomain before starting).
Status: shipped in v0.11.3 (2026-11-24). DNS is on WordPress.com's nameservers, so the CNAME lives there.

## Why

Safari keeps one bookmark icon per host name. The online Photomosaic
(`maralons0.github.io/photomosaic/`) and 7 Fichas (`maralons0.github.io/domino-advisor/`)
share that host, so 7 Fichas' Favorites in Safari show Photomosaic's icon. Giving Photomosaic
its own host gives each app its own icon slot.

Photomosaic is the one to move because it saves almost nothing in the browser: only the slider
settings (localStorage key `photomosaic.settings`). It has no service worker and no manifest.
See `FAVICON.md`, section "GitHub Pages project sites".

## Current setup (already checked)

- GitHub Pages publishes from `main`, repo root, with `.nojekyll`.
- The icon files are at the repo root (`favicon.ico`, `favicon-16.png`, `favicon-32.png`,
  `apple-touch-icon.png`), so on the new host they're served at the site root, which is what
  Safari bookmarks need.
- `index.html` and `js/` use relative paths, with no hard-coded `/photomosaic/` or github.io links.
- The online URL appears in `README.md` line 10 ("Try it online"). `CHANGELOG.md` line 17
  mentions it too, but that's history, so leave it.
- `gh` isn't installed on this machine.

## Steps

1. **Confirm the subdomain** (default: `photomosaic.looking4nature.com`).
2. **DNS** (Mario does this; wait for confirmation):
   - CNAME record: name `photomosaic`, value `maralons0.github.io` (no path). Add it wherever
     looking4nature.com's DNS is managed: Netlify DNS if the domain uses Netlify's nameservers,
     otherwise the registrar. If it's Cloudflare, set the record to "DNS only".
   - Recommended: verify the domain for GitHub Pages (GitHub › Settings › Pages › Add a domain).
     It adds a TXT record and stops anyone else from claiming the subdomain.
   - Check: `dig +short photomosaic.looking4nature.com CNAME`
3. **Repo changes** (ask before pushing):
   - Add a `CNAME` file at the repo root containing only `photomosaic.looking4nature.com`.
   - Update the README "Try it online" link to `https://photomosaic.looking4nature.com/`.
   - PATCH release per `VERSIONING.md` (bump from the current version, e.g. 0.11.2 → 0.11.3):
     `VERSION`, a `CHANGELOG.md` entry, an annotated tag. The changelog notes that settings
     saved in the browser start fresh once, because it's a new site.
   - Push `main` on its own first, then the tag. Pushing both together has skipped the Pages
     build before.
4. **HTTPS:** once GitHub's DNS check passes and the certificate is issued (can take a while),
   Mario ticks "Enforce HTTPS" in Settings › Pages.
5. **Verify and report:**
   - `curl -sI https://photomosaic.looking4nature.com/` → 200
   - `curl -sI https://photomosaic.looking4nature.com/apple-touch-icon.png` → 200 `image/png`
   - `curl -sI https://photomosaic.looking4nature.com/favicon.ico` → 200
   - `curl -sI https://maralons0.github.io/photomosaic/` → 301 to the new host. If it still
     serves the page with 200, say so: the old URL could still claim the shared icon slot.
   - Open the new URL; check the folder picker and the demo scenes work.
6. **Safari (Mario):** quit Safari, clear the `maralons0.github.io` icon with `FAVICON.md`'s
   "One host" command, open 7 Fichas first so its icon takes the slot, then bookmark Photomosaic
   again at the new address.
7. **Optional:** set Photomosaic's `deployment_url` in project-dashboard's `projects_config.py`
   to the new URL (it's `""` today). Ask first — that's another repo.
