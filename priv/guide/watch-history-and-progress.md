---
title: Watch history & progress
nav_label: Watch history
part: Watching
slug: watch-history-and-progress
order: 10
---
Two separate things track what you've watched, and the difference matters. **Progress** is
where you are in a title and whether you've finished it; it drives resume and Continue
Watching. **History** is a permanent log of completions; it drives the stats and heatmap on
the Watch history page. Progress changes as you watch; history only ever grows.

## Progress and Continue Watching

Progress is one record per playable item — your position, the duration, and whether it's
complete (at 90%). Continue Watching on the Home page is built from progress: it lists
everything you've started but not finished, most recent first, with a blended progress bar
(for a series, completed episodes plus your position in the current one).

Because progress is stored independently of the files, **Continue Watching survives an
offline drive**. Unplug the drive and its in-progress titles drop off the list; plug it back
in and they return exactly where you left them — your position was never on the drive. See
[Moving & relinking media](/guide/moving-and-relinking-media).

## History

Every time you complete a title, one event is appended to your history — the title (stored
by name, so it outlives the entry), its type, duration, and when. Rewatching adds another
event; nothing is deduplicated.

The Watch history page (`/history`) turns that log into:

- **Stats** — titles watched, hours watched, and your current daily streak.
- **An activity heatmap** — a year of days, shaded by how much you watched, switchable
  between all / movies / episodes / videos.
- **A filterable list** — by type, by text search, or by a single day. Rewatched titles
  carry a count badge, and each entry can be deleted on its own.

It all updates live as you finish things.

## What's kept

Watch history is the one thing Media Centaur keeps **forever** — it's the deliberate
exception to the retention sweeps that age out other data (see
[Updates, retention & running as a service](/guide/updates-retention-and-service)). There's
no bulk clear; you remove entries one at a time from the history page. Deleting a history
entry doesn't reset your progress — they're separate records.

> [!TIP]
> The heatmap isn't just a picture — click a day to filter the list to exactly what you
> finished that day. Combined with the type filter and search, it's the fastest way to answer
> "what did I watch last Saturday?"

In short: progress drives resume and Continue Watching (and survives offline drives); history
is a permanent, append-only completion log behind the stats and heatmap; and history is kept
forever while everything else is swept.
