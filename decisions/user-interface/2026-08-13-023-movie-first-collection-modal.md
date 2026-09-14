---
status: accepted
date: 2026-08-13
amended: 2026-09-14
---
# Movie-first collection modal with a poster-rail picker

## Context and Problem Statement

Collection members are full movies in the data model, but the collection modal rendered them as episode-style rows where a click started playback, with no way to see a member's cast or synopsis first. A drill-in (collection surface → member surface) would add a navigation level and a third dismissal meaning; the chosen shape deletes the level instead.

## Decision Outcome

1. **The modal is the selected member movie's panel**: the standalone-movie cinematic panel for whichever member is selected, from the same component family, parameterised and never forked. Cast is the selected movie's cast; the UIDR-021 artwork ladder applies per member, falling back to collection art.
2. **Selection lives in a poster rail** (`CollectionRail`) below the action row: one 2:3 poster per member, a dashed tile with a date pill per announced-but-unreleased part (not selectable), and a label line with the saga progress ("1 of 3 watched"). The rail names the collection, so there is no saga eyebrow over the title and no "N movies" count in the metadata row.
3. **Selecting never plays.** A rail pick re-anchors the panel; the backdrop swap is an instant cut (the pinned-block replica must stay byte-identical). Play is the only way to start playback.
4. **The modal opens on the resume target**, so open → Play stays two clicks; the selection rides the URL and a fresh open returns to the resume target.
5. **Dismissal is unchanged** (UIDR-013): one surface, no back level. Manage stays collection-scoped; the watched toggle acts on the selected movie.
6. **Collection-level extras render as the standard `ExtrasSection`** in the body, the idiom a bare movie with bonus content uses.
7. **The member is the subject** (amended 2026-09-14, UIDR-043): a collection is addressed through its selected member — `?title=movie-<member tmdb id>` — and `?movie=` retires. A rail tile is an entity emitter like any card (`select_entity`), and because another member of the open collection is the same document, a pick keeps the modal's state and sub-view. A collection has no tracking block of its own; the bookmark and the switches act on the member.

### Consequences

* Marking a movie watched requires selecting it first.
* Per-member runtime and year are no longer scannable as a column.
