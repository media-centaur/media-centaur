---
status: decided, unplanned
started: 2026-09-07
last_updated: 2026-09-07
---
# Tracking is a person's act

## Goal

A tracked title exists only because a person turned tracking on, and turning
it off deletes it. The app never starts tracking a title on its own.

## Status

Decided 2026-09-07. Not planned. No code.

## Decisions made

* `2026-09-07` — **Tracking starts only by a person's act.** No code path
  creates a tracked title as a side effect of something else. As of this
  date four do: the gap handoff (a plan that found some of its units), the
  "Download all" scope on a title, auto-tracking on library import, and the
  lower-quality acceptance on a plan board. Each stops, or becomes an
  explicit question.
* `2026-09-07` — **Off deletes.** Setting a title's tracking mode to Off
  deletes the tracked title and everything under it: calendar rows, wants,
  events. The row kept as a "durable disarm" existed only to veto the
  automatic paths above; with those gone it has no job. This supersedes that
  part of [ADR-065](../decisions/architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md)
  and its "library reason" default. The decision record is written when this
  is planned.

## Open

Not decided. Recorded so planning starts from the question, not from a
guess.

* Whether the gap handoff asks ("keep searching for the N missing
  episodes?") or simply stops at what the plan found.
* What happens to the titles already auto-tracked when this ships: kept as
  they are, or removed.

## Next steps

1. Plan it, in its own session.

## Completion criteria

* No code path creates a tracked title without a person asking for it.
* Off deletes the tracked title and its rows.
* ADR-065 is superseded where it conflicts.
