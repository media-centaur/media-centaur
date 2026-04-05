---
name: troubleshoot
description: "Use this skill when debugging production issues, checking service health, enabling runtime logs, or investigating errors in the deployed Media Centaur backend."
---

## Production Deployment

- **Service:** `media-centaur-backend` (systemd user unit)
- **Install dir:** `~/.local/lib/media-centaur/`
- **Binary:** `~/.local/lib/media-centaur/bin/media_centaur`
- **Database:** `~/.local/share/media-centaur/media_library.db` (SQLite)
- **Config:** `~/.config/media-centaur/backend.toml`
- **Port:** 4000 (loopback only)
- **Node:** `media_centaur` (sname, cookie: `media-centaur-local`)

Dev runs on port 4001. Both coexist on the same machine.

## Diagnostics Module

All diagnostic logic lives in `MediaCentaur.Diagnostics` (`lib/media_centaur/diagnostics.ex`). The troubleshoot script calls these named functions — never inline Elixir code.

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

`scripts/troubleshoot` is the CLI interface. All Elixir-side calls go through `MediaCentaur.Diagnostics`.

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
scripts/troubleshoot log recent 50          # last 50 buffered log entries
scripts/troubleshoot logs                   # tail systemd journal
scripts/troubleshoot errors 24h             # error-level journal entries, last 24h
```

### Dev (via Tidewave MCP)

Call functions directly on the running dev node:
- `MediaCentaur.Diagnostics.log_recent(20)` — print recent entries
- `MediaCentaur.Console.recent_entries(20)` — same data as `%Entry{}` structs
- `MediaCentaur.Console.snapshot()` — entries + buffer cap + current filter
- `MediaCentaur.Diagnostics.playback()` — active playback state
- `MediaCentaur.Diagnostics.services()` — watcher/pipeline/session counts
- `MediaCentaur.Diagnostics.status()` — supervision tree health

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
3. `journalctl --user -u media-centaur-backend --since "1 hour ago"` — full
   journal context around the crash

## Systemd Operations

```bash
systemctl --user start media-centaur-backend
systemctl --user stop media-centaur-backend
systemctl --user restart media-centaur-backend
```

## Rebuilding and Deploying

```bash
scripts/release          # build production release
scripts/install          # install + migrate + restart
```
