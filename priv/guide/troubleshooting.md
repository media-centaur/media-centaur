---
title: Troubleshooting
part: Operating it
slug: troubleshooting
order: 18
---
The goal is to find which part is unhappy, then fix the cause or recompute what went stale.
The method, then the common cases.

## The method

1. **Console first.** Press the backtick, filter to the component you suspect, and reproduce
   the problem. Most issues announce themselves here.
2. **Status next.** If the logs are quiet, open Status and look for a coloured tile; drill in
   for that subsystem's metrics, recent logs, and any incident.
3. **Recompute if it's derived.** If the data is wrong rather than the machinery (artwork,
   names), the fix is a maintenance action, not a repair — see
   [The mental model](/guide/the-mental-model).

## Common cases

| Symptom | Fix |
|---|---|
| A file didn't import | It's almost certainly in the [Review queue](/guide/the-review-queue) as a low-confidence match — accept or search it there. If not, check the watcher (directory listed, watchers on) and press *Scan now* |
| Wrong or missing artwork | *Refresh artwork* on the title, or *Refresh image cache* across the library — artwork re-downloads from TMDB |
| Nothing matches / wrong metadata | Confirm the TMDB key (Test connection); filter the Console to `tmdb` for rate-limit or auth errors |
| Playback won't start | Check mpv's path in Settings; confirm `mpv --version` works; filter the Console to `playback` |
| "mpv exited before playback started" | The service started before your desktop session — restart it so it inherits the display environment (see [Updates, retention & service](/guide/updates-retention-and-service)) |
| A download finished but never landed | Open the [pursuit](/guide/pursuits), read its timeline and unit board, and confirm the download client saves into a watched media directory |
| Library empty after a drive move | Point the media directory at the new location; the next scan re-links by path and size. Don't clear the database — see [Moving & relinking media](/guide/moving-and-relinking-media) |
| The UI looks stale | Reload the page (a LiveView reconnect); if that doesn't help, check the Console with the `phoenix` / `live_view` filters on |

## Maintenance, and why it's safe

Settings groups operator actions into non-destructive **maintenance** (repair missing images,
re-fetch backdrops, refresh credits, re-derive bonus-feature names) and a **Danger Zone**
(clear database, refresh image cache). Everything they touch is recomputable — from your
files and from TMDB — so the only thing *Clear database* actually costs is watch progress.
When a value looks wrong, recomputing it is the safe first move, not the last resort.

> [!TIP]
> The fastest triage is two keystrokes: backtick to open the Console, then the component
> filter for the area you suspect. The error is usually sitting right there, already tagged
> with which subsystem produced it. The full case list is in the
> [Troubleshooting wiki page](https://github.com/media-centaur/media-centaur/wiki/Troubleshooting).
