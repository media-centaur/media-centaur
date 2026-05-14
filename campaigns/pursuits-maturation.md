---
status: in_progress
started: 2026-05-14
last_updated: 2026-05-14
---
# Pursuits maturation

> **Phase 1 shipped (2026-05-14).** Recipe value object, timeline
> presentation moved to TimelineEntry VM, Observations docstring
> honesty, find/current_target consolidation, StartFromPick command.
> AutoGrab rename deferred (see Next steps).
>
> **Phase 2 shipped (2026-05-14).** AutoCancel auto-pivots — on
> confirmed safe-case (zero-seeders), the dead release is cancelled,
> its guid lands on `tried_release_guids`, and a fresh seeking target
> is inserted with a PursueTarget Oban job enqueued. Pursuit never
> dangles. Caught a sibling latent bug: `TargetStatus.in_flight()` only
> includes `seeking` (worker alive), so the original AutoCancel was a
> no-op when zero-seeders fired on an `acquired` torrent. Added
> `TargetStatus.cancellable/0` (`seeking + acquired`) for the wider
> cancel filter.

## Goal

The pursuits concept has matured to the point where the architectural
audit (engineering-audit, 2026-05-14) surfaced ten seams worth
addressing. Internals of `Acquisition.Pursuits.*` are solid; the
cracks are at the boundary (`Acquisition` parent doing command work),
in the state model (`needs_decision` conflated with `active`), and
in one functional gap (`AutoCancel` leaves the pursuit dangling).
Migrate, don't rebuild — 80% of the code survives a from-scratch
rebuild unchanged, and the event log is the load-bearing scaffolding
that lets the migration ship phase-by-phase.

## Status

Phases 1+2 complete (local). Phase 3 (collapse `needs_decision` →
`awaiting_decision_at` flag) is next — single commit with DB migration.

## Decisions made

* `2026-05-14` — Migrate, not rebuild. Internals are sound; only the
  boundary and a few state-vocabulary choices need rework. (audit)
* `2026-05-14` — `AutoCancel` post-condition: **auto-pivot to fresh
  search.** Confirmed zero-seeders chains into `ChangeTarget`, prior
  guid lands on tried-list, pursuit silently continues. Aligns with
  the ADR-039 "safe cases auto-act" thesis. (user pick)
* `2026-05-14` — State model: **keep `active`, add
  `awaiting_decision_at`** orthogonal timestamp. Drop `needs_decision`
  from the state enum. Minimum churn; predicates become
  `terminal?/1` + `awaiting_decision?/1` + `active?/1`. (user pick)

## Next steps

Phased; ship each phase as its own commit set so we can pause between.

1. **Phase 1 — pure refactors, no DB change** (multiple commits)
   * `Pursuits.Pursuit.Recipe` value object — single touchpoint for
     recipe pattern matching across `QueryBuilder`, `TitleMatcher`,
     `Acquisition.do_search_for_pursuit`, `PursueTarget`.
   * Move timeline presentation (`summary_for/2`, `severity_for/1`,
     `detail_for/1`, `transition_phrase/2`) out of
     `MediaCentarr.Acquisition.Pursuits` into
     `ViewModels.TimelineEntry.from_event/1`.
   * Rename `Pursuits.Observations` semantics — honest moduledoc
     that owns "signal-derived event emission" (the
     `DownloadStarted` / `HealthChanged` decision lives here, not in
     Policy; ADR-039 phrasing needs a footnote).
   * `Pursuits.Commands.StartFromPick` — single command replacing
     the `Start.execute` → `PickTarget.execute` pair on the manual
     pick path (kills the spurious `UserDecisionRecorded` +
     `FallbackInitiated` events on first pick).
   * Kill duplicates: `Acquisition.current_target/1` (private copy
     of `Pursuits.current_target/1`); unify `find_pursuit` helpers
     into `Pursuits.find_for_target/2`.
   * ~~Rename `AutoGrab*` modules → `AutoAcquire*`~~ — **deferred**.
     "auto-grab" terminology has settled at the user-facing surface
     (DB column `item.auto_grab_mode`, TOML config keys, Settings
     copy, capability flag, routes). Renaming only the three internal
     modules creates a code-vs-data nominal split; a full rename is
     a wider campaign with config migration + UI re-copy. Not a
     "pure refactor."

2. **Phase 2 — `AutoCancel` auto-pivot fix** (single commit)
   * Test-first: `AutoCancelTest` red on "after auto_cancel,
     pursuit has fresh seeking target."
   * Implementation: `AutoCancel.execute` chains into
     `ChangeTarget.execute` (or shares its core helper) so the
     pursuit emerges with a new `current_target_id` and a fresh
     `PursueTarget` job enqueued.

3. **Phase 3 — collapse `needs_decision` state** (single commit, with
   data migration)
   * Migration: add `awaiting_decision_at :utc_datetime`; backfill
     for rows with `state = "needs_decision"`; rewrite state to
     `"active"` for those rows. Drop `needs_decision` from the
     `validate_inclusion` list and from `State.in_flight/0`.
   * Code: `State.terminal?/1` stays; `State.awaiting_decision?/1`
     reads the timestamp; `State.in_flight/0` collapses to "not
     terminal". Update `RequestDecision` to set the timestamp;
     `PickTarget` / `ChangeTarget` clear it on resume.
   * Update timeline rendering to read the flag.

4. **Phase 4 — split `Acquisition` parent context** (multi-commit)
   * New `Pursuits.Commands.Arm` (idempotent on TMDB tuple,
     replaces `Acquisition.find_or_create_tmdb_pursuit` +
     `ensure_active_target`).
   * New `Pursuits.Commands.ArmAll` (replaces
     `Acquisition.enqueue_all_pending_for_item`'s classifier).
   * Move target lifecycle reads (`list_auto_targets`) into
     `Acquisition.Targets` query module; move `cancel_target/2` /
     `rearm_target/1` to `Pursuits.Commands.*` (they're
     command-shaped).
   * Move search session passthroughs out (`Acquisition.Search`).
   * Move Reactor entry points (`handle_release_ready_event` /
     `apply_decision`) into `Acquisition.Reactor.Handlers`.
   * `Acquisition` shrinks to a true thin facade.

5. **Phase 5 — single PubSub dialect** (multi-commit)
   * Add typed events: `TargetAcquired`, `TargetSnoozed`,
     `TargetFailed`, `TargetArmed`, `TargetCancelled`.
   * Migrate LiveView `handle_info` clauses to receive typed
     structs uniformly via `Events.event?/1`.
   * Delete legacy `{:target_*, target}` tuple broadcasts.

## Completion criteria

* `Acquisition` parent context is under 300 lines, all functions are
  thin facade delegates or pure helper readers.
* No callers pattern-match on `recipe_type` directly outside of
  `Pursuit.Recipe.from/1`.
* `Pursuit.state` enum has four values; `awaiting_decision_at`
  timestamp drives the user-input-blocked state.
* `Policy.evaluate/1` returns the same shape, but `AutoCancel` action
  no longer leaves the pursuit dangling — every confirmed-safe-case
  pursuit emerges with a fresh seeking target.
* PubSub subscribers consume one dialect (typed structs); no legacy
  `{:target_*, _}` tuples remain on `acquisition_updates`.
* `mix precommit` green throughout.

## Pointers

* Audit conversation (this session) — source of all findings.
* ADR-039 — original pursuits design.
* ADR-041 — three-pillar segregation (Pillar 1 storage commitment).
* `MediaCentarr.Acquisition.Pursuits.*` — internals being preserved.
* `MediaCentarr.Acquisition` — the 1,047-line parent slated for
  splitting in Phase 4.
