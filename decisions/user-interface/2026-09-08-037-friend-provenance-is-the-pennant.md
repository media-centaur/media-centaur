---
status: accepted
date: 2026-09-08
---

> **Amended 2026-09-11** by [UIDR-038](2026-09-11-038-the-feed-is-friends-actions-one-entry-each.md):
> the Feed entry is the one title surface that flies no mast — each
> friend's action is its own entry there. The tracking flag (bell)
> becomes a listing flag (bookmark) per
> [ADR-067](../architecture/2026-09-11-067-listing-replaces-tracking-on-the-wire.md).

> **Amended 2026-09-12** by [UIDR-040](2026-09-12-040-a-review-is-an-opinion-of-any-valence.md):
> six flags — love, like, dislike, reviewed, watched, listing — and the
> recommendation is a review ([ADR-068](../architecture/2026-09-12-068-review-replaces-recommendation-on-the-wire.md)).

# Friend provenance is the pennant, on every title surface

Extends [UIDR-031](2026-09-06-031-friends-carry-shelves-feed-is-recommendations.md)
and [UIDR-035](2026-09-07-035-two-title-surfaces.md).

## Context and Problem Statement

The pennant mast said who recommended a title and how much, on every
surface a title appears on. Every other kind of friend activity — a friend
watched it, a friend is tracking it — showed only as a provenance line
under the title detail's hero, worded as a feed statement ("Sample Friend
watched S02E05 · 2d ago"), and only when the modal happened to be opened
from that activity. Opened from the watchlist, the same line narrated the
person's own broadcast back to them ("You started tracking · 12s ago")
with a delete link beside it, because the host fell back to any activity
it could find for the title.

Two representations of one fact, one of them visible only by the route
taken to the modal, and one of them about the reader rather than their
friends.

## Decision Outcome

Chosen option: "the pennant carries every kind of friend activity, and
nothing else says who did what", because the mast is already on every
title surface — list rows, search results, the library detail's hero, the
title detail's hero — so widening what it carries makes friend provenance
standard everywhere at once.

1. **Four flags, in mast order: love, like, watched, tracking.** Love keeps
   the rose fill; the other three sit on the neutral tint. A friend's act
   of any kind flies on every surface the title is on, whether or not the
   modal was opened from it.

2. **One feed behind the mast.** `Activities.friend_activity_for/1` returns
   every live act by a current friend on the titles asked for, plus the
   reader's own recommendations. Own watched and tracking acts are left
   out: a pennant tells you what friends did, not what you did.

3. **The provenance line is gone.** The title detail no longer prints
   "<actor> <verb> · <when>" under its hero. The one thing a flag cannot
   hold — a friend's note — leads the body, attributed by nickname, in the
   list row's note idiom.

4. **Delete <noun> survives only on an own activity the modal was opened
   from** (the You card). A watchlist title never offers to delete a
   broadcast, because it never narrates one.

### Consequences

* Good, because who-did-what is in one place with one look, and does not
  depend on how the modal was reached.
* Good, because the title detail's body starts with the title, not with
  bookkeeping about the reader's own acts.
* Bad, because the watched pennant carries no episode: "Nick watched this"
  where the feed row says "watched S02E05". The feed keeps the episode;
  the mast states presence.
