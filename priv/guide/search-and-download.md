---
title: Search & download
part: Acquisition
slug: search-and-download
order: 12
---
Acquisition is optional. With an indexer manager (Prowlarr) and a download client configured,
Media Centaur can search for releases and grab them; until then the Downloads page stays
hidden. Prowlarr searches across your indexers; the download client downloads (qBittorrent has
the fullest support). Everything happens on the Downloads page (`/download`).

## The page

| Zone | What's there |
|---|---|
| Search box | Media mode (search TMDB for a title) or release mode (type release names, with `Show S0{1,2}` brace expansion) |
| Draft plans | Proposed plans awaiting your approval; durable across reloads |
| Active pursuits | Live downloads, with progress |
| History | Finished, failed, and cancelled pursuits |
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
