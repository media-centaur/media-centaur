---
title: Release tracking
nav_label: Release tracking
part: Acquisition
slug: release-tracking-and-upcoming
order: 17
---
Release tracking watches TMDB for releases you don't have yet — new seasons of shows in your
library, new films in a series you own, anything you armed from your
[watchlist](/guide/watchlist-and-tracking) — and the Incoming page shows the dated ones as the
**Coming up** shelf. If acquisition is configured, tracking can grab them too.

## What gets tracked, and why it stops

A title is tracked while there's a reason to track it. There are two, and they behave
differently:

- **You own it.** A series in your library is followed automatically, and a movie you own joins
  its collection's tracking. This is the app's default, so it goes away when the reason does:
  delete the series and tracking stops.
- **You armed it.** Setting a tracking mode is your decision, so it outlives the library. Delete
  an armed series and it keeps its place on your watchlist and its mode; new seasons still
  arrive. Take it off the watchlist to stop it.

Turning a title's tracking **Off** is remembered whatever else happens to it.

## The Coming up shelf

One card per tracked title with a dated release, nearest first: a date badge that gets more
explicit with distance (Tonight → Tue → Fri Jul 17 → Aug 6) and a status pill. A whole season
dropping on one day collapses into one "all N episodes at once" card. Past the first six titles
the shelf caps — **Show all N** grows it in place.

Titles TMDB hasn't dated yet don't appear here. They're on your watchlist, or in your library,
with their mode on the row.

| Status | Meaning |
|---|---|
| Landed | You already have it |
| In pursuit | Released and being grabbed now — click the pill to jump to the live download below |
| Armed | A future release that *will* auto-grab when it drops — shown only when a grab will genuinely fire |
| Tracked | Dated, but won't auto-grab |
| In theaters | A film's cinema date — informational only, never grabbed |

Click a card for the title: its release timeline, recent activity, and the tracking control.
Titles you own open in the library instead, and carry the same timeline and control there.

## Auto-grab

When a tracked release airs and you don't have it, the app records a durable **want**. A planner
periodically sweeps open wants, batches what's due, and — if the title's mode allows — turns
them into a [pursuit](/guide/pursuits). Per-title modes are in
[the watchlist](/guide/watchlist-and-tracking#tracking-modes); a title left on **Default**
follows the global setting and changes with it.

Wants persist through TMDB calendar changes and transient outages — a missed sweep is caught by
the next.

> [!TIP]
> The patience window is the feature to know. If you want 4K but only a 1080p release has
> appeared, tracking *waits* — for a configurable window (48 hours by default) it insists on
> your top quality, then falls back to your floor and grabs what's there. Set it per title and
> you stop getting a 1080p grab an hour before the 4K release lands.
