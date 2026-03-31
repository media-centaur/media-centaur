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
| `log_status/0` | Thinking log state, framework suppression |
| `log_enable/1` | Enable a component (atom) |
| `log_disable/1` | Disable a component |
| `log_all/0` | Enable all |
| `log_none/0` | Disable all |
| `log_solo/1` | Enable only one |
| `services/0` | Watcher/pipeline state, watch dirs |

## The Troubleshoot Script

`scripts/troubleshoot` is the CLI interface. All Elixir-side calls go through `MediaCentaur.Diagnostics`.

### Quick Health Check

```bash
scripts/troubleshoot
```

Shows: service status, port, HTTP, database, supervision tree, thinking logs, services, playback, and recent errors.

### Tailing Logs

```bash
scripts/troubleshoot logs         # last 100 lines, follows
scripts/troubleshoot logs 500     # last 500 lines, follows
scripts/troubleshoot errors       # error-level only, last 1h
scripts/troubleshoot errors 24h   # error-level, last 24h
```

### Thinking Log Toggles

```bash
scripts/troubleshoot log status              # what's enabled
scripts/troubleshoot log enable pipeline     # turn on pipeline logs
scripts/troubleshoot log enable playback     # turn on playback logs
scripts/troubleshoot log all                 # everything on
scripts/troubleshoot log solo watcher        # only watcher
scripts/troubleshoot log none                # clean up when done
```

Components: `watcher`, `pipeline`, `tmdb`, `playback`, `library`

Changes persist to DB and survive restarts. **Always run `log none` when done.**

### Remote Shell

```bash
scripts/troubleshoot remote
```

Disconnect with `Ctrl+\`.

## Logging Configuration

### TOML Defaults (`~/.config/media-centaur/backend.toml`)

```toml
[logging]
components = []                                        # thinking log components on by default
suppress_framework = ["ecto", "phoenix", "live_view"]  # framework modules to suppress
```

These are first-boot defaults. Once toggled at runtime (via troubleshoot script, `/operations` page, or IEx), the DB setting takes precedence.

To always have playback logging in production: set `components = ["playback"]` in the TOML.

### Component Formatter

Production uses the component-aware formatter (`MediaCentaur.Log.Formatter`), so thinking logs show `[info][playback] resolved entity Dept Q — play_next, file.mkv` in the journal.

## LLM Troubleshooting Interface

### Production (via Bash)

```bash
scripts/troubleshoot log enable playback    # enable logs
scripts/troubleshoot logs                   # watch output
scripts/troubleshoot log none               # clean up
```

### Dev (via Tidewave MCP)

Call functions directly on the running dev node:
- `MediaCentaur.Log.enable(:playback)`
- `MediaCentaur.Diagnostics.playback()`
- `MediaCentaur.Diagnostics.log_status()`

## Common Debugging Workflows

### "Play does nothing"

1. `scripts/troubleshoot log enable playback`
2. Reproduce the play action
3. `scripts/troubleshoot logs` — the resolver now logs every decision point:
   - Which UUID was requested
   - Which resolution strategy matched (entity/episode/movie/extra)
   - Why it failed (not found, no content_url, no playable content)
   - Or what action was resolved (resume, play_next, restart) with the file
4. `scripts/troubleshoot log none` when done

### "Files aren't being detected"

1. `scripts/troubleshoot log enable watcher`
2. `scripts/troubleshoot logs`

### "TMDB lookups failing"

1. `scripts/troubleshoot log enable tmdb`
2. `scripts/troubleshoot logs`

### "Service keeps crashing"

1. `scripts/troubleshoot errors 24h`
2. `journalctl --user -u media-centaur-backend --since "1 hour ago"`

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
