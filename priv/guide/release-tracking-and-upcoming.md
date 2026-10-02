---
title: Release tracking
nav_label: Release tracking
part: Acquisition
slug: release-tracking-and-upcoming
order: 17
---
Release tracking watches TMDB for releases you don't have yet — the next season of a show, a
film that isn't out — for every title with **Track release dates** or **Auto-grab** on in your
[watchlist](/guide/watchlist-and-tracking). The title's watchlist row shows its next release;
Home's **Coming up** shelf shows the releases of the next three months. If acquisition is
configured, tracking can grab them too.

## What gets tracked, and why it stops

A title is tracked because you turned on **Track release dates** or **Auto-grab** for it, and
for no other reason. Adding a series to your library does not start tracking it; neither does
downloading one.

- **Deleting a series from your library does not stop tracking it.** The switches are yours,
  and losing the files says nothing about whether you still want new episodes.
- **Taking a title off your list stops it, and deletes its calendar.** So does turning Track
  release dates off. Nothing except you can turn it back on.

## The next release on the row

A tracked title's watchlist row carries its next release still to come at the right: a date
that gets more explicit with distance (Tonight → Tue → Fri Jul 17 → Aug 6), the release
(S02E04; a whole season dropping on one day collapses into one "all N episodes at once" line;
a film's digital or disc date) and a status pill. Rows are ordered nearest first.

Titles TMDB hasn't dated yet have no next release. Their rows follow the dated ones, with
**Tracking** or **Auto-grab** as the marker.

A release that has already come out and is still missing stays on the row for as long as the
app is searching for it — the date reads as how long ago it came out ("5 days ago",
"May 1998") and the pill reads **Searching**. A release you have reads **Landed** for a week
when nothing later is scheduled; otherwise the row moves on to the next one.

| Status | Meaning |
|---|---|
| Landed | You already have it |
| In pursuit | Released and being grabbed now — the download is on the Activity tab |
| Will grab | A future release that *will* be grabbed when it drops — shown only when a grab will genuinely fire |
| Searching | A release whose date has passed that you still don't have — indexers are being re-checked for it |
| Tracked | Dated, but won't auto-grab |
| In theaters | A film's cinema date — informational only, never grabbed |

Click a row for the title: its release dates beside the two switches.

## Auto-grab

When a tracked release airs and you don't have it, the app records a durable **want**. A planner
periodically sweeps open wants, batches what's due, and — for a title with **Auto-grab** on —
turns them into a [pursuit](/guide/pursuits). Whether the plan downloads without asking or
waits for your approval is your Download button default under **Settings → Acquisition**.

Wants persist through TMDB calendar changes and transient outages — a missed sweep is caught by
the next.

Quality follows the Auto-acquisition settings, **Highest resolution** and **Within a
resolution**. The best release available at the time is taken right away; there is no waiting
period for a higher quality, so an episode grabbed at 1080p is not replaced when a 4K release
appears later.
