---
status: accepted
date: 2026-08-14
---
# Re-selecting the current page in the main nav scrolls to the top

## Context and Problem Statement

Clicking the sidebar link for the page already on screen remounted the page and reset its state while the scroll position survived. A nav re-click universally means "back to the top".

## Decision Outcome

1. Re-selecting the current page scrolls the window to the top and never remounts. `assets/js/nav_reselect.js` intercepts sidebar clicks whose destination pathname equals the current one and issues a smooth scroll instead of LiveView navigation.
2. When the current URL carries a query string the bare link does not (a filtered view), the navigation proceeds; the scroll-to-top still applies.
3. The rule keys on pathname, so every sidebar entry inherits it, including entries whose target varies.

### Consequences

* A nav link no longer resets the page when the URL matches exactly; a filtered URL still resets.
