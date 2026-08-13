---
status: accepted
date: 2026-08-13
---
# Movie-first collection modal with a poster-rail picker

## Context and Problem Statement

Collection members are full movies in the data model — own cast, crew, synopsis,
artwork, duration — but the collection modal rendered them as episode-style rows
where a click immediately started playback. There was no way to look at a member
movie (its cast, its synopsis at full size, its facets) before committing to
playing it, and the modal's Cast view blended everyone across the saga. A member
movie was first-class data presented as a second-class row.

Two shapes were considered for fixing it. A drill-in (collection surface → member
movie surface) adds a navigation level inside the modal, with a Back state that
UIDR-013's dismissal modes would have to grow a third meaning for. The chosen
shape deletes the level instead: there is no collection surface.

## Decision Outcome

Chosen option: "the modal is the selected member movie's panel, with a poster-rail
picker", because it removes a surface rather than adding a level, and the movie
idiom already does everything a member needs.

* The collection modal renders the **standalone-movie cinematic panel** for
  whichever member is selected — backdrop and title layer (with saga eyebrow
  "‹Collection› · Part N of M"), facet strip, progress line, Play/Cast/Manage
  row. Cast is always the selected movie's cast, never a saga blend. The
  UIDR-021 artwork ladder applies per selected movie, falling back to
  collection art.
* The panel for a selected member **is the same component family as the
  standalone movie panel** — one source of truth for modal config, layout, and
  logic. The collection case parameterizes it (eyebrow, rail); it never forks it.
* Selection lives in a **poster rail** below the action row: one 2:3 poster per
  member, watched check badge, progress underline on the in-progress movie,
  dashed muted tile with a date pill per announced-but-unreleased part
  (not selectable), and a trailing ghost tile for collection-level extras.
  The rail's label line carries the saga progress note ("1 of 3 watched").
* **Selecting never plays.** A rail pick re-anchors the whole panel (backdrop
  crossfade, title/facets/label swap). Play is the only way to start playback.
* The modal **opens pre-selected on the resume target** (existing ladder:
  first movie / next after last watched / partially watched), so
  open → Play stays two clicks, exactly as before. Selection is reflected in
  the modal's URL params; a fresh open returns to the resume target.
* Dismissal is unchanged (UIDR-013): B/Esc closes the modal from anywhere.
  There is no back-level because there is no second surface.
* The Manage cog stays collection-scoped (files, rematch, artwork for the
  entity). The watched toggle acts on the selected movie.

The episode-style member rows (and with them the season-list symmetry for
collections) are retired: episodes are continuations, so a series-level surface
fits TV; collection members are destinations, so each gets the movie treatment.

### Deviations settled at implementation

* **No extras rail tile.** Collection-level extras render as the
  standard `ExtrasSection` in the modal body — the same idiom as a bare
  movie with bonus content — instead of the trailing ghost tile the
  design sketched. One idiom for extras everywhere beats a second,
  rail-specific one.
* **The metadata row drops the "N movies" count** — the eyebrow's
  "Part N of M" already carries the saga extent.
* **The backdrop swap is an instant cut, not a crossfade.** The
  pinned-block illusion requires the panel backdrop and its
  orientation-backing replica to render byte-identical sources; a
  two-layer crossfade would have to keep both copies in lockstep
  mid-animation. The same-element src swap holds the old frame until
  the cached new image decodes, which reads as near-atomic. Revisit
  only if the cut feels jarring on the TV.

### Consequences

* Good, because a member movie gets the full movie idiom — cast, artwork,
  facets, deliberate playback — with zero new surface types to maintain.
* Good, because collection-level state (saga progress, announced parts, extras)
  survives on the rail without a dedicated collection view.
* Good, because dismissal semantics stay binary; no drill-in stack.
* Bad, because marking a movie watched now requires selecting it first
  (a rail-tile toggle is a deferred graft).
* Bad, because per-member metadata (runtime, year) is no longer scannable as a
  column; it appears one movie at a time in the facet strip.
* Bad, because members without poster art need a legible fallback tile.
