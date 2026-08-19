---
status: accepted
date: 2026-08-19
---
# Back enters the main menu; left stays in the page

Supersedes UIDR-007 ("Left wall enters sidebar", retired).

## Context and Problem Statement

UIDR-007 made Left at the left edge of any content row enter the sidebar. In
practice the rule overloaded one key with two meanings: Left was both "move
one item left" and — at an edge the user can't see from the keyboard — "leave
the page for the main menu". Overshooting a horizontal row silently changed
the focused page context, and the sidebar was reachable by a different
gesture depending on which zone the cursor happened to be in. Meanwhile BACK
(Escape / gamepad B) was a no-op in every content context, wasting the one
button whose universal meaning is "step out one layer".

## Decision Outcome

Chosen option: BACK enters the main menu; Left never leaves the page.

* BACK's containment peeling gains a final rung: after overlay regions,
  sub-focus, overlay dismissal, and primary-menu exit, a content context
  enters the sidebar. One button steps out of anything; pressing it again
  from the sidebar returns to where you were.
* No zone layout declares a `left: ["sidebar"]` edge. Left/right are lateral
  movement within the page only. Genuine lateral edges between content zones
  (settings grid → sections, guide outline → chapters) are unaffected.
* Pages without a sidebar (the setup tour) declare no sidebar node in their
  layout, so BACK stays a no-op there — the node's presence in the nav graph
  is the capability check.
* The sidebar collapse toggle is a nav item with deferred activation:
  reachable by cursor, toggled only by explicit SELECT (activate-on-focus
  would otherwise flip the rail in passing).

### Consequences

* Good, because one gesture reaches the main menu from anywhere, at any
  depth, on every page — no edge-hunting.
* Good, because Left at a wall is now inert: no more accidental page-context
  changes from holding a direction.
* Bad, because keyboard users lose the spatial "the sidebar is physically to
  the left" gesture and must learn Escape/B instead; the gamepad hint bar
  advertises B → Menu in content contexts to compensate.
