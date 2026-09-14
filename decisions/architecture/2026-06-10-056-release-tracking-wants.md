---
status: accepted
date: 2026-06-10
amended: 2026-09-13
---
# Release-tracking wants — tracks emit plan-based pursuits

## Context and Problem Statement

Media search resolves a bounded selection through corpus → planner → plan →
composite pursuit ([ADR-055](2026-06-09-055-composite-pursuits.md)): search
discovers, a pursuit executes. Release tracking still armed one single-unit
pursuit per `release_ready` event whose worker re-searched indexers
open-endedly, so a season drop became ten pursuits, packs were never
considered, and pursuit-versus-track dedup had no mechanism. Release
tracking owns the passage of time, and the time lived in the pursuit worker.

## Decision Outcome

A track is a standing targeting intent. Every materialization runs through
the same corpus → planner → plan machinery, every grab is a plan-provenance
composite pursuit, and waiting belongs to release tracking, never a pursuit.

1. **The want ledger.** `ReleaseTracking.Want` (`release_tracking_wants`) is
   durable per-unit acquisition intent. A want opens when a unit becomes
   acquirable — aired and not in the library; pre-air schedule never enters
   the ledger. Status is `open | satisfied | dismissed`, nothing else. Claim
   state is not stored: Acquisition derives it from active plan and pursuit
   units by the ADR-055 overlap check, enforced once at `CommitPlan`.
   `release_tracking_releases` stays the wholesale-replaced TMDB calendar.
2. **Per-drop plans.** Per cadence tick, per title, the open, unclaimed,
   search-due wants become one drop plan solved by the existing planner.
   The batch is state, not delta — everything re-derives from open-want
   state. At most one active tracking-born draft per title; wants opening
   mid-draft wait one tick.
3. **Back-off by want age** (`Acquisition.WantSchedule`): every tick for
   the first 48 hours, then about every four hours to seven days, daily to
   thirty days, weekly forever. Giving up is a dismissal, never a timeout.
4. **Failure.** A terminal pursuit releases its claims and the still-open
   want re-plans on cadence; the planner excludes candidates matching that
   unit's terminally failed targets, so re-plans assign only new releases.
   A user cancelling a tracking-born pursuit dismisses the covered wants;
   organic failure never dismisses.
5. **Approval** (amended 2026-09-05): every plan carries `approval_policy`
   (`automatic` | `review`), stamped at creation from the title's rung by
   the drop planner and as `review` by the picker; `Reactor` reads it for
   every plan.

Superseded since:

* The `off / ask / auto` modes are the rungs of
  [ADR-066](2026-09-07-066-one-ladder-per-title.md).
* The 4K patience window — a young want raising its quality floor — was
  removed with UIDR-041 §6. The automatic floor is fixed at 1080p; the only
  per-title quality datum is `Acquisition.TitleDownloadParams`
  ([ADR-063](2026-08-31-063-plan-diagnosis-model.md) §2).
* Waiting state is shown on the Watchlist
  ([UIDR-035](../user-interface/2026-09-07-035-two-title-surfaces.md)),
  not on a tracking page; Incoming shows a track only once acquisition
  begins.

### Consequences

* Automation exercises the planner unattended, guarded by conservative pack
  classification, the quality floor, plan provenance and the `review` policy.
* Search timing is tick-granular.
* Quality upgrades are not built; `satisfied_quality` is recorded on the
  want because it is the one datum painful to backfill later.
