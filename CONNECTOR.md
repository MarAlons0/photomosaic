# Claude Connector Standard

How an app becomes a **Claude connector**: a remote MCP server that Claude can use from
claude.ai, Claude Code and **Claude Duet** (which carries over the account's connectors and can
run on a schedule). Copy this approach, and the code, rather than designing it again.

**Reference implementations**
- **TripPlanner** `app/connector/`: the full version, with a database. Stored hashed tokens,
  a Connected apps list with Disconnect, read and write tools, the 🤖 marker. Spec:
  `docs/DESIGN.md` → "Booking to-dos as a Claude connector".
- **project-dashboard** `connector/`: the same flow with **no database**. Client ids, codes
  and tokens are signed values (itsdangerous, one salt per kind). The trade-off is no
  per-connection Disconnect; changing `CONNECTOR_SECRET` disconnects everything. Its writes
  go to files in GitHub repos, not database rows; see **File-backed writes** below.

Signed values can't remember that something was used. Two checklist items need a small
store even in an app without a database: one-use authorization codes, and revoking a
connection when a spent refresh token is reused. A single table or key-value file holding
spent code and refresh-token ids (hashed, with expiry) is enough. Without it, mark both
items as not met and keep access tokens short.

Start from whichever matches the app: TripPlanner's if it has a database, the dashboard's if
not.

---

## Shape

A Flask blueprint package with three modules:

| File | What it holds |
|---|---|
| `oauth.py` | Discovery, client registration, the approval page, tokens, scopes |
| `mcp.py` | The `/mcp` endpoint and the `INSTRUCTIONS` text |
| `tools.py` | Tool definitions (`DEFINITIONS`), handlers (`HANDLERS`), `TOOL_SCOPES` |

- **Off unless configured.** If the app has no database, it needs a secret (e.g.
  `CONNECTOR_SECRET`); with the secret unset, the routes aren't registered.
- **Behind the app's own login.** The approval page needs the owner signed in. There is no
  separate account system.

## Protocol checklist

- [ ] `POST /mcp`: stateless Streamable HTTP, answered as JSON (no SSE stream). `GET` and
      `DELETE` on `/mcp` → 405.
- [ ] `initialize` negotiates the version from a supported list (TripPlanner:
      `2025-11-25`, `2025-06-18`, `2025-03-26`) and returns `instructions`.
- [ ] Notifications get `202`; unknown methods get JSON-RPC `-32601`; unknown tools get
      `-32602`.
- [ ] **Check `Origin`** (DNS rebinding): when the header is present, allow claude.ai,
      claude.com and loopback only. A request with **no** `Origin` (Claude's server-side
      calls, Claude Code) is allowed and still needs a valid token.
- [ ] A request without a token → `401` with `WWW-Authenticate` pointing at
      `/.well-known/oauth-protected-resource`.
- [ ] Discovery:
      - `/.well-known/oauth-protected-resource` (and `…/mcp`), RFC 9728, with
        `scopes_supported`.
      - `/.well-known/oauth-authorization-server`, RFC 8414.
- [ ] `POST /oauth/register` (RFC 7591 dynamic registration):
      - public clients only;
      - redirect URIs limited to Claude's callbacks
        (`https://claude.ai/api/mcp/auth_callback`, and `https://claude.com/api/mcp/auth_callback`
        if a real connection shows it in use) and loopback, plus any extras in a config
        variable. Log refused redirect URIs so a new Claude callback is easy to spot.
- [ ] `/oauth/authorize`:
      - PKCE `S256` is required;
      - an unregistered redirect is **shown, not followed**;
      - the approval page's CSP lets its callback through.
- [ ] `/oauth/token`:
      - each code works once and needs its verifier;
      - access tokens last 1 hour;
      - **refresh tokens rotate**, and reusing a spent one revokes the whole connection.
- [ ] Store **only hashes** of codes and tokens, or signed values when there's no database.
- [ ] Production URLs are `https` behind Render's proxy: build them from `X-Forwarded-Proto`, and test for it.

## Permissions: one scope per kind of change

- **Reads** are one or more scopes, always granted (TripPlanner: `todos`, `trips`,
  `packing`).
- **Each kind of change is its own scope and its own checkbox** on the approval page (e.g.
  `todos.write`, `todos.create`, `stays.write`, `plans.write`, `packing.write`). Group the
  checkboxes under one "Also let it:" heading, one line each. **Every checkbox starts
  unticked**, so pressing Allow without choosing gives a read-only connection.
