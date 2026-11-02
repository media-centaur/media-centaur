---
status: accepted
date: 2026-11-02
---
# Pages are stages: choose, get, watch

Campaign `campaigns/discovery.md` (M5, the core idea; M14, the cutover). Amends UIDR-010 (the sidebar's Watch group), UIDR-014 (the omnibox), UIDR-015 (Incoming) and UIDR-050 (the Watchlist tab), each with a dated amendment of its own.

## Context and Problem Statement

Home and Library answered "what do I own"; Incoming's Watchlist tab answered "what do I want, and when"; media search answered "find this title"; Social answered "what did my friends think". Nothing answered "what is out there that I would want", and the download page had grown a watchlist and a title search beside its plans and pursuits — three concerns on one page, with the watchlist reachable only there.

## Decision Outcome

A title's life in the app has three stages, and the Watch group's assembled pages are those stages:

1. **Choose — Discovery** (`/discovery`). An optional feature (ADR-081), on by default; off, an install has no page, no entry and no shelf refresh, and the bookmark on title pages is the watchlist's one surface. The page for titles you do not own yet, built like Home: media search at the top, a hero from the New Releases shelf, then shelves — Out Now, New Releases, Reviewed by Friends, the Watchlist grouped row (In Theaters · Coming Up). The watchlist lives here, by release stage; so does finding a title by name. Every tile opens the title detail, where a title is listed or downloaded.
2. **Get — Downloads** (`/downloads`). Release search as its own field, download plans, the pursuits in flight and the history of what landed, under two tabs, Activity and History. Nothing on it is about choosing a title. Without Prowlarr it renders its diagnosed empty state (UIDR-034) under the sidebar's unconditional entry.
3. **Watch — Home** (`/`). What you own: the hero, Continue Watching, Recently Added, and Coming Up — the tracked releases landing soon, which answers *when* (UIDR-050 rule 5); a tile without a library entity opens the title in place, and *See all* goes to Discovery.

**Library, Social and History are side views**: the catalog, the people, the record. They are not stages and do not change.

The Watch group reads in stage order with the side views between: **Home, Library, Discovery, Downloads, Social, Apps** (UIDR-010 amended). Each assembled page composes from the same kit (`HeroCard`, `ShelfHead`, `PosterRow`, `ScrollRow`) and holds the TV performance floor (UIDR-056).

**One owner per fact, one surface per act.** Discovery owns no state: each shelf reads one context (`NewReleases`, `Watchlist` through `TMDB.ReleaseStages`, `Activities`). A verb — list, download, ignore — is the title detail host's, wherever the tile is. A move between stages removes from the old page what it adds to the new one, in the same release; the cutover was one such move (`/incoming` is gone with no redirect, the repo keeping no compatibility paths).

### Consequences

* Good, because a question has one page: what is out there (Discovery), what is being fetched (Downloads), what to watch now (Home).
* Good, because the download page is download management alone, and a watchlist no longer needs an indexer to be worth opening.
* Bad, because the arc split one page into two and renamed a route; links and bookmarks to `/incoming` broke on purpose.
* Bad, because the stage model asks of every new surface which stage it serves before it is built; a surface that serves two is a sign the design is not done.
