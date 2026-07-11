---
title: Search & download
part: Acquisition
slug: search-and-download
order: 14
---
Acquisition is optional. With an indexer manager (Prowlarr) and a download client configured,
Media Centaur can search for releases and grab them; until then the Incoming page shows only
its [tracking side](/guide/release-tracking-and-upcoming). Prowlarr searches across your
indexers; the download client downloads (qBittorrent has the fullest support). Everything
happens on the Incoming page (`/incoming`).

## The page

| Zone | What's there |
|---|---|
| Search | Media mode (search TMDB for a title) or release mode (type release names, with `Show S0{1,2}` brace expansion) |
| Coming up | Tracked releases as a shelf — see [release tracking](/guide/release-tracking-and-upcoming) |
| Draft plans | Proposed plans awaiting your approval; durable across reloads |
| In flight | Live downloads, with progress |
| Recently landed | The newest outcomes; **View all** expands it into the full archive with failed/cancelled/succeeded filters and a title search |
| Other downloads | Client torrents that match no tracked pursuit (orphans) |

## The flow

1. Search TMDB for a title and pick it.
2. The app builds a **plan** — which releases to grab to cover what you asked for.
3. Review it: swap any unit for an alternative, remove a release and re-solve, heed the
   overlap warning if a swap would download something twice.
4. Approve. Each grab becomes a [pursuit](/guide/pursuits) in Active pursuits.

## How the plan is built

The planner descends a coverage ladder — **series pack → season packs → individual
episodes** — and at each rung searches only for what the rungs above left uncovered, so a
show with season packs costs a few dozen indexer searches, not hundreds. It prefers fewer,
broader releases (a season pack over twelve singles) and stays within the quality bounds you
set, never fragmenting an acceptable pack just to upgrade one episode.

> [!TIP]
> Plans are durable — start one, walk away, finish it later. And when a plan can't cover
> everything, one button hands the missing episodes to
> [release tracking](/guide/release-tracking-and-upcoming) so they're grabbed automatically
> when they appear, instead of you checking back.
