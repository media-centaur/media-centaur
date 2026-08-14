---
status: accepted
date: 2026-08-14
---
# Re-selecting the current page in the main nav scrolls to the top

## Context and Problem Statement

Clicking a sidebar link for the page already on screen did nothing useful:
LiveView performed a full live navigation to the same route, remounting the
page and resetting its state, while the scroll position survived the patch.
The reader who scrolled deep into Home and clicked "Home" expected the
universal idiom — nav re-click means "take me back to the top of this page"
— and instead got a flash and no movement.

## Decision Outcome

**Re-selecting the current page in the sidebar scrolls the page to the top.
It never remounts the page.** Implemented once, at the sidebar seam
(`assets/js/nav_reselect.js`, installed from `app.js`): a capture-phase
click listener intercepts sidebar links whose destination pathname equals
the current one, suppresses LiveView's link handling, and issues a smooth
`window.scrollTo(0)`.

* When the current URL carries a query string the bare nav link doesn't
  (a filtered view such as `/incoming?q=…`), the navigation is real and
  proceeds — but the scroll-to-top still applies, so the gesture's outcome
  is the same from the reader's seat.
* The rule keys on pathname, so it covers every sidebar entry uniformly,
  including ones whose target varies (Review → `/review` or `/reconcile`).
* This is a principle, not a page feature: any future main-nav surface
  inherits the same contract — re-selecting where you are returns you to
  the top, never reloads.

### Consequences

* Good, because the nav gains the behaviour every reader already expects
  from browsers, mobile apps, and TV shells alike.
* Good, because the pointless same-page remount (state reset, image
  re-decode, hero repaint) disappears — the click is now cheaper as well
  as more useful.
* Neutral, because split-pane pages whose window doesn't scroll (Review,
  Reconcile) see a no-op scroll; nothing moves because nothing was
  scrolled.
* Bad, because anyone who relied on the nav link as a "reset this page"
  button loses the remount when the URL matches exactly; a filtered URL
  still resets, and a reload remains available.
