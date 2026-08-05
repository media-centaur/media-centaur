---
status: accepted
date: 2026-06-09
---
# Composite pursuits — units carry the attempt thread

## Context and Problem Statement

A pursuit ([ADR-039](2026-05-07-039-acquisition-pursuits.md)) is one
acquisition goal that may span multiple target attempts. The aggregate
assumes **one pursuit = one wanted thing** (one episode, one movie, one
query): the per-attempt thread — `current_target_id`,
`tried_release_guids`, `attempt_count`, `awaiting_decision_at`, the
stall / zero-seeder observations — lives directly on the pursuit row,
and idempotency is key-equality on the TMDB tuple
`(tmdb_id, tmdb_type, season_number, episode_number)`.

The media-search campaign (`campaigns/media-search-tmdb-acquisition.md`,
completed and removed — see git history)
requires pursuits that cover **many wanted things at once**: a
brace-expanded file search (`Sample Show S01E{01-10}`) should be one
pursuit with ten wanted units, and a future TMDB media search will
submit whole seasons. Three pressures break the one-thing assumption:

1. **Progress must be unit-based.** "7 of 10 episodes landed" cannot be
   derived from a model whose only counters describe a single attempt
   thread.
2. **One release can cover many units.** Phase 2 introduces season
   packs: one grab attempt satisfies ten episodes. If attempts are
   modelled per-unit, a pack is unrepresentable; if progress is counted
   per-attempt, a failed pack looks like one failure instead of ten
   missing episodes.
3. **Idempotency by key equality stops working.** A composite parent
   has no single episode tuple. The useful invariant is *no two active
   pursuers may claim the same unit of the same title* — an overlap
   check, not a key match.

## Decision Outcome

Chosen option: **grow the existing `Pursuit` into a composite by
introducing a `Unit` child entity that carries the attempt thread**,
because it keeps one aggregate (no parallel system), reuses today's
battle-tested thread semantics unchanged (they just move down one
level), and makes unit-based progress and pack coverage structural
rather than computed workarounds.

### Vocabulary (from the campaign — load-bearing)

* **Unit** — one wanted thing (an episode, a movie, or one expanded
  query). Targeting produces a set of units.
* **Candidate** — a known release covering ≥1 units (corpus entry).
* **Assignment** — a plan mapping each covered unit to one candidate.
* **Leaf / target** — one grab attempt of one release. **Per-release,
  not per-unit.**

### Shape

```
Pursuit (parent: goal, recipe, title, origin, criteria, outcome state)
  └── Unit (wanted thing: query/identity, thread state)   [delete_all]
        ↑ covered by
Target (leaf: one grab attempt of one release) ── TargetUnit join ──┘
```

* **`acquisition_pursuit_units`** — one row per wanted thing. Carries
  the entire attempt thread moved off the pursuit: `state`,
  `current_target_id`, `tried_release_guids`, `attempt_count`,
  `awaiting_decision_at`, `stall_first_seen_at`,
  `zero_seeders_first_seen_at`, `last_queue_state`,
  `last_queue_health`, plus `query` (the concrete search query for this
  unit), `label` (display), and `position` (stable ordering). The
  **unit state machine is exactly the old pursuit state machine**:
  `active → satisfied | exhausted | cancelled`, with
  `awaiting_decision_at` orthogonal.
* **`acquisition_target_units`** — join table; which units a target's
  release covers. Phase 1 always writes exactly one row per target;
  Phase 2 packs write many. This is deliberately a join (not a
  `unit_id` FK on targets) so pack coverage is a data change, not a
  schema retrofit.
* **Pursuit** keeps the goal: recipe fields, `title`, `origin`,
  `criteria`, timestamps — and an **outcome state** derived from its
  units.

### Parent state = fold over unit states

Stored (UI filters and indexes need it), reconciled transactionally by
every unit-transition command:

* any unit `active` → pursuit `active`
* all units `satisfied` → `satisfied`
* terminal with ≥1 `satisfied` → **`partial`** (new state)
* terminal, none satisfied, ≥1 `exhausted` → `exhausted`
* terminal, none satisfied, all `cancelled` → `cancelled`

`partial` buckets as `:terminal_success` (something landed); the UI
badges it distinctly. **Progress is always `units satisfied / units
wanted`** — never a count of targets.

### Identity: overlap check, not key equality

The invariant is *no two active pursuers (pursuit×pursuit or
pursuit×release-tracking item) may claim the same unit of the same
title*. Phase 1 implements the degenerate case — auto-grab pursuits
stay single-unit and `find_by_tmdb_recipe/1` key-equality **is** the
overlap check when every pursuit has one unit. The general check lands
with multi-unit TMDB pursuits (campaign Phase 3) and becomes the
release-tracking dedup mechanism (campaign risk #4).

### Migration

One safe paired migration: create both tables; backfill **one unit per
existing pursuit** copying the thread fields verbatim; insert one
`TargetUnit` row per existing target (to its pursuit's single unit);
drop the moved columns from `acquisition_pursuits`. Backfill is
idempotent; existing pursuits become single-unit composites with
identical behavior.

### Events

Events stay pursuit-scoped (one timeline per goal). Unit-scoped kinds
gain a `unit_id` / unit label in their payloads via the existing
`Events.Define` macro. No event-system rework.

### Rejected alternatives

* **Parent pursuit grouping child pursuits.** Two aggregate levels with
  the same name and duplicated lifecycle machinery; the campaign
  explicitly settled "no separate aggregate."
* **Keep thread state on the pursuit, add units as bookkeeping.** Multi-
  unit pursuits would need N concurrent threads but have storage for
  one; every concurrent-download scenario becomes a special case.
* **`unit_id` FK on targets instead of a join table.** Phase 2 packs
  (one target covering many units) would force the join-table migration
  anyway, plus a data rewrite of every FK written in between.
* **Derived (unstored) parent state.** List filters, indexes, and the
  existing state-machine events all key on a stored state; deriving on
  read trades a transactional fold for N+1 aggregation everywhere.

## Consequences

* Good, because unit-based progress ("7 of 10") and pack coverage are
  structural — risk #1 of the campaign (pack→episode accounting)
  becomes a join-table write, not an accounting layer.
* Good, because the thread semantics (decision flag, tried-GUIDs,
  stall observations) move unchanged — commands, policy, and watcher
  keep their logic, re-pointed at units.
* Good, because existing pursuits migrate losslessly to single-unit
  composites; no behavior change ships with the schema change.
* Bad, because every reader/writer of the moved columns (commands,
  snapshot/policy/watcher, view-models, LiveView, tests) must be
  re-pointed in the same change — a wide mechanical refactor.
* Bad, because the Snapshot → Policy → Watcher loop becomes per-unit,
  multiplying watcher work by unit count (bounded: composites are
  user-sized, tens of units, not thousands).
* Neutral, because `partial` adds a fifth pursuit state — UI filter
  chips and `State.bucket/1` gain one case.
