---
status: accepted
date: 2026-10-02
amended: 2026-10-03
---
# The watchlist is Incoming's first tab, and the schedule is on its rows

> **Amendment 2026-10-03 (UIDR-051).** The Discovery page named below is the Social page at `/social`.

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
