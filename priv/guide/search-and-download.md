---
title: Search & download
part: Acquisition
slug: search-and-download
order: 14
---
Acquisition is optional. With an indexer manager (Prowlarr) and a download client configured,
Media Centaur can search for releases and grab them; until then the Incoming page shows the
search box and the [watchlist](/guide/watchlist-and-tracking) only. Prowlarr searches across your
indexers; the download client downloads (qBittorrent has the fullest support). Everything
happens on the Incoming page (`/incoming`).

## The page

The search box at the top has two modes: media (search TMDB for a title) and release (type
release names, with `Show S0{1,2}` brace expansion). Below it, three tabs:

| Tab | What's there |
|---|---|
| Watchlist | Every title you listed, one row each; a tracked one carries its next release and a status pill — see [the watchlist](/guide/watchlist-and-tracking) and [release tracking](/guide/release-tracking-and-upcoming) |
| Activity | Draft plans awaiting your approval (durable across reloads), live downloads with progress, and client torrents that match no tracked pursuit |
| History | The archive of finished downloads, with Failed / Cancelled / Succeeded filters and a title search; **Show older** walks further back |

## The flow

1. Search TMDB for a title and pick it.
2. The app builds a **plan** — which releases to grab to cover what you asked for.
3. Review it: swap any unit for an alternative, remove a release and re-solve, heed the
   overlap warning if a swap would download something twice.
4. Approve. Each grab becomes a [pursuit](/guide/pursuits) under In flight on the Activity tab.

## How the plan is built

The planner descends a coverage ladder — **series pack → season packs → individual
episodes** — and at each rung searches only for what the rungs above left uncovered, so a
show with season packs costs a few dozen indexer searches, not hundreds. It prefers fewer,
broader releases (a season pack over twelve singles) and stays within the quality bounds you
set, never fragmenting an acceptable pack just to upgrade one episode.

> [!TIP]
> Plans are durable — start one, walk away, finish it later. A plan never changes a title's
> tracking: episodes it can't find stay missing until you search again, unless the show has
> **Auto-grab** on in your [watchlist](/guide/watchlist-and-tracking), in which case
> [release tracking](/guide/release-tracking-and-upcoming) already wants them and keeps looking.
