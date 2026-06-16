---
title: Running a large library
nav_label: Large libraries
part: Operating it
slug: running-a-large-library
order: 22
---
Media Centaur is built to stay responsive at scale, but a few thousand files surface one
system limit and one expectation worth setting. Nothing here is required for a small library.

## Raise the inotify watch limit

The watcher uses Linux's inotify to notice file changes, and each watched directory consumes
one "watch." Distributions ship a modest default (often 8192), which a large library can
exhaust — the symptom is the watcher silently missing new files or a scan that never finishes.

Raise it, and persist it across reboots:

```sh
# check the current limit
cat /proc/sys/fs/inotify/max_user_watches
# raise it now, and on every boot
sudo sysctl fs.inotify.max_user_watches=524288
echo 'fs.inotify.max_user_watches=524288' | sudo tee /etc/sysctl.d/40-media-centaur.conf
```

If the **Watcher** tile on the Status page shows a scan that isn't advancing, this is the
first thing to check.

## What to expect on a big import

- **The first scan takes a while.** Every file is parsed, matched against TMDB (rate-limited),
  and has artwork downloaded. It runs in the background — you can use the app meanwhile.
- **The UI may lag during a burst, then snaps back.** Reads come from in-memory projections,
  not the database, so a heavy import doesn't block browsing; the projections catch up within
  a fraction of a second once the burst eases. This is the [mental model](/guide/the-mental-model)
  doing its job, not a fault.
- **Newly-added files settle before import.** A file still being copied is held briefly rather
  than imported half-written. *Scan now* (Settings → General → Services) forces a full re-scan
  if you've moved a lot at once.

## Keeping it bounded

A large library doesn't grow unbounded on the housekeeping side: the daily retention sweep
ages out finished download records, logs, and stale queue entries (see
[Updates, retention & running as a service](/guide/updates-retention-and-service)). Your
backup footprint is still just the database — artwork re-downloads from TMDB — so backups stay
small regardless of library size (see
[Settings, configuration & backups](/guide/settings-configuration-and-backups)).
