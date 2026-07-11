---
title: Release tracking
nav_label: Release tracking
part: Acquisition
slug: release-tracking-and-upcoming
order: 16
---
Release tracking watches TMDB for releases you don't have yet — new seasons of shows in your
library, new films in a series you own — and the Incoming page shows them as the **Coming up**
shelf. If acquisition is configured, tracking can also grab them automatically.

## What gets tracked

- **Automatically** when a new season is announced for a series you own, or a movie joins a
  collection you have.
- **Explicitly** from the Incoming page — **Track something** searches TMDB and follows a
  title you don't own yet.
- **From a download plan** when [search & download](/guide/search-and-download) leftovers are
  handed off to tracking.

## The Coming up shelf

One card per tracked title, nearest first, carrying its next release: a date badge that gets
more explicit with distance (Tonight → Tue → Fri Jul 17 → Aug 6) and a status pill. A whole
season dropping on one day collapses into one "all N episodes at once" card. Past the first
six titles the shelf caps — **Show all N** grows it in place. Titles TMDB hasn't dated yet sit
in a quiet "Also tracking" line under the shelf.

Click a card for the title's detail: its full release timeline, recent activity, and the
auto-grab toggle. The status pills:

| Status | Meaning |
|---|---|
| Landed | You already have it |
| In pursuit | Released and being grabbed now — click the pill to jump to the live download below |
| Armed | A future release that *will* auto-grab when it drops — shown only when a grab will genuinely fire |
| Tracked | Dated, but won't auto-grab |
| In theaters | A film's cinema date — informational only, never grabbed |

## Auto-grab

When a tracked release airs and you don't have it, the app records a durable **want**. A
planner periodically sweeps open wants, batches what's due, and — if the title's mode allows —
turns them into a [pursuit](/guide/pursuits). The mode is global with per-title overrides:

| Mode | Behaviour |
|---|---|
| All releases | Grab automatically |
| Ask | Park a draft plan on Incoming for you to approve |
| Off | Track for information only |

Wants persist through TMDB calendar changes and transient outages — a missed sweep is caught
by the next.

> [!TIP]
> The patience window is the feature to know. If you want 4K but only a 1080p release has
> appeared, tracking *waits* — for a configurable window (48 hours by default) it insists on
> your top quality, then falls back to your floor and grabs what's there. Set it per title and
> you stop getting a 1080p grab an hour before the 4K release lands. Flip a title's auto-grab
> on or off from its detail panel without leaving the page.