- **Adding a capability means adding a new scope, never widening an old one.** An existing
  connection keeps exactly what was approved; the owner reconnects to get the new tools. Each
  new read area gets its own scope too, so an old token is refused with "approved before X —
  reconnect".
- A call refused for a missing scope says **which checkbox to tick**, using the label exactly
  as the approval page shows it (`ticks "Add booking to-dos" under "Also let it"`).
- **Connected apps** (in the app's profile or settings) lists each connection with a label
  built from its scopes, e.g. "reads, ticks off to-dos, adds to-dos & packs", plus a
  Disconnect button.
- The approval page states the limits plainly: *"It never deletes, re-dates or renames what
  you made … and never books or pays."* It also warns the owner to allow only a connector
  they just added themselves.

## Tool design

**Definitions**
- `name` in snake_case verb form (`list_…`, `get_…`, `record_…`, `add_…`, `create_…`), plus a
  human `title`.
- The `description` says what the tool returns *and when to use it* ("Use it to match a
  confirmation email to the stay it books").
- `inputSchema` uses `additionalProperties: false`, required fields listed, and a
  description on every property that isn't obvious.
- Annotations: reads are `readOnlyHint: true`. Nothing is ever `destructiveHint: true`,
  because there are no delete tools. Mark `idempotentHint` honestly; appending a note is not
  idempotent.

**Write tools: the guards**
- **Match the key facts before writing.** For example, a booking's dates must equal the
  stay's, and a flight may only go on a day that flies. On a mismatch, **refuse, change
  nothing, and say "tell the owner"**.
- **Set, don't toggle.** `check_items(packed=true)` called twice changes nothing.
- **No silent overwrites.** A different value already set is refused unless `replace: true`.
  The same value again is fine.
- **No duplicates.** Compare on a normalized key (case and whitespace folded). Refuse and
  return the existing id; for transport, the same confirmation twice is a no-op.
- **All-or-nothing.** A batch with one bad id changes nothing. A refused call rolls back.
- **Caps** on anything Claude creates (TripPlanner: 10 open to-dos per trip, 50 items per
  batch). Track Claude-created rows in a `created_by` column, because the marker is cleared by
  the owner's edit.
- **Require a `reason`** on anything Claude adds, and store it where the owner sees it
  ("Claude: …").
- **Shape checks:** one-line text within the column limits, references matching a pattern,
  amounts through the app's own parser, dates in ISO format.
- **Warn rather than refuse** when the record is real but something looks off, such as a
  booking whose party differs from the trip's. Record it, return `warnings`, and put
  ", party differs" in the marker.
- **Estimates are labelled.** A date Claude supplies counts as an estimate unless it quotes
  its source (`date_source`), which is then stored.
- **Never:** delete, re-date, rename, change structure (routes, how a day travels), book or
  pay.

**File-backed writes** (e.g. the dashboard adding to a repo's `BACKLOG.md` via the GitHub
API)
- **One commit per call**, with a message starting `🤖 Claude:` and the `reason`. A batch
  goes in that one commit, so all-or-nothing holds.
- **No clobbering.** Read the file and its blob `sha`, change only the lines being added,
  and send that `sha` with the update. A `409` means the file changed in the meantime:
  re-read once and retry; if it fails again, refuse and change nothing.
- **The marker lives in the line itself**, e.g. a trailing `🤖 2026-11-26` on the backlog
  item. The owner editing or removing it is the "clear". Caps count lines that carry it.
- **Duplicates** are checked against the file as just read, on the same normalized key.
- **Stay inside the format.** Insert only where the file's own standard (e.g.
  `BACKLOG_FORMAT.md`) says items go, and refuse if the file doesn't parse.

**Errors**
- Raise a tool error (`isError: true`) whose message is the next step: what was wrong, that
  nothing changed, and which tool or field fixes it ("list_trips gives the ids").

## The 🤖 marker

Every model Claude can change gets `claude_action` (text) and `claude_action_at` columns, with
`mark_claude(action)` and `clear_claude()`.
- Write the action in plain words ("recorded the booking (time, cost)", "added this").
- **Show it where the change appears** (the to-do, day card, budget line, packing item):
  `🤖 Claude <action> · <date>`.
- **The owner's own edit of that record clears it**, in every edit route.
- Reads return it as `last_claude_change`.

## Tokens: what a tool returns, the owner pays for

Every tool result goes into Claude's context and is re-read on each later turn of the
conversation, from the owner's Claude budget.
- **The list tool carries enough to pick the right record**, so Claude doesn't open every
  detail to find one. TripPlanner's `list_trips` gives each trip's `places`; a question
  about "Puerto Morelos" matches without reading an itinerary.
- **Detail tools take a range or a filter** (`from_date`/`to_date`, `status`, `category`) and
  default to the useful subset (packing: unpacked only).
- **Say nothing twice in one response.** Don't list an item in two arrays. Give a repeated
  block in full once, then refer back to it (`same_stay_as_day: 1`).
- **Leave out nulls and empty lists**, and say so in the description.
- **Leave out long URLs** unless the tool is about them.
- Serialize compactly (`json.dumps` with no indent).
- **Measure it.** Call the tool on real data, as the owner's connector does, and note the
  size in the spec. As a guide, a one-record answer should be well under 1,000 tokens.

## `INSTRUCTIONS`

One paragraph returned by `initialize`. It covers:
- what the app holds;
- which tool to start with;
- the domain rules Claude needs (e.g. "ticking records a booking, it doesn't make one");
- what to do on a mismatch (tell the owner, change nothing);
- what it must never do (book or pay; record only once booked).

Extend it with each phase.

## Tests (one file, e.g. `tests/test_connector.py`)

- **OAuth:**
  - discovery documents;
  - registration limits;
  - the approval page needs login;
  - PKCE is required;
  - deny → `access_denied`;
  - a code works once;
  - only hashes are stored;
  - refresh rotation, and reuse revokes (needs the spent-id store in an app without a
    database);
  - an expired token is refused;
  - Disconnect.
- **MCP:** version negotiation; 202 for notifications; foreign Origin refused, missing
  Origin allowed; the tool list in order with its annotations.
- **Approval page:** every write checkbox starts unticked.
- **File-backed writes:** a stale `sha` is retried once then refused with nothing changed;
  the commit message carries the marker and reason.
- **Scopes:**
  - each choice is its own scope;
  - a read-only connection can't change anything;
  - an older connection is told to reconnect;
  - refusal messages name the checkbox;
  - Connected apps labels.
- **For each write tool:**
  - the change, and its marker;
  - every refusal, with **nothing changed** asserted;
  - the warning cases;
  - the owner's edit in the app clearing the marker.
- **Reads match the app's own pages:** the same rules, from the same model properties.
- **Payload shape:** nothing listed twice, nulls left out, ranges respected.
- Helper signature: `call(client, token, tool, /, **args)`, positional-only so a tool
  argument called `name` can't clash.

## Shipping and connecting

- **Ship in phases**, each with a spec in `docs/DESIGN.md`: reads → simple writes → richer
  writes. Each phase's new writes get their own scope.
- **Check the deploy is live** by polling `/.well-known/oauth-protected-resource` until
  `scopes_supported` lists the new scope.
- **Connecting:**
  1. Claude → Settings → Connectors → **Add custom connector**.
  2. Paste **only the URL** (`https://<app>/mcp`). Extra text pasted with it gives a 404.
  3. Sign in, choose the checkboxes, and press Allow.
- **New scopes need a reconnect:** remove the connector and add it again. Say so in the
  CHANGELOG entry.
- **User Guide:** keep a "Claude & Duet outside the app" section covering:
  - connecting;
  - what Claude always sees, and each change it can be allowed to make;
  - the 🤖 marker;
  - what it never does;
  - example requests to Duet;
  - Duet's limits.
- **Test end to end in Duet:** one read, one write, one refusal. Duet's review of the spec
  is worth asking for; it caught real gaps in TripPlanner's phase 3.

## Duet: what to expect

- It uses whatever connectors the account has, so one connection serves claude.ai, Claude Code
  and Duet.
- **Scheduled runs can't sign in to a site or pay.** Design writes to record what the owner
  did, not to act for them.
- It combines connectors (e.g. email + the app): "when a confirmation arrives, record it". That
  is why the date and party guards matter: they stop a misread email from writing wrong data.
- A long Duet conversation re-sends everything it holds. Starting a fresh conversation per task
  saves more tokens than any server change.
