---
status: accepted
date: 2026-09-11
amended: 2026-09-12
---
# Add to watchlist first, then the tracking controls

Amends UIDR-036: the bookmark is the listing verb on every title surface, and the tracking controls appear only once it has been used. UIDR-040 (2026-09-12) is folded in.

## Context and Problem Statement

Adding a title to the watchlist and enabling release tracking are two acts, in that order, and the second happens only on the watchlist. The seven-way control was mounted on every title view, so a search result or a Feed entry reached Grab in one click without the title ever being listed. A rule by opening surface was considered and rejected: the title view would need to know which page opened it.

## Decision Outcome

The form follows the rung, wherever the title was opened.

1. **A title not on the list offers one verb: the bookmark** (`Components.Title.WatchlistToggle`), beside Download. Outline off the list, solid on it; accessible name *Add to watchlist*. A click sets List for a title with no record or an ignored one, and Off for a title still at List. At Follow and above it is a marker with no click: Off lives in the tracking controls, which state that they delete. The tracking block is empty for a title with no record; an ignored title's block says the Feed hides it.
2. **A title on the list shows the tracking controls** of UIDR-036. Off empties the bookmark and the block again. Review (the pencil-square icon, UIDR-040) sits beside the bookmark.
3. **The rule is the rung.** From a search result: open, bookmark, then the controls appear. From the Watchlist tab or Coming up the title is by definition listed. In the Library an owned series nobody listed offers the bookmark first.
4. **A download never moves a rung.** No download scope, picker checkbox, or handoff from a plan's missing units. `ReleaseTracking.set_rung/3` stays the one write path.
5. **Ignore for an unlisted title lives on the Feed entry only** (UIDR-038).

*Tracking controls* and *Add to watchlist* are the user-facing names; "ladder" and "rung" name nothing user-facing.

### Consequences

* Raising an unlisted title to Grab is two clicks where it was one. That is the point.
