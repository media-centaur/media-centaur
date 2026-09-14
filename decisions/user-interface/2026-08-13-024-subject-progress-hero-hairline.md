---
status: accepted
date: 2026-08-13
---
# Subject progress lives in the hero hairline, from one shared component

## Context and Problem Statement

The detail modal's pinned block crammed the metadata row, a thin progress bar with "29m remaining", and the action row into one narrow column. TV series already carried their watched fraction as the orientation hairline on the hero window's bottom edge; movies and collection members were the exception keeping a card-row bar.

## Decision Outcome

1. **The hairline always shows the subject's watched fraction.** TV: the series. Movie and collection member: that movie. One meaning, no per-type branching; the rail tile underline keeps per-member state for the set.
2. **The PlayCard's percent/remaining row is retired from its contract**, attrs removed, not hidden. No progress gauge or copy renders in the pinned block's card area.
3. **Remaining time is the metadata line's final item** ("29m left", in the app-wide duration format), tinted toward primary as the hairline's caption. It displaces "Released" whenever present.
4. **One component everywhere.** `ProgressHairline` is rendered by every CinematicShell tenant that shows subject progress, never re-implemented locally; the metadata items are composed in one builder for every subject shape. The `aria` label names the subject ("Movie progress" / "Series progress").

The Continue Watching playback card keeps its own bar; this record governs the detail modal.

### Consequences

* A member's hairline shows that movie's fraction where a series shows the whole series: the same pixel, different scopes.
