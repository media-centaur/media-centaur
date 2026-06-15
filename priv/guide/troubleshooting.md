---
title: Troubleshooting
part: Operating it
slug: troubleshooting
order: 17
---
When something's wrong, the goal is to find *which part* is unhappy and then either fix the
cause or recompute what went stale. This chapter is the method and the common cases; it leans
on [Observability](/guide/observability) and the [mental model](/guide/the-mental-model).

## The method

1. **Console first.** Press the backtick, filter to the component you suspect, and reproduce
   the problem. Most issues announce themselves here — a TMDB auth error, a watcher that
   isn't firing, mpv refusing to launch.
2. **Status next.** If nothing's obvious in the logs, open Status and look for a coloured
   tile. Drill in for that subsystem's metrics, recent logs, and any incident.
3. **Recompute if it's derived.** If the data is wrong rather than the machinery (bad
   artwork, blank names), the fix is usually a maintenance action, not a repair.

## Common cases

- **A file didn't import.** It's almost certainly in the [Review queue](/guide/the-review-queue)
  as a low-confidence match — accept or search it there. If it's not even there, check the
  watcher (Settings → the directory is listed, watchers are on) and press *Scan now*.
- **Wrong or missing artwork.** Use *Refresh artwork* on the title, or *Refresh image cache*
  across the whole library — artwork is re-downloadable from TMDB.
- **Metadata is wrong or nothing matches.** Confirm the TMDB key under Settings (Test
  connection), and filter the Console to `tmdb` for rate-limit or auth errors.
- **Playback won't start.** Check mpv's path in Settings, confirm `mpv --version` works, and
  filter the Console to `playback`. If mpv "exited before playback started," the service
  started before your desktop session — restart it so it inherits the display environment
  (see [Updates, retention & running as a service](/guide/updates-retention-and-service)).
- **A download finished but never landed.** Open the [pursuit](/guide/pursuits) and read its
  timeline and unit board — and make sure the download client saves into a watched media
  directory.
- **Library looks empty after a drive move.** Point the media directory at the new location;
  the next scan re-links by path and size. Don't clear the database. See
  [Moving & relinking media](/guide/moving-and-relinking-media).

## Maintenance, and why it's safe

Settings groups operator actions into non-destructive maintenance and a Danger Zone. The
non-destructive ones — repair missing images, re-fetch backdrops, refresh credits, re-derive
bonus-feature names — all act on *recomputable* data and are safe to re-run. The Danger
Zone's *Clear database* and *Refresh image cache* rebuild from your files and from TMDB.

The principle from the [mental model](/guide/the-mental-model) holds: everything these
actions touch is derivable again, so the only thing *Clear database* actually costs you is
watch progress. When a value looks wrong, recomputing it is the safe first move, not the last
resort.

> [!TIP]
> The fastest triage is two keystrokes: backtick to open the Console, then the component
> filter for the area you suspect. Nine times out of ten the error is sitting right there,
> already tagged with which subsystem produced it.

In short: Console to see what's failing, Status to see who's unhealthy, and a maintenance
recompute when the data (not the machinery) is wrong. The full case list lives in the
[Troubleshooting wiki page](https://github.com/media-centaur/media-centaur/wiki/Troubleshooting).
