# Movie-First Collection Modal — Design Plan

## Problem Statement

Collection member movies are full movies in the library — own cast, synopsis,
artwork, duration — but the collection modal presented them as dense episode-style
rows where clicking immediately started playback. There was no way to examine a
member (cast, synopsis, facets) before committing to play it, and the collection
Cast view blended people across the whole saga.

## Design Objectives

- **Movie-first**: a collection member gets the exact same detail experience as a
  standalone movie. The collection is a grouping of destinations, not a series.
- **One component family, zero forks**: the selected member's panel is the
  standalone-movie panel, parameterized — never a parallel copy. No duplicated
  modal config, layout, or logic that can drift. Where the collection case needs
  something extra (eyebrow, rail), it composes onto the shared panel.
- **Deliberate playback**: selecting is never playing. Play is the only playback
  affordance.
- **No new navigation level**: one surface, one dismissal (UIDR-013 unchanged).
- **Fast happy path preserved**: opens on the resume target; open → Play is two
  clicks, as today.

## User-Facing Behavior

Opening a collection shows the resume-target movie's full cinematic panel:
backdrop, title with saga eyebrow ("‹Collection› · Part N of M"), tagline, facet
strip, progress line, and the Play / Cast / Manage row. Below the action row, a
poster rail shows every member as a 2:3 poster tile with per-member state:
watched check, progress underline on the in-progress movie, dashed muted tile
with a date pill for each announced-but-unreleased part, and a trailing ghost
tile for collection-level extras. The rail's label line carries the saga
progress note ("1 of 3 watched · next: ‹part› ‹year›").

Picking a poster re-anchors the panel — backdrop crossfades to that movie's art
(UIDR-021 ladder, collection art as fallback), title/facets/synopsis/play-label
swap, Cast now means that movie's cast. Play label follows the selected movie's
state: Resume / Play / Watch again. The watched toggle acts on the selected
movie. Manage stays collection-scoped. Selection is reflected in the URL so a
refresh restores it; a fresh open returns to the resume target.

Gamepad/keyboard: DOWN from the action row enters the rail at the selected tile;
LEFT/RIGHT walks it; A selects; B/Esc closes the modal from anywhere.

## Acceptance Criteria

- [ ] Opening a collection shows the resume-target movie's full detail panel;
      Play starts it without touching the rail
- [ ] Selecting another poster swaps backdrop/title/facets/synopsis/play-label/
      cast without starting playback
- [ ] Play label per selected movie: Resume (partial) / Play (unwatched) /
      Watch again (watched)
- [ ] Rail shows per-member state at a glance: watched check, progress
      underline, muted upcoming tile with date
- [ ] Upcoming and extras tiles render only when such items exist; a one-movie
      collection still renders correctly
- [ ] A member without poster art gets a legible fallback tile (title text on a
      neutral background)
- [ ] Spoiler-free mode blurs the synopsis of an unwatched selected movie
- [ ] Gamepad: rail reachable from the action row, selected tile is the entry
      point, B closes the modal from anywhere
- [ ] Storage offline: Play is replaced by the Offline pill; the rail stays
      browsable
- [ ] Refresh restores the picked movie; a fresh open lands on the resume target

## Anti-patterns

- **Drill-in stack**: no collection-page → movie-page navigation level; one
  surface, one dismissal.
- **Rail as play row**: a rail click must never start playback (the retired row
  behavior).
- **Chrome band on the seam**: the rail is content (posters), not a tab strip;
  the reverted tab-strip experiment stays reverted.
- **Blended saga cast**: Cast never merges members.
- **Forked panel**: a collection-specific copy of the movie panel's layout or
  logic is a defect, not a shortcut.

## Deferred

- Watched toggle directly on rail tiles (hover/focus affordance)
- Per-movie Manage (cog remains collection-scoped)
- Runtime captions on rail tiles

## Decisions

See [UIDR-023](../../decisions/user-interface/2026-08-13-023-movie-first-collection-modal.md).
Related: UIDR-019 (two-region modal), UIDR-021 (artwork ladder), UIDR-013
(dismissal modes), ADR-047 (playable items), ADR-050 (presentable resolver).
