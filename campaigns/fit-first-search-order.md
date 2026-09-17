---
status: in progress
started: 2026-09-17
last_updated: 2026-09-17
---
# Fit-first search order

## Goal

A TV plan searches the scope that fits its want first — one episode
starts at the episode term, a whole season at the season term — and
widens only to offer packs it may not grab. Alongside: a grab that fails
because the download client is unreachable is treated as an outage, not
as a bad release; tracking-born plans get the same fit gating as hand
plans; the pursuit retry asks about a pack before giving up. Design:
[`docs/superpowers/specs/2026-09-17-planning-descent-design.md`](../docs/superpowers/specs/2026-09-17-planning-descent-design.md).

## Status

Design decided 2026-09-17 (six decisions, all recorded in the spec).
Prerequisite fix shipped in v1.32.1 (`1764bea9`, pursuits read scope
from their units). No rollout code yet.

## Decisions made

* `2026-09-17` — Search the scopes whose pack could pass the fit gate
  first, widest first; then the rest narrowest first, offers only.
  (spec §The rule)
* `2026-09-17` — The fallback search runs automatically, not on demand.
  (spec decision 2)
* `2026-09-17` — Tracking plans derive span sizes from the tracking
  calendar; the planner's unknown-means-unjudged contract stays.
  (spec decision 3)
* `2026-09-17` — The retry loop runs the fallback search once before
  exhausting and raises a decision when a pack has the unit. (spec
  decision 4)
* `2026-09-17` — `Prowlarr.grab/1` 5xx and transport errors are an
  infrastructure outcome: no attempt bump, short snooze, copy that names
  the client. (spec decision 5)
* `2026-09-17` — Plain names: scope, search order, primary, fallback.
  "Rung", "ladder", "descent" leave the code as their modules are
  touched. (spec decision 6)

## Next steps

1. Grab-failure classification in `Jobs.PursueTarget` + the pursuit
   status copy. Test-first: a 500 from grab leaves the attempt count
   unchanged. Independent of the rest; ships first.
2. `Plans.SearchOrder` (pure) + `RunPlan` on it; `LadderTerms` →
   `SearchTerms`; `PlanEvents.DescentStatus` → `SearchProgress` with the
   primary/fallback kind; board headline and `GapVerdict` copy;
   `Alternatives.for_unit` on the same order.
3. Span sizes for tracking plans from the tracking calendar
   (`create_tracking_plan/2` callers). Regression test: a lone unit with
   no span sizes and a pack option is not assigned the pack.
4. Retry loop: fallback search once before exhausting; decision prompt
   when a pack contains the unit.
5. Check what Status shows while a download client is unreachable; add
   a Needs-attention item if nothing does.
6. Wiki: Searching-and-Downloading (search order), Troubleshooting
   (download client unreachable), Settings-Reference if "Season packs"
   copy changes.

## Completion criteria

* A one-episode plan makes one indexer request when the episode exists.
* A whole-season plan starts at the season term.
* An unfound episode carries a season-pack offer when one exists.
* A weekly-drop plan never auto-grabs a season pack for one episode.
* A grab that fails on a 5xx keeps its attempt count and says why.
* No "rung", "ladder" or "descent" left in `lib/media_centaur/acquisition`.
* Wiki pages updated.

## Pointers

* `lib/media_centaur/acquisition/jobs/run_plan.ex`, `planner.ex`,
  `plans/ladder_terms.ex`, `jobs/pursue_target.ex`, `plan_events.ex`,
  `view_models/gap_verdict.ex`.
* ADR-055 (composite pursuits), ADR-056 (release-tracking wants),
  ADR-063 (plan diagnosis model); campaign plan-solver-consolidation
  (2026-06-10, "packs win when they fit").
* Evidence run: acquisition log ring 2026-09-17 14:52–15:40 UTC.
