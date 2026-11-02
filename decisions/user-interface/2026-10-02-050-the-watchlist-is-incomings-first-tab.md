---
status: accepted
date: 2026-10-02
amended: 2026-11-02
---
# The watchlist is Incoming's first tab, and the schedule is on its rows

> **Amendment 2026-11-02 (campaign `discovery.md`, M14 cutover) — superseded in the main.** The Watchlist tab is gone with Incoming (UIDR-015, amended): the watchlist's home is **Discovery**, by release stage — the **Out Now** shelf and the **In Theaters · Coming Up** grouped row (`PosterRow.grouped_poster_row/1`, `TMDB.ReleaseStages`), every listed title once, a poster tile with its marker chip and date chip (campaign decisions 13–15). Rules 1–4 are retired: there is no row, no next-release column and no In pursuit pill; a tracked title's next release and its status are read in its title detail (`Components.ReleaseTracking.ReleaseDates`), reached from the tile, and the pursuit's row is on Downloads' Activity tab. `Title.Row` keeps the title, the markers, the notes and the social glyphs, as a media-search result; its next-release block, `UpcomingFeed.next_per_title/1`, `landed_per_title/1` and `Components.Incoming.StatusPill` are removed. Rule 5 stands as amended below (Home's Coming Up marquee answers *when*; Discovery's group, *what*). Rule 6 stands.
>
> **Amendment 2026-10-03 (UIDR-051).** The Discovery page named below is the Social page at `/social`.
>
> **Amendment 2026-11-01 (campaign `discovery.md`, decision 13).** Rule 5's reservation of the words *Coming up* for Home's shelf is narrowed: Discovery's Watchlist row (`PosterRow.grouped_poster_row/1`) also names its group of unreleased listed titles **Coming Up**, beside **In Theaters**, with **Out Now** a row of its own — the watchlist by release stage (`TMDB.ReleaseStages`). The two answer different questions: Home's marquee, *when* (tracked releases on a calendar); Discovery's group, *what* (every listed title still ahead). Rule 5's first sentence stands: Home's shelf is unchanged.
>
> **Amendment 2026-10-03 (owner).** Rules 2–3, two changes. A followed title's row shows the release that just landed as well as the next one still to come: a quiet line above the next release — the episode, how long ago, the Landed pill — while the feed still keeps it (seven days, `UpcomingFeed.landed_per_title/1`); the next-release rule itself stands. And the In pursuit pill is a button that switches to the Activity tab, where the pursuit's row is (no scroll); the shelf-era anchor stays retired.

Amends UIDR-015 (the Coming up tab), UIDR-035 rule 5 (three lists) and UIDR-042 rule 2 (the Follow switch's label). Campaign: `campaigns/social-and-watchlist.md`, Phase 1; plan: `docs/superpowers/plans/2026-10-02-watchlist-on-incoming.md`.

## Context and Problem Statement

The watchlist was a tab of the Discovery page and Coming up a tab of Incoming. Both listed title intents: the watchlist every one at List or above, Coming up the followed ones by date. One record, two lists on two pages — and the watchlist was reachable only while the social preference was on.

## Decision Outcome

1. **Incoming's tabs are Watchlist (default), Activity, History.** `/discovery/watchlist` is gone; the Discovery page keeps the Feed and Friends.
2. **One row per title at List or above**, the `Title.Row`: poster, markers, social glyphs. A followed title's row carries its **next release** at the right — date label, the release, and its status in the `StatusPill` vocabulary; an in-pursuit pill carries the percent; the pursuit row itself is on the Activity tab (UIDR-015 §6's anchor is retired with the shelf).
3. **Order:** titles with a dated next release nearest first, then followed titles TMDB has not dated, then listed-only titles newest first. A title's next release is its next one still to come: a release the app is still searching for counts as still to come; a release already in the library leads the row, as Landed, only while nothing else is scheduled for the title.
4. **No cap.** The list is the list.
5. **Home's Coming up shelf is unchanged.** The words *Coming up* name that shelf only.
6. **The Follow switch reads *Track release dates*.** It no longer names a tab.

### Consequences

* Good, because the watchlist is always reachable and one record is listed once.
* Bad, because a long watchlist puts listed-only titles below the fold; the omnibox above is the way to a specific title.
