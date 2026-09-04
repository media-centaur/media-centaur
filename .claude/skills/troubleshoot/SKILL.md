---
name: troubleshoot
description: "Use this skill when debugging production issues, checking service health, enabling runtime logs, or investigating errors in the deployed Media Centaur backend."
---

> **Current setup (dev-only):** this machine now runs the **dev instance as the
> sole daily driver** — `media-centaur-dev` (`mix phx.server`), port **2160**,
> against the real library DB, with `MEDIA_CENTAUR_DURABLE_DIAGNOSTICS=1` so it
> mints incidents normally. The installed prod release (`media-centaur`) is
> **stopped + disabled**. Reach the running node through **Tidewave MCP**
> (`mcp__tidewave__project_eval` at `http://127.0.0.1:2160/tidewave/mcp`),
> evaluating `MediaCentaur.Diagnostics.*` / `MediaCentaur.ErrorReports.*`
> directly. The release-targeting tools below (`scripts/troubleshoot`, `mc-rpc`,
> the `media_centaur` node) only work if you re-enable the prod release.

## Production Deployment (the installed release — disabled on this machine)

- **Service:** `media-centaur` (systemd user unit)
- **Install dir:** `~/.local/lib/media-centaur/`
- **Binary:** `~/.local/lib/media-centaur/bin/media_centaur`
- **Database:** `~/.local/share/media-centaur/media-centaur.db` (SQLite) — shared with the dev daily driver
- **Config:** `~/.config/media-centaur/media-centaur.toml`
- **Port:** 2160 (loopback only) — now bound by the dev instance instead
- **Node:** `media_centaur` (sname, cookie: `media-centaur-local`)

This is the artifact other end users run; keep it understood even though it's not
the daily driver here.

## Diagnostics Module

All diagnostic logic lives in `MediaCentaur.Diagnostics` (`lib/media_centaur/diagnostics.ex`). The troubleshoot script calls these named functions — never inline Elixir code.

| Function | Purpose |
|----------|---------|
| `status/0` | Supervision tree health, child counts |
| `playback/0` | Active sessions, state, position |
| `log_recent/1` | Print the N most recent console buffer entries (default: 20) |
| `services/0` | Watcher/pipeline state, media dirs |

Log visibility is controlled in the browser console (press backtick, or
navigate to `/console`) — there is no runtime enable/disable at the logger
level. The buffer captures every log; filtering is a display concern.

## The Troubleshoot Script

`scripts/troubleshoot` is the CLI interface. All Elixir-side calls go through `MediaCentaur.Diagnostics`.

### Quick Health Check

```bash
scripts/troubleshoot
```

Shows: service status, port, HTTP, database, supervision tree, recent console
entries, services, playback, open incidents, and recent errors from the
systemd journal.

### Investigating an Incident

An **incident** is a durable record (the `incidents` table), distinct from the
volatile Console log buffer: it survives restarts and freezes its own
cross-subsystem context at capture time (`first_context`/`latest_context` — the
lead-up logs, every subsystem's vitals, the firing subsystem's contributor
data, and the triggering ids). This is usually the fastest way to understand a
production fault *after the fact*, since the live log buffer may already have
rolled over.

Incidents come from two tracks (ADR-054). **`:log`** incidents are minted 1:1
from any `warning`/`error` log line — the safety net for unexpected, un-owned
errors. They have no live recovery signal (a log line is a point-in-time
event), so they don't auto-resolve on health recovery the way `:subsystem`
incidents do; instead a daily maintenance sweep (`SupersededSweepJob`) resolves
any open `:log` incident last seen on a version no longer running — a deploy is
the terminal signal, since that exact code can't recur. They're resolved (with
`resolved_at`), not deleted, so the audit trail survives. A still-recurring
incident keeps `app_version_at_last` current and is never swept. (Note: a
transport-layer client disconnect — `Bandit.TransportError` `:timeout`/`:closed`,
or its HTTP-layer twin, a `Bandit.HTTPError` read timeout — is not an
application fault and never mints a `:log` incident, though it still shows in
the console. Likewise, Req's own retry log lines — anything from
`Req.Steps.log_retry/5`, e.g. `http2 error: :pool_not_available` and the
`will retry in N, attempts left` that follows — are transient by definition
(Req is recovering on its own; a terminal give-up is logged by the *caller* and
mints normally), so they stay in the console but never mint a `:log` incident.
The dev code reloader's own artifacts — a stale-closure `BadFunctionError`, an
`UndefinedFunctionError` for a module no longer loaded, or the
`Phoenix.Ecto.PendingMigrationError` the dev-only `CheckRepoStatus` plug raises
when source reloads ahead of `mix ecto.migrate` — never mint either.
Durable minting is also **prod-only**: the dev server shares the
prod database, so its hot-reload crashes and shutdown markers would otherwise
pollute the production Status page. Crash incidents are attributed to the
subsystem owning the crashing stack frame — `Console.Entry`'s crash-frame
classification — not the framework module that logged it; only crashes no
subsystem owns land under `system`.) **`:subsystem`** incidents come from a subsystem's `assess/0` health
probe polled by the evaluator: grouped by `{component, kind}`, threshold-gated,
and **auto-resolving** when health recovers. External-dependency connectivity
(e.g. the download client — `Downloads.IncidentContext`) lives on the
`:subsystem` track, so a transient qBittorrent timeout no longer mints a flock
of duplicate `:log` incidents — a sustained outage opens exactly one
`{:acquisition, :download_client_unreachable}` incident that closes itself on
recovery. Those connectivity `Log.warning` lines still appear in the console
(tagged `mc_incident: :skip`); they just no longer create `:log` incidents.

