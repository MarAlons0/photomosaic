# Versioning Approach

This document describes the versioning system used in this project.
Copy it to any new app and adapt as needed.

---

## Scheme: Semantic Versioning (SemVer)

Versions follow `MAJOR.MINOR.PATCH`:

| Part | Increment when… | Example trigger |
|------|-----------------|-----------------|
| `MAJOR` | Architecture changes, breaking redesigns, multi-user overhaul | New auth system, database restructure, complete UI rewrite |
| `MINOR` | New user-facing features or meaningful capability additions | Weather forecast, date shift, new export format |
| `PATCH` | Bug fixes, small UX improvements, copy changes, performance tweaks | JSON truncation fix, favicon fix, help text update |

**Rule of thumb:**
- If a user would say *"the app can now do something it couldn't before"* → `MINOR`
- If a user would say *"that thing that was broken now works"* → `PATCH`
- If a user would say *"this is basically a different app"* → `MAJOR`

---

## Files

### `VERSION`
A single file at the project root containing only the version string, e.g.:
```
1.2.0
```
No `v` prefix in the file — that's added in display and git tags.

### `CHANGELOG.md`
Documents what changed in each release. Follow the
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format:

```markdown
## [1.2.0] – YYYY-MM-DD
### Added
- New feature description
### Fixed
- Bug description
### Changed
- Behaviour that changed but isn't a new feature or bug fix
```

Use `Added`, `Fixed`, `Changed`, `Removed`, `Security` as section headers.
Group entries by feature area for readability on larger releases.

---

## Flask Implementation

### 1. Read `VERSION` at startup (`app/__init__.py`)

```python
import os

def _read_version() -> str:
    version_file = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'VERSION')
    try:
        with open(version_file) as f:
            return f.read().strip()
    except FileNotFoundError:
        return '?.?.?'

def create_app(config_class=Config):
    app = Flask(__name__)
    # ...
    _version = _read_version()

    @app.context_processor
    def inject_globals():
        return {'app_version': _version}
    # ...
```

### 2. Display in the base template (`templates/base.html`)

```html
<a class="navbar-brand" href="{{ url_for('main.index') }}">
  AppName
  <span class="text-secondary fw-normal ms-2" style="font-size:.7rem">v{{ app_version }}</span>
</a>
```

Place it wherever suits the app's layout — navbar brand, footer, or help modal.

### 3. Implementation for other frameworks

| Framework | Equivalent pattern |
|-----------|-------------------|
| **Django** | Read `VERSION` in `settings.py`; expose via `django.template.context_processors` |
| **FastAPI** | Read at startup; add to Jinja2 `globals` or return in a `/version` endpoint |
| **Express (Node)** | Read `package.json` version field; pass to templates via `res.locals` |
| **Static sites** | Embed version in `_config.yml` / `config.js`; reference in layout template |

---

## Git Workflow

### Tagging a release

```bash
# 1. Update VERSION file
echo "1.1.0" > VERSION

# 2. Update CHANGELOG.md — add new section at the top

# 3. Commit both files
git add VERSION CHANGELOG.md
git commit -m "Release v1.1.0"

# 4. Create an annotated git tag
git tag -a v1.1.0 -m "v1.1.0 — Weather forecast, date shift, Smart Pack improvements"

# 5. Push commit and tag
git push origin main
git push origin v1.1.0
```

### Viewing releases

```bash
git tag -l              # list all tags
git show v1.1.0         # inspect a specific tag
git log v1.0.0..v1.1.0  # commits between two releases
```

---

## When to cut a release

There is no fixed cadence — release when a meaningful chunk of work is complete
and deployed. Avoid releasing mid-feature. Good triggers:

- A session's worth of features is live and tested in production
- A significant bug that affected real use has been fixed
- A natural milestone is reached (first production use, first real trip, etc.)

---

## Versioning in the BACKLOG / CHANGELOG relationship

- **BACKLOG.md** — what's planned and in progress; items marked ✅ Done when shipped
- **CHANGELOG.md** — the permanent record of what shipped and when
- **VERSION** — the current version, always matches the latest CHANGELOG entry

When closing out a session:
1. Move completed backlog items to CHANGELOG under a new version section
2. Bump VERSION
3. Commit + tag
