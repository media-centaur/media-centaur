---
title: Search & download
part: Acquisition
slug: search-and-download
order: 12
---
Acquisition is optional. Configure an indexer manager (Prowlarr) and a download client and
Media Centaur can search for releases and grab them for you; until then, the Downloads page
stays hidden and nothing here applies. Prowlarr provides the search across your indexers;
the download client (qBittorrent has the fullest support) does the actual downloading.

Everything happens on the Downloads page (`/download`).

## From a title to a download

The usual path starts with a title, not a release. Search TMDB for what you want, pick it,
and the app builds a **plan**: a proposal of which releases to grab to cover exactly what
you asked for. You review the plan, adjust it if you like, and approve it — and each grab
becomes a [pursuit](/guide/pursuits) you can watch on the same page.

If you'd rather work at the release level, the search box has a release mode where you type
release names directly (including brace expansion like `Show S0{1,2}` to run several
searches at once) and grab individual results.

## How the plan is built

The planner is the clever part. Rather than searching for every episode, it descends a
coverage ladder — **series pack → season packs → individual episodes** — and at each rung
it only searches for what the rungs above left uncovered. A show with season packs
available costs a few dozen indexer searches, not hundreds. It also prefers fewer, broader
releases (a season pack over twelve singles) and stays within the quality bounds you set,
without ever fragmenting an acceptable pack just to upgrade one episode.

The plan board shows what each unit will be grabbed from, narrates what it's searching, and
lets you swap any unit for an alternative or remove a release and re-solve without it. If a
swap would download something twice (an episode that a pack already covers), it warns you.

> [!TIP]
> Plans are durable. You can start one, walk away, and come back to it later — it survives a
> reload as a draft. And when a plan can't cover everything, one button hands the missing
> episodes to [release tracking](/guide/release-tracking-and-upcoming) so they're grabbed
> automatically when they appear, instead of you checking back.

## When something doesn't match

The "Other downloads" section lists torrents in your client that don't belong to any tracked
pursuit — grabbed outside the app, or left over from old pursuits. Release-mode searches
that time out get per-term retry buttons. None of this blocks the rest of the page.

In short: search a title, let the planner work out the fewest releases that cover it
(descending only for what's missing and staying within your quality bounds), approve, and
each grab becomes a pursuit — with anything it can't cover handed off to release tracking.
