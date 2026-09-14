---
status: accepted
date: 2026-07-11
amended: 2026-08-02
---
# Merge Upcoming and Downloads into one "Incoming" page

## Context and Problem Statement

Upcoming (`/upcoming`) and Downloads (`/download`) were two thin, rarely visited pages telling one story split at release day: tracked release → pursuit and torrent → history → in library. Both were visited with the same intent, growing the collection. Of three mocked paradigms (time spine, split canvas, intent-first hub) the hub won: the merge's justification is an intent statement.

## Decision Outcome

1. The page is **Incoming** at `/incoming`, in the Watch group; `/upcoming` and `/download` are gone.
2. **Hero omnibox**, always present: "What do you want to watch?", TMDB title search or direct release search. While a search owns the page the sections recede behind the flat results.
3. **Coming up**: the schedule, one compact date-led row per tracked title in nearness order, statuses through the shared `StatusPill` vocabulary, overflow growing in place ("Show all N"). An empty forecast renders nothing.
4. **In flight**: draft plans, every live pursuit paired with its torrent rows, and client downloads matching no pursuit. Operational chrome appears only here.
5. **History**: the one history surface, an archive with lifecycle chips and title search, a bounded window plus "Show earlier", and the calm storage foot line.
6. A Coming up row and its torrent row are two zoom levels of one object: the row's "In pursuit · N%" pill anchors to `#pursuit-<id>`.
7. Without acquisition capability the page renders forecast-only: no tab bar, no in-flight or history content, nothing implying grabbing is possible.

Amended 2026-08-02: the sections below the hero became three zone tabs, **Coming up** (default), **Activity** (drafts, in flight, other downloads) and **History**.

### Consequences

* Time is a label on the rows, not the skeleton; there is no month-shaped view.
* The same pursuit appears twice by design; the shared pill vocabulary must hold.
