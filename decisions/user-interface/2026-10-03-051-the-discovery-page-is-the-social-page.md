---
status: accepted
date: 2026-10-03
amended: 2026-10-03
---
# The Discovery page is the Social page

> **Amendment 2026-10-03.** `show_social` is on by default and its switch is **Show Social in the sidebar** under Settings → Social, not under Preferences: the preference belongs with the identity, relays and sharing it gates, and the page is no longer treated as an opt-in preview. Point 1's "default off" and point 3's "switched on again" describe the morning of 2026-10-03 only.

Amends UIDR-010 (the Watch group's pages) and the records that name the page: UIDR-038, UIDR-043, UIDR-045, UIDR-046, UIDR-050.

## Context and Problem Statement

The Discovery page held three tabs: Feed, Watchlist, Friends. UIDR-050 moved the watchlist to Incoming. What is left — friends' reviews and listings, and the roster — is the social subsystem's one page, and "Discovery" no longer says what it is. The `show_discovery` preference gated the page and the Review control.

## Decision Outcome

1. **The page is Social**, at `/social` (Feed, the default) and `/social/friends`. Sidebar entry **Social** (`hero-users`), gated by **Social** under Settings → Preferences (`show_social`, default off — the page is still an early preview).
2. **Code and surface agree** (ADR-075 rule 3): `SocialLive`, `Components.Social.*`, the `social` page behaviour and nav layout, the `.social-*` classes.
3. **No data migration.** `show_discovery` is not read any more; the preference resets to off and is switched on again by the person who wants the page.
4. **The subsystem keeps its name.** `MediaCentaur.Social` and the Social page are one context's two faces; the shared word is correct, not a collision.

### Consequences

* Good, because the sidebar names what the page is.
* Bad, because anyone who had turned Discovery on turns Social on once.
