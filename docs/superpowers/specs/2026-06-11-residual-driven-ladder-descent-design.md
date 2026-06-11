# Residual-Driven Ladder Descent — Design

**Date:** 2026-06-11
**Status:** Approved in design conversation; awaiting implementation plan
**Touches:** `MediaCentaur.Acquisition.Jobs.RunPlan`, `MediaCentaur.Acquisition.Plans.LadderTerms`, `MediaCentaur.Acquisition.Plans`, plan board swap picker (`AcquisitionLive` + `plan_modal`)

## Problem

`RunPlan.gather_options/4` searches **every** coverage-ladder term up front, then solves
once. For a fully-wanted 10-season × 24-episode show that is 1 series term + 20 season
terms + 240 episode terms = **261 sequential searches per plan run**, regardless of what
the broader rungs found. Because the planner's consolidation policy means an acceptable
pack is never fragmented for per-unit quality, the episode rung almost never changes an
assignment when packs exist — its results mostly feed the swap picker. The 30-minute
corpus freshness window protects re-runs but not the first run, and `force: true`
re-issues the full burst live.

Scenario inventory the design must serve:

1. **Big back-catalog plan** — packs exist; episode terms are ~92 % of traffic and almost
   pure speculation.
2. **Gap-fill** (scattered missing episodes) — episode terms are essential, but only for
   the holes.
3. **Weekly drops** (`DropPlanner` → small wanted sets) — already cheap; must not regress.
4. **Obscure/dry shows** — every rung returns nothing; full descent is unavoidable once.
5. **Patience-elevated units** (ADR-056 Q4 per-unit `min_quality` floors) — packs
   acceptable to the plan may be unacceptable for specific units; those units need deeper
   rungs, the rest don't.
6. **Force re-search** — user-initiated; today re-issues all terms live.

Unifying observation: **the episode rung's value is exactly the solver's residual.**
Wherever broader rungs produce acceptable coverage, deeper searches are speculation;
wherever they don't, they're essential.

## Design

### 1. Rung loop in `RunPlan` (replaces gather-all-then-solve)

```
rung 1: search series term            → accumulate options → solve → residual empty? stop
rung 2: search season terms, only for seasons containing residual units
                                      → accumulate options → solve → residual empty? stop
rung 3: search episode terms, only for residual units
                                      → accumulate options → solve → done
```

- **Residual** = the union of `Planner.Solution.unfound` across the per-quality-floor
  group solves that `run_tv/3` already performs. A unit with an elevated floor fails
  acceptability in its group's solve, stays in the residual, and drives descent for
  itself alone — scenario 5 composes with zero extra bookkeeping.
- `Planner` is pure and cheap; re-solving per rung is free. **No planner changes.**
- Option accumulation is cumulative across rungs: red-flag filtering, exclusion
  filtering, guid dedup (`terms_by_guid`, first term wins), and
  `TitleMatcher.coverage/2` identity verification behave exactly as today, applied as
  each rung's results arrive.
- The final solve's assignments/unfound land on plan units exactly as today
  (`assign_changeset` / `unfound_changeset`); `PlanEvents.SearchActivity` still
  broadcasts per term actually searched; a failed search still records the plan `error`
  and continues.
- `force: true` passes through to `Corpus.search/2` per term **actually searched** — a
  force re-run also walks lazily, so it only re-hammers as deep as the residual requires.
- **Movies unchanged** (already one term).

Expected effect: scenario 1 drops from 261 searches to 1–21; scenario 2 pays series +
affected seasons + exactly the holes; scenarios 3 and 4 are unchanged (correctly — you
cannot prove absence without looking).

### 2. `LadderTerms` rung constructors

Split term generation into rung-scoped functions, keeping the existing API as their
concatenation so the corpus keys and the picker can never drift:

- `series_terms(plan)` — `[{title, type: :tv}]`
- `season_terms(plan, seasons)` — `Title Season N` + `Title SNN` per season
- `episode_terms(plan, units)` — `Title SNNENN` per unit
- `for_plan/2` ≡ `series ++ seasons(all wanted seasons) ++ episodes(all wanted)` —
  **invariant, unit-tested**, because `for_unit/2` (the picker's term universe) and
  corpus keying both build on it.

### 3. Swap picker: on-demand "search for more alternatives"

Lazy descent thins the picker: when packs cover everything, episode terms were never
searched, so `Plans.alternatives_for/1` (corpus-only by design) has fewer candidates —
e.g. no 4K singles behind a 1080p pack assignment.

Fix at the seam, paying for alternatives when a human asks instead of speculatively per
plan:

- New `Plans.search_alternatives(plan_unit_id)` — runs `Corpus.search/2`
  (**`force: false`** — consult-first; fresh keys cost nothing, never-searched keys go
  live) over the unit's `LadderTerms.for_unit/2` terms, then returns the same shape as
  `alternatives_for/1`.
- Plan board UI: an explicit **button** in the alternatives picker (`plan_modal`), not
  search-on-open — picker-open latency and surprise indexer traffic are both wrong. The
  LiveView (`AcquisitionLive`) runs it async (`start_async`) with a loading state on the
  button, then replaces the alternatives list.
- `plan_modal` is a function component: its story gains the loading/expanded variations
  in the same change (MC0009).

## Out of scope (deliberately deferred)

- **Liveness-aware corpus freshness** (ended show ⇒ longer window) — revisit only if
  dry-show re-runs still hurt after descent lands.
- **Structured tvsearch season params** replacing the two season text forms — needs an
  investigation of what our indexers honor; separate change.
- **Parallelizing searches** — fixes latency by worsening indexer citizenship; the burst
  itself is the bug.
- **Term budgets/caps** — arbitrary holes; rejected.
- **"Keep hunting above acceptable"** — require-vs-prefer is already encoded in
  `min_quality` floors and the patience window; the prefs are the policy.

## Testing

Test-first throughout (repo policy). No network; Prowlarr stubbed per `automated-testing`
conventions. Generic titles only (`Sample Show`).

- **`RunPlan` descent behavior** (the heart): with a stubbed search layer that records
  terms, assert per scenario —
  - acceptable series pack on rung 1 ⇒ exactly 1 term searched, all units assigned;
  - season packs on rung 2 ⇒ no episode terms searched;
  - season packs with one hole ⇒ episode term searched **only** for the hole;
  - nothing found anywhere ⇒ full ladder searched, all units unfound (existing behavior);
  - elevated-floor unit behind an acceptable 1080p pack ⇒ episode term searched only for
    that unit;
  - plan-wide exclusion of a pack ⇒ excluded guid never assigned and descent continues
    past it.
- **`LadderTerms`**: rung constructors + the `for_plan` ≡ concatenation invariant.
- **`Plans.search_alternatives/1`**: only non-fresh terms hit the (stubbed) live search;
  result shape matches `alternatives_for/1`.
- **LiveView test**: picker button event → async result → alternatives list re-renders.
- **Existing suites**: planner tests untouched; existing `RunPlan` tests keep passing
  (drops/movies paths unchanged).
