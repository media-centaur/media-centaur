---
title: Release tracking & Upcoming
part: Acquisition
slug: release-tracking-and-upcoming
order: 15
---
Release tracking watches TMDB for releases you don't have yet — new seasons of shows in your
library, new films in a series you own — and the Upcoming page shows them as a forecast. If
acquisition is configured, tracking can also grab them automatically.

## What gets tracked

- **Automatically** when a new season is announced for a series you own, or a movie joins a
  collection you have.
- **Explicitly** from the Upcoming page — search TMDB and follow a title you don't own yet.
- **From a download plan** when [search & download](/guide/search-and-download) leftovers are
  handed off to tracking.

## The Upcoming page

A timeline runs by air date — Today, This week, Next week, Later — with the nearest release
shown large and the rest compact; a whole season dropping on one day collapses into one
"drops N episodes" entry. A mini-month lets you jump to a date. Each entry carries an honest
status:

| Status | Meaning |
|---|---|
| In library | You already have it |
| Under pursuit | Released and being grabbed now (links to its pursuit on Downloads) |
| Armed | A future release that *will* auto-grab when it drops — shown only when a grab will genuinely fire |
| Upcoming | Tracked and dated, but won't auto-grab |
| Theatrical | A film's cinema date — informational only, never grabbed |
| (unscheduled) | Tracked but TMDB hasn't announced a date; sits in a separate group |

## Auto-grab

When a tracked release airs and you don't have it, the app records a durable **want**. A
planner periodically sweeps open wants, batches what's due, and — if the title's mode allows —
turns them into a [pursuit](/guide/pursuits). The mode is global with per-title overrides:

| Mode | Behaviour |
|---|---|
| All releases | Grab automatically |
| Ask | Park a draft on Downloads for you to approve |
| Off | Track for information only |

Wants persist through TMDB calendar changes and transient outages — a missed sweep is caught
by the next.

> [!TIP]
> The patience window is the feature to know. If you want 4K but only a 1080p release has
> appeared, tracking *waits* — for a configurable window (48 hours by default) it insists on
> your top quality, then falls back to your floor and grabs what's there. Set it per title and
> you stop getting a 1080p grab an hour before the 4K release lands. Flip a title's auto-grab
> on or off from its detail panel without leaving the page.
