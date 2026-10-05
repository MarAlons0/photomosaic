# Backlog Format

How `BACKLOG.md` is structured across all projects. Copy this to any new app and follow it.
Keeps every backlog scannable and consistent so the Project Dashboard can render them uniformly.

---

## File

One `BACKLOG.md` at the repo root. It answers three things per item: **what**, **why**, and **how urgent**.
Deep design detail does **not** live here — see [Long design specs](#long-design-specs).

---

## Edited from the dashboard

The Project Dashboard can edit and commit this `BACKLOG.md` **straight to the repo's `main`**
via the GitHub Contents API (its in-app backlog editor). So:

- The remote `BACKLOG.md` may be **ahead of your local clone** — run `git pull` before editing
  the backlog locally, and before any release that touches it.
- A conflict only arises if the same file was changed both locally (uncommitted) and from the
  dashboard. (Same pattern as Looking4Nature's `photos.json`.)
- Dashboard commits use the message `Update BACKLOG.md via dashboard` and are **not** releases —
  no version bump needed.

---

## Header

```markdown
# <Project> — Backlog
_Last updated: YYYY-MM-DD_
```

---

## Status

Checkboxes only:

| Marker | Meaning |
|--------|---------|
| `- [ ]` | open |
| `- [x]` | done (move to **✅ Shipped**) |
| `🚧` prefix on the title | in progress |

Don't use strikethrough, `[-]`, or `### Done (date)` headings — they render inconsistently.

---

## Grouping: by priority

Top-level sections are always these three, in this order:

```markdown
## 🔴 High
## 🟡 Medium
## 🟢 Low / Nice to have
```

For a large backlog you may add feature-area `###` sub-headings **inside** a priority section
(e.g. `### Map` under `## 🟡 Medium`). Priority stays the primary axis.

---

## Item shape

```markdown
- [ ] **Short title** — one-line what + why. `[type]`
  - optional: one or two brief sub-bullets (acceptance criteria or a key note)
  - optional: see [docs/design-note.md](docs/design-note.md) for the full spec
```

- **Title** in bold, then an em-dash, then a single sentence.
- **Type tag** (optional, at the end): `` `[feature]` `` · `` `[bug]` `` · `` `[chore]` `` · `` `[security]` `` · `` `[idea]` ``
- Keep it to the title line plus at most a couple of sub-bullets. Anything longer is a design spec → move it out.

---

## ✅ Shipped

When an item ships, move it to a `## ✅ Shipped` section at the bottom and tag it with the
version it shipped in:

```markdown
## ✅ Shipped
- [x] **Marker clustering** — v0.5.5
- [x] **Changelog viewer** — v0.6.0
```

This closes the loop with `VERSION` / `CHANGELOG.md` (see `VERSIONING.md`): the changelog is the
prose record of what shipped; the Shipped list is the one-line index tying each item to its version.
Keep the section trimmed — once it's long, older entries can be dropped since the changelog has them.

---

## Long design specs

Schemas, library comparisons, trade-offs, and multi-paragraph implementation plans belong in a
design note, **not** the backlog:

- Put them in `docs/DESIGN.md`, or `docs/<feature>.md` for a big single feature.
- The backlog item keeps a one-line summary and links to the note.
- When the feature ships, fold the user-facing part into `README.md` and the changelog entry; the
  design note can stay as the historical rationale.

Rule of thumb: **README = what exists & how to use it. docs/ = how/why we're building it. BACKLOG = what's next.**

---

## Full template

```markdown
# Aurora Tracker — Backlog
_Last updated: 2026-06-09_

## 🔴 High
- [ ] **Push alerts** — notify when KP index crosses a user threshold. `[feature]`
- [ ] 🚧 **Offline map tiles** — cache tiles so the map works with no signal. `[feature]`

## 🟡 Medium
- [ ] **Year filter** — browse sightings by year; `dateTaken` already stored. `[feature]`
- [ ] **Fix marker drift** — markers shift 1px on zoom. `[bug]`

### Map  <!-- optional area sub-group -->
- [ ] **Cluster toggle** — group dense markers. See [docs/clustering.md](docs/clustering.md). `[feature]`

## 🟢 Low / Nice to have
- [ ] **Dark-mode toggle** — Bootstrap supports it natively. `[chore]`

## ✅ Shipped
- [x] **Heatmap overlay** — v0.4.0
- [x] **CSV export** — v0.3.0
```
