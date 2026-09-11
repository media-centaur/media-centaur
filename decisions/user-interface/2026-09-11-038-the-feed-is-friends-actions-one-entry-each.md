---
status: accepted
date: 2026-09-11
---
# The Feed is friends' actions, one entry each

Supersedes the feed half of
[UIDR-031](2026-09-06-031-friends-carry-shelves-feed-is-recommendations.md);
its Friends card stands. Amends [UIDR-036](2026-09-07-036-one-control-per-title.md)
(the row's Ignore shortcut and the List bookmark move into the entry's
toolbar) and [UIDR-037](2026-09-08-037-friend-provenance-is-the-pennant.md)
(the feed is the one title surface without a mast). Design:
`docs/superpowers/specs/2026-09-11-discovery-feed-design.md`; mockups in
`2026-09-11-discovery-feed-mockups/` (round 2, `A-poster-left-row` chosen).

## Context and Problem Statement

UIDR-031 split the social surface into two projections: Recommendations,
one row per title, and the Friends card, one per person. Its reasoning
was that only a recommendation is a message, and that a friend's watching
and tracking are shelf state. With a small roster the Recommendations tab
was nearly empty, and the one forward-looking thing a friend does besides
recommending — putting a title on their watchlist, "I want to watch this"
— was buried as a text row on their card. The tab did not answer the
question a person opens it with: what have my friends pointed at since I
last looked.

The row itself was title-first: poster, title, then who and when as a
marker, plus a pennant mast, state markers and a synopsis. Who did what
was the smallest text on it.

## Decision Outcome

Chosen option: "a flat feed of friends' actions, one entry per action,
modelled on Bluesky's timeline", because a feed shows what changed, a
profile shows what is, and UIDR-031 already drew that line; it only
placed the wrong things on each side.

1. **Two actions, one feed.** An entry is a friend's **recommendation**
   ("recommended", with a rose heart for Love and nothing for Like) or a
   friend's **listing** ("wants to watch"). Watched actions stay on the
   Friends card. Own actions stay on the You card. Former friends' actions
   are not shown.
2. **One entry per action**, newest first, flat. A title appears as often
   as friends act on it; one friend recommending then listing a title is
   two adjacent entries. No grouping, no day dividers, no re-sorting.
3. **An entry shows three things** and the time: the friend's name, the
   action, and the title's identification — poster, name, year — plus the
   note when a recommendation has one. Reading order is name, action,
   title: the sentence is the first line. No pennants, no state markers,
   no synopsis, no type badge, no avatar.
4. **Verbs and state share a toolbar** that shows only while the entry is
   hovered or holds the cursor, in a fixed seat so hover never changes an
   entry's height. List (bookmark; "Listed" filled on your list;
   "Following" as a marker at Follow and above, per UIDR-036), Download
   (the one-click plan; "Downloading" with the hairline or "In library" as
   plain state text when it no longer applies), Ignore (the Ignored rung,
   with the Undo toast). The whole entry opens the title modal for
   everything else.
5. **Withdrawal removes the entry.** A friend deleting a recommendation,
   or dropping a title below List, takes the entry off the feed.
6. **A window, then Show older** — the History archive idiom, not the
   whole roster's history at once.
7. **The Friends card stands** as UIDR-031 wrote it, with its Tracking
   shelf renamed Wants to watch ([ADR-067](../architecture/2026-09-11-067-listing-replaces-tracking-on-the-wire.md)).

### Consequences

* Good, because the tab is worth opening with two friends: every listing
  is an entry, and a listing is the signal "someone is looking forward to
  this".
* Good, because who did what is the first line of every entry, in one
  anatomy, at roughly a hundred pixels each — thirty friends fit.
* Good, because state and verb are one control each, so the entry body
  carries no bookkeeping and the row-jumps-to-top cost of UIDR-031 is
  gone with the grouping.
* Bad, because the "Cleo agrees" signal — every friend's flag on one
  title — leaves the feed with the pennants. It stays on the title modal
  and the Watchlist row, where the title is the subject.
* Bad, because the tab renames a second time in a week (Feed →
  Recommendations → Feed). The name follows the content.
* Bad, because a friend who lists many titles produces many one-line
  entries. That is the feed working as designed; the compact line is
  what makes it tolerable.

## Anti-patterns this record names

* **Wall of watching** — watched actions never appear as a timeline.
* **Title-first row** — an entry whose first line is the title reads as a
  list annotated with names.
* **Grouped rows** — one row per title, re-sorted on the next friend.
* **State as decoration** — badges, chips, markers or pennants on the
  entry body. State appears only as the toolbar's own state.
* **Social-network chrome** — avatars, handles, replies, reposts, counts.
* **Hover jump** — a toolbar that changes the entry's height.
* **Day dividers** — the sort order is the time axis.
