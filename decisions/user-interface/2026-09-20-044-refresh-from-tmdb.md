---
status: accepted
date: 2026-09-20
---
# One control to ask TMDB again: Refresh from TMDB

Amends [UIDR-042](2026-09-14-042-tracking-is-the-bookmark-and-two-switches.md):
the tracking card gains one title-wide action. Companion to
[ADR-071](../architecture/2026-09-20-071-tmdb-store-one-record-per-title.md).

## Context and Problem Statement

ADR-071 made the app ask TMDB about a title only when a check is due —
the day after the title's next known date, a week after the last check,
never once the title has settled. Nothing on a title's surfaces asks
TMDB on open any more. The owner wanted one control that asks anyway,
"just in case": a date TMDB set an hour ago, a season announced this
morning, a settled film revived.

## Decision Outcome

Chosen option: one button, *Refresh from TMDB*, on the two surfaces a
title has, firing the same event with the title's ref.

1. **On the Manage toolbar for an owned title**, between *Rematch* and
   *Refresh artwork* — neutral, small, with an icon like its neighbours;
   shown only while TMDB is ready and the title has a TMDB match (the
   *Rematch* hint covers the other case).
2. **Under the tracking switches for a tracked title the library does
   not own** — quiet and extra small, the tracking card's precedent for
   a title-wide action (the lower-quality *Reset*). Shown while the
   title is at Follow or above.
3. **No confirm step.** A check costs one request and changes nothing a
   person would want to undo; the button reads *Checking…* and is
   disabled while the answer is in flight.
4. **Three outcomes, one flash each**: *Checked TMDB — nothing has
   changed.*; *Updated from TMDB.*; *TMDB didn't answer — try again
   later.* When something changed, the surfaces refresh on the change
   broadcast as they already do.

### Consequences

* Good, because a person never has to wait for a schedule they cannot
  see, and the policy stays strict everywhere else.
* Good, because both surfaces dispatch one event on one identity; the
  host has one handler.
* Bad, because on an owned title the check updates the store while the
  library's own fields still change only at import — until Phase 4 of
  `tmdb-fetch-policy` makes them projections, the flash is honest about
  the store and silent about the entity.
