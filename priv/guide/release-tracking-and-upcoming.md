---
title: Release tracking & Upcoming
part: Acquisition
slug: release-tracking-and-upcoming
order: 14
---
Release tracking watches TMDB for releases you don't have yet — new seasons of shows in your
library, new films in a series you own — and the Upcoming page shows them as a forecast. If
acquisition is configured, tracking can also grab them for you the moment they're available.

## What gets tracked

A title starts being tracked automatically when it's relevant: a new season is announced for
a series you own, or a movie joins a collection you have. You can also track something
explicitly from the Upcoming page — search TMDB and follow a title you don't own yet, such as
an announced sequel. When a [search & download](/guide/search-and-download) plan can't cover
everything, its leftovers are handed to tracking too.

## The Upcoming page

Upcoming (`/upcoming`) is a time-first forecast, not a control panel. A timeline runs by air
date — Today, This week, Next week, Later — with the nearest release shown large and the rest
as compact rows; a whole season dropping on one day collapses into a single "drops N
episodes" entry. A quiet mini-month on the side lets you jump to a date. Each entry carries an
honest status:

- **In library** — you already have it.
- **Under pursuit** — released and being grabbed now (links to its pursuit on Downloads).
- **Armed** — a future release that *will* auto-grab when it drops. This only appears when a
  grab will genuinely fire (acquisition configured and auto-grab on for that title).
- **Upcoming** — tracked and dated, but won't auto-grab.
- **Theatrical** — a film's cinema date, shown for information only; never grabbed.
- Titles with no announced date sit in a separate "nothing scheduled yet" group.

## How auto-grab works

When a tracked release airs and you don't have it, the app records a durable **want**.
Periodically a planner sweeps the open wants, batches what's due for each title, and — if that
title's auto-grab mode allows it — turns them into a plan that becomes a
[pursuit](/guide/pursuits). The mode has three settings, global with per-title overrides:
**all releases** (grab automatically), **ask** (park a draft for you to approve), or **off**
(track for information only). Wants persist through TMDB calendar changes and transient
outages — a missed sweep just gets caught by the next one.

> [!TIP]
> The patience window is the feature to know. If you want 4K but only a 1080p release has
> appeared, tracking will *wait* — for a configurable window (48 hours by default) it insists
> on your top quality, and only when that runs out does it fall back to your floor and grab
> what's there. Set it per title, and you stop getting a 1080p grab an hour before the 4K
> release lands. You can also flip a title's auto-grab on or off from its detail panel without
> leaving the page.

In short: tracking watches TMDB for releases of titles you own or follow, Upcoming forecasts
them with honest per-entry status, and auto-grab turns aired releases into pursuits — with a
patience window that waits for the quality you actually want before settling.
