---
title: Downloads
part: Acquisition
slug: downloads
order: 15
---
A download on the Downloads page is a goal, not a file: "get these episodes at this
quality". It outlives any one release — if the first release fails at your download
client, the next is tried under the same download — and it finishes only when the files
are in your library. When something grabbed but never showed up, its window is where you
find out why.

## States

| State | Meaning |
|---|---|
| Active | At least one episode is still being searched for or downloaded |
| Done | Everything landed |
| Partly done | Some episodes landed; the rest gave up or were cancelled |
| Gave up | Nothing acceptable was found and the attempts ran out |
| Cancelled | You stopped it |

The state is always a summary of the episodes, which matters most for the next part.

## One download, many episodes

A season pack or a multi-episode plan is **one** download with a coverage board: one row
per episode, grouped by season. A single release can cover many episodes (a pack covers a
whole season), and as files land each one checks off exactly its episode, by TMDB identity
rather than by guessing from the filename. Episodes land in whatever order the files
arrive; the download stays active until every episode has.

Each episode row reads one of: **Landed**, **Trying**, **Needs a pick**, **Gave up**,
**Cancelled**.

## Grabbed is not downloaded

A download reads **Grabbed** between the moment Prowlarr accepts a release and the moment
your download client shows the job in its queue — usually seconds. Prowlarr reports that
the hand-over succeeded, not that the download started, so this is the one stage where the
app knows a release was handed over and nothing more.

You don't have to watch it. If the client never takes the release, the download says so
itself: after half an hour it flips to **Not at your client**, and picking a different
release is the recovery. This is distinct from **Downloaded**, which the app only says
about a job it watched at your client and then saw leave.

## How a job is paired and lands

To connect a download to the job at your client (and then to the file on disk), the app
matches on the strongest signal it has, in order: the torrent's **infohash**, then the
**content path** on disk, then the **TMDB identity** (season and episode), and finally the
**release name**. This ladder is why a tracker-prefixed torrent name (`www.x.org - …`) or a
usenet grab with no hash still pairs correctly.

When a file finishes and the pipeline imports it into your library, the download is marked
done by a fast notification path — and, as a safety net, a reconciler re-checks every tick,
so even if that notification is missed the file is found on the next pass by its content
path or TMDB identity.

## Releases that fail

A release your client can't finish — usenet articles missing, a torrent with no seeders —
is abandoned and the next-best release tried in its place. Each one counts as an attempt,
and after four failed releases for an episode the download gives up on it. **Search again**
in the window plans the episodes that never arrived as a fresh download, skipping every
release already tried. With **Auto-grab** on, an episode it gave up on stays wanted and
release tracking looks again on its own.

## What you can do from the window

**Cancel download** stops it and removes its jobs from the client (partial data is deleted;
anything already imported stays). **Pick a different release** opens the list of
alternatives for the episode being tried. The app also acts on its own: a release with zero
seeders is abandoned, and a stalled one can be flagged for your pick.

> [!TIP]
> To diagnose a download that grabbed but never landed: read its status line first —
> **Not at your client** means the job never started. Otherwise read its **History**, which
> logs every grab, stall and pick. For a series, open the season on the **coverage board**
> to see which episode is stuck and on what release. If it's active but nothing is
> downloading, it's waiting for your pick — choose an alternative from the card. And if the
> file clearly landed but the download is still active, the reconciler will catch it on the
> next tick, by content path even when the torrent name never matched.

In short: a download is a durable, per-episode goal that pairs to your client by the
strongest identity available and lands files into the library on a fast path with a
reconciler behind it — its History and coverage board are where you look when one is stuck.
