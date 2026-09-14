---
status: accepted
date: 2026-08-19
---
# Back enters the main menu; left stays in the page

Supersedes UIDR-007 ("Left wall enters sidebar", retired).

## Context and Problem Statement

UIDR-007 made Left at the left edge of any content row enter the sidebar, so one key meant both "move one item left" and, at an edge the user cannot see from the keyboard, "leave the page for the main menu". Overshooting a horizontal row silently changed the focused page context. BACK (Escape, gamepad B) was a no-op in every content context.

## Decision Outcome

1. BACK's containment peeling (UIDR-019) gains a final rung: after overlay regions, sub-focus, overlay dismissal, and primary-menu exit, a content context enters the sidebar. Pressing BACK again from the sidebar returns to where you were.
2. No zone layout declares a `left: ["sidebar"]` edge. Left and right are lateral movement within the page only; genuine lateral edges between content zones are unaffected.
3. Pages without a sidebar (the setup tour) declare no sidebar node in their layout, so BACK stays a no-op there. The node's presence in the nav graph is the capability check.
4. The sidebar collapse toggle is a nav item with deferred activation: reachable by cursor, toggled only by explicit SELECT.

### Consequences

* Keyboard users lose the spatial "the sidebar is to the left" gesture and must learn Escape or B; the gamepad hint bar advertises B → Menu in content contexts.
