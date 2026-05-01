---
name: troubleshoot
description: "Use this skill when debugging production issues, checking service health, enabling runtime logs, or investigating errors in the deployed Media Centarr backend."
---

## Production Deployment

- **Service:** `media-centarr` (systemd user unit)
- **Install dir:** `~/.local/lib/media-centarr/`
- **Binary:** `~/.local/lib/media-centarr/bin/media_centarr`
- **Database:** `~/.local/share/media-centarr/media-centarr.db` (SQLite)
- **Config:** `~/.config/media-centarr/media-centarr.toml`
- **Port:** 2160 (loopback only)
- **Node:** `media_centarr` (sname, cookie: `media-centarr-local`)

Dev runs on port 1080 (see `MEDIA_CENTARR_CONFIG_OVERRIDE` in the dev systemd unit). Both coexist on the same machine.

## Diagnostics Module

All diagnostic logic lives in `MediaCentarr.Diagnostics` (`lib/media_centarr/diagnostics.ex`). The troubleshoot script calls these named functions — never inline Elixir code.

| Function | Purpose |
|----------|---------|
| `status/0` | Supervision tree health, child counts |
| `playback/0` | Active sessions, state, position |
| `log_recent/1` | Print the N most recent console buffer entries (default: 20) |
| `services/0` | Watcher/pipeline state, watch dirs |

Log visibility is controlled in the browser console (press backtick, or
navigate to `/console`) — there is no runtime enable/disable at the logger
level. The buffer captures every log; filtering is a display concern.

## The Troubleshoot Script

`scripts/troubleshoot` is the CLI interface. All Elixir-side calls go through `MediaCentarr.Diagnostics`.

### Quick Health Check

```bash
scripts/troubleshoot
```

Shows: service status, port, HTTP, database, supervision tree, recent console
entries, services, playback, and recent errors from the systemd journal.

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
into `MediaCentarr.Console.Buffer` — an in-memory ring buffer (default 2,000
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

Production uses the component-aware formatter (`MediaCentarr.Log.Formatter`),
so thinking logs show `[info][playback] resolved entity Dept Q — play_next, file.mkv`
in `journalctl`. The browser console shows the same entries with rich
filtering. Choose whichever is faster for the task at hand.

## LLM Troubleshooting Interface

### Production (via Bash)

```bash
scripts/troubleshoot                        # dashboard (service health + recent console entries)
scripts/troubleshoot log recent 50          # last 50 buffered log entries
scripts/troubleshoot logs                   # tail systemd journal
scripts/troubleshoot errors 24h             # error-level journal entries, last 24h
```

For arbitrary state queries against the running production node, use the
`mc-rpc` wrapper (`~/scripts/mc-rpc`) — it pipes an Elixir expression to
`bin/media_centarr rpc` on the installed release and prints the result.
Same `Diagnostics.*` helpers as dev work; non-interactive, scripts cleanly:

```bash
mc-rpc 'MediaCentarr.Diagnostics.services()'
mc-rpc 'alias MediaCentarr.{Library, Repo}; import Ecto.Query; Repo.aggregate(Library.Movie, :count)'
echo 'MediaCentarr.Console.snapshot()' | mc-rpc
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
mc-debug-browser --url http://localhost:1080   # point at the dev server instead
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
- `MediaCentarr.Diagnostics.log_recent(20)` — print recent entries
- `MediaCentarr.Console.recent_entries(20)` — same data as `%Entry{}` structs
- `MediaCentarr.Console.snapshot()` — entries + buffer cap + current filter
- `MediaCentarr.Diagnostics.playback()` — active playback state
- `MediaCentarr.Diagnostics.services()` — watcher/pipeline/session counts
- `MediaCentarr.Diagnostics.status()` — supervision tree health

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
3. `journalctl --user -u media-centarr --since "1 hour ago"` — full
   journal context around the crash

## Systemd Operations

```bash
systemctl --user start media-centarr
systemctl --user stop media-centarr
systemctl --user restart media-centarr
```

## Rebuilding and Deploying

```bash
scripts/preflight        # build a production release locally to verify it compiles
```

Deployment happens by tagging (`/ship <level>`) and letting the running app update itself via Settings > Overview → *Update now*. There is no `scripts/install` any more — never hand-roll an install over the top of a real deployment; the in-app updater does the atomic symlink flip and migrations safely.
