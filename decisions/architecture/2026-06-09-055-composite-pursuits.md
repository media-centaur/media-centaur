---
status: accepted
date: 2026-06-09
---
# Composite pursuits — units carry the attempt thread

## Context and Problem Statement

A pursuit ([ADR-039](2026-05-07-039-acquisition-pursuits.md)) was one wanted
thing: the attempt thread (current target, tried releases, attempt count,
decision flag, stall observations) sat on the pursuit row, and identity was
key-equality on the TMDB tuple. Media search needs one pursuit over many
wanted things — a brace-expanded query or a whole season — with progress
counted per unit, and a season pack that satisfies ten episodes with one grab.
Neither is representable when the thread lives on the pursuit.

## Decision Outcome

Chosen option: grow `Pursuit` into a composite by introducing a `Unit` child
that carries the attempt thread. One aggregate, the same thread semantics,
moved down one level.

Vocabulary: a **unit** is one wanted thing (an episode, a movie, or one
expanded query); a **candidate** is a known release covering one or more
units; an **assignment** maps each covered unit to one candidate; a **target**
is one grab attempt of one release — per release, never per unit.

1. **`Acquisition.Pursuits.Unit`** (`acquisition_pursuit_units`) holds the
   thread: `state`, `current_target_id`, `tried_release_guids`,
   `attempt_count`, `awaiting_decision_at`, the stall and zero-seeder
   timestamps, plus `query`, `label` and `position`. The unit state machine
   is the former pursuit state machine: `active → satisfied | exhausted |
   cancelled`, with the decision flag orthogonal.
2. **`TargetUnit`** (`acquisition_target_units`) joins a target to the units
   its release covers. A single grab writes one row; a pack writes many. It
   is a join, not a `unit_id` on the target, so pack coverage is data rather
   than a schema change.
3. **The pursuit keeps the goal** — recipe, title, origin, criteria — and a
   stored outcome state folded from its units on every unit transition: any
   unit active → `active`; all satisfied → `satisfied`; terminal with at
   least one satisfied → `partial` (bucketed as terminal success); terminal
   with none satisfied and at least one exhausted → `exhausted`; otherwise
   `cancelled`.
4. **Progress is units satisfied over units wanted**, never a count of
   targets.
5. **Identity is an overlap check, not key equality.** No two active
   pursuers — pursuit or release-tracking want — may claim the same unit of
   the same title. A single-unit pursuit reduces this to the TMDB-tuple
   lookup; multi-unit pursuits and release tracking use the general check
   ([ADR-056](2026-06-10-056-release-tracking-wants.md)).

### Consequences

* Every reader and writer of the thread — commands, snapshot, policy,
  watcher, view models — is per unit, so watcher work scales with unit
  count (bounded: composites are user-sized).
* `partial` is a fifth pursuit state that every state filter must know.