```bash
scripts/troubleshoot issues             # exactly what the Status page shows, grouped by subsystem
scripts/troubleshoot incidents          # list recent incidents (short id, severity, title)
scripts/troubleshoot incidents 50       # list the 50 most recent
scripts/troubleshoot incident           # full dump of the most recent incident
scripts/troubleshoot incident 95e0a7c8  # full dump by short id (from the listing)
scripts/troubleshoot incident fp_xyz    # ...or by fingerprint
scripts/troubleshoot dismiss 95e0a7c8   # remove one false-positive incident
scripts/troubleshoot dismiss all        # clear every issue currently on the board
```

`dismiss` *removes* the incident (it doesn't mark it `:resolved`), so it won't
reappear on the next cache rebuild — use it to clear false-positives a fix has
already addressed. A still-live fault re-mints from fresh evidence, so dismiss
never permanently silences a real one. Bulk-clear with `dismiss all` after
landing a noise-suppression fix (the already-minted incidents predate the fix
and won't disappear on their own until the next deploy's superseded-sweep).

**`issues` vs `incidents`:** `issues` prints the **bucket cache**
(`ErrorReports.list_buckets/0`) — exactly the set the Status page renders,
grouped by subsystem, with each row's *fingerprint* as the handle. This is the
faithful "what's on the board" query and the entry point for `/resolve-issues`.
`incidents` prints the broader `Store.list_incidents` listing (ordered by
last-seen), a superset that can include older resolved incidents already aged
out of the board window. Use `issues` to see what a user sees; `incidents` to
audit history.

`incident` resolves its reference in order: `:latest` (omit the arg) → full id
→ short id prefix → fingerprint. The dump renders the header plus the frozen
context, with lead-up log lines that share a triggering id flagged
`(correlated)` — the causal chain. Incidents whose context predates the
snapshot rollout show *"No frozen context captured"*; fall back to `log recent`
for those.

Resolution lives in `ErrorReports.Store.find_incident/1`; rendering lives in
the pure `MediaCentaur.Diagnostics.format_incident/1` (so the same dump is
reachable from any REPL — e.g. `mc-rpc 'MediaCentaur.Diagnostics.incident("95e0a7c8")'`).

### Tailing Logs

```bash
scripts/troubleshoot logs         # last 100 lines, follows
scripts/troubleshoot logs 500     # last 500 lines, follows
scripts/troubleshoot errors       # error-level only, last 1h
scripts/troubleshoot errors 24h   # error-level, last 24h
```

### Recent Buffered Log Entries

```bash
scripts/troubleshoot log recent        # last 20 buffer entries
scripts/troubleshoot log recent 100    # last 100 buffer entries
```

The buffer captures every log component and framework event
(`watcher`, `pipeline`, `tmdb`, `playback`, `library`, `system`, `phoenix`,
`ecto`, `live_view`). Visibility filtering happens in the browser console —
press backtick on any page, or navigate to
`http://127.0.0.1:$port/console` for a full-page view.

### Remote Shell

```bash
scripts/troubleshoot remote
```

Disconnect with `Ctrl+\`.

## Log Architecture

Every log emitted by the application flows through an Erlang `:logger` handler
into `MediaCentaur.Console.Buffer` — an in-memory ring buffer (default 2,000
entries, configurable up to 50,000). The buffer captures unconditionally; the
console UI applies display-time filtering via component chips, a level floor
(info/warning/error), and a text search box.

Default filter on first boot: app components (`watcher`, `pipeline`, `tmdb`,
`playback`, `library`, `system`) visible, framework components (`phoenix`,
`ecto`, `live_view`) hidden. Users can flip any chip on to see that
component's entries.

Filter state and buffer size are persisted per user in `Settings.Entry` with a
2-second debounce and survive restarts.

### Component Formatter (terminal / journal)

Production uses the component-aware formatter (`MediaCentaur.Log.Formatter`),
so thinking logs show `[info][playback] resolved entity Dept Q — play_next, file.mkv`
in `journalctl`. The browser console shows the same entries with rich
filtering. Choose whichever is faster for the task at hand.

## LLM Troubleshooting Interface

### Production (via Bash)

```bash
scripts/troubleshoot                        # dashboard (service health + recent console entries)
scripts/troubleshoot issues                 # what the Status page shows (board buckets, by subsystem)
scripts/troubleshoot incidents              # list recent durable incidents
scripts/troubleshoot incident 95e0a7c8      # full forensic dump for one incident
scripts/troubleshoot dismiss 95e0a7c8       # remove a false-positive incident (or 'all')
scripts/troubleshoot log recent 50          # last 50 buffered log entries
scripts/troubleshoot logs                   # tail systemd journal
scripts/troubleshoot errors 24h             # error-level journal entries, last 24h
```

For arbitrary state queries against the running production node, use the
`mc-rpc` wrapper (`~/scripts/mc-rpc`) — it pipes an Elixir expression to
`bin/media_centaur rpc` on the installed release and prints the result.
Same `Diagnostics.*` helpers as dev work; non-interactive, scripts cleanly:

```bash
mc-rpc 'MediaCentaur.Diagnostics.services()'
mc-rpc 'alias MediaCentaur.{Library, Repo}; import Ecto.Query; Repo.aggregate(Library.Movie, :count)'
echo 'MediaCentaur.Console.snapshot()' | mc-rpc
```

Set `MC_BIN` to override the release path on hosts with a non-default install.

For browser-side diagnostics against the production install, use the
`mc-debug-browser` wrapper (`~/scripts/mc-debug-browser`) — it launches a
headless Chromium with remote debugging on port 9223 and a tmp profile,
isolated from the user's normal browser (no extensions, no shared state).
Idempotent; reuses the running instance if already attached. The
`chrome-devtools` MCP server picks it up automatically.

```bash
mc-debug-browser                      # launch (or reuse) — defaults to http://localhost:2160
mc-debug-browser --headed             # show the window for visual inspection
mc-debug-browser --url http://localhost:2160   # point at the dev server instead
mc-debug-browser --status             # is it running?
mc-debug-browser --kill               # tear it down
```

Override defaults with `MC_DEBUG_PORT`, `MC_DEBUG_URL`, `MC_DEBUG_PROFILE`,
or `MC_DEBUG_BIN`. The isolated profile means a clean session every time —
useful when a user reports a bug you can't reproduce, since their main
profile may carry stale storage, service workers, or extensions that the
debug browser won't.

### Dev (via Tidewave MCP)

Call functions directly on the running dev node:
- `MediaCentaur.Diagnostics.log_recent(20)` — print recent entries
- `MediaCentaur.Console.recent_entries(20)` — same data as `%Entry{}` structs
- `MediaCentaur.Console.snapshot()` — entries + buffer cap + current filter
- `MediaCentaur.Diagnostics.playback()` — active playback state
- `MediaCentaur.Diagnostics.services()` — watcher/pipeline/session counts
- `MediaCentaur.Diagnostics.status()` — supervision tree health
- `MediaCentaur.Diagnostics.incidents(20)` — recent durable incidents
- `MediaCentaur.Diagnostics.incident(:latest)` — full dump of one incident

## Common Debugging Workflows

### "Play does nothing"

1. Reproduce the play action
2. `scripts/troubleshoot log recent 30` — look for `:playback` component entries:
   - Which UUID was requested
   - Which resolution strategy matched (parent/episode/child movie/extra)
   - Why it failed (not found, no content_url, no playable content)
   - Or what action was resolved (resume, play_next, restart) with the file
3. If the noise is too much, open the browser console (backtick), solo the
   `:playback` chip, and reproduce again for a focused view.

### "Files aren't being detected"

Open browser console, solo the `:watcher` chip, and exercise the file flow.
Or: `scripts/troubleshoot log recent 50` and grep for `[watcher]`.

### "TMDB lookups failing"

Open browser console, solo the `:tmdb` chip, and trigger the pipeline. Watch
for rate-limit warnings, 404s, and confidence scoring decisions.

### "Service keeps crashing"

1. `scripts/troubleshoot errors 24h` — systemd journal errors
2. `scripts/troubleshoot log recent 100` — in-memory buffer (lost on restart,
   so may be empty after a crash)
3. `journalctl --user -u media-centaur --since "1 hour ago"` — full
   journal context around the crash

## Systemd Operations

```bash
systemctl --user start media-centaur
systemctl --user stop media-centaur
systemctl --user restart media-centaur
```

## Rebuilding and Deploying

```bash
scripts/preflight              # build a production release locally to verify it compiles
scripts/ship check             # full upgrade-safety gate (includes preflight + contract checks)
scripts/ship verify [version]  # confirm a tagged release published (tarballs + SHA256SUMS), fail-fast on a failed workflow run
```

Deployment happens by tagging (`/ship <level>`, mechanics in `scripts/ship`) and letting the running app update itself via Settings > Overview → *Update now*. There is no `scripts/install` any more — never hand-roll an install over the top of a real deployment; the in-app updater does the atomic symlink flip and migrations safely.

If a user reports "Update now does nothing" or a stuck update check, `scripts/ship verify <version>` answers whether the release assets ever made it to GitHub before you go digging in the updater.
