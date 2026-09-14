---
status: accepted
date: 2026-09-08
amended: 2026-09-12
---
# Friend provenance is the pennant, on every title surface

Extends UIDR-035 and UIDR-038; UIDR-040 (2026-09-12) is folded in.

## Context and Problem Statement

The pennant said who recommended a title, on every surface. Every other friend act showed only as a provenance line under the title detail's hero, only when the modal was opened from that activity, and from the watchlist it narrated the reader's own broadcast.

## Decision Outcome

1. **Six flags, in mast order: love, like, dislike, reviewed, watched, listing** (`Components.Title.Pennant`). A review flies its sentiment, or the reviewed flag (speech bubble) when it gives none; love keeps the rose fill. A friend's act of any kind flies on every title surface, however opened.
2. **One feed behind the mast.** `Activities.friend_activity_for/1` returns every live act by a current friend on the given titles, plus the reader's own reviews. Own reviews fly ("You"); own watching and listing never do.
3. **The Feed entry is the one title surface without a mast** (UIDR-038).
4. **The provenance line is gone.** A friend's review text leads the body attributed by nickname.
5. **Delete survives only on an own activity the modal was opened from** (the You card).

### Consequences

* The watched pennant carries no episode; the Friends card keeps that detail.
