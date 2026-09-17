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
from their units). Step 1 (grab-failure classification) implemented
2026-09-17, unpushed: a 5xx or transport error from `Prowlarr.grab/1`
lands `download_client_unavailable`, no attempt charged, 15-minute
snooze, and the pursuit reads "Waiting — Prowlarr could not reach your
download client". Step 2 (fit-first order + plain names) implemented
2026-09-17, unpushed, as two commits: the rename (`SearchTerms`,
`SearchProgress`, `SearchProgressPanel`; no "rung", "ladder" or
"descent" left in the acquisition code) and the behavior
(`Plans.SearchOrder` + `Plans.Fit`; `RunPlan` walks primary then
fallback steps; the picker and gap evidence read terms in the same
order; board copy and story updated). A one-episode plan now makes one
indexer request when the single exists. Step 3 (season sizes on the
tracking item → drop plans get fit gating) implemented 2026-09-17,
unpushed, with an additive migration. Step 4 (the pursuit side searches
like the plan side: one term builder, coverage-filtered decision card
with pack alternatives, pre-exhaust pack decision) implemented
2026-09-17, unpushed. Step 5 (a Status warning and an Incoming glyph
card while Prowlarr cannot hand releases to the client, plus the app's
own client faults on the glyph) implemented 2026-09-17, unpushed. Wiki
pages committed locally alongside each step, unpushed until the app
ships. Nothing left but review and ship; one known history wrinkle:
`51dc5303` swept up two staged deletions from the parallel step 4 work
and does not compile alone (`1afcb814` restores the callers) — nothing
is pushed, so it can be left or reordered before the push.

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
* `2026-09-17` — Correction to decision 3: the tracking calendar holds
  only post-library episodes, so season sizes are recorded on the
  tracking item by the refresher from the TMDB responses it already
  fetches; no fetch in the plan-creating path. (spec decision 3, as
  corrected; commit `d252a5a7`)
* `2026-09-17` — A tracking draft that found nothing but offers a pack
  stays `ready` on the board for a person, whatever the planning mode;
  one with nothing to offer is still deleted. Owner chose this over
  "tracking stays singles-only". (spec decision 7; commit `51dc5303`)
* `2026-09-17` — The Incoming Heads-up glyph shows download-client
  faults (unreachable, credentials rejected, Prowlarr can't hand over)
  next to search health and storage; a Status warning opens while grabs
  keep failing the hand-off. Owner did not object when told. (commits
  `34ec6dfa` and the glyph commit)

## Next steps

1. ~~Grab-failure classification in `Jobs.PursueTarget` + the pursuit
   status copy.~~ Done 2026-09-17 (three worker tests, one status test,
   wiki Troubleshooting entry).
2. ~~`Plans.SearchOrder` (pure) + `RunPlan` on it; `LadderTerms` →
   `SearchTerms`; `PlanEvents.DescentStatus` → `SearchProgress` with the
   primary/fallback kind; board headline and `GapVerdict` copy;
   `Alternatives.for_unit` on the same order.~~ Done 2026-09-17
   (`search_order_test.exs` pins the use-case table; `run_plan_test.exs`
   pins U1, U4 and the U1 miss with its fallback offer).
3. ~~Season sizes recorded on the tracking item at refresh (spec decision
   3, corrected 2026-09-17: the calendar holds only post-library
   episodes; the refresher's own TMDB responses carry the counts) and
   passed into drop plans as `span_sizes`.~~ Done 2026-09-17. Additive
   migration `20260917190000_add_release_tracking_item_season_sizes`
   (`release_tracking_items.season_sizes`, default `%{}`) — **mention in
   the CHANGELOG at ship**; an item fills in at onboarding or on its next
   refresh, and its drop plans plan as before until then. Pinned by
   `helpers_tv_calendar_test.exs` (sizing), `refresher_test.exs`
   (persisted), and `drop_planner_test.exs` (span sizes on the plan; one
   new episode takes its single, never the pack; a pack-only indexer
   yields an offer and no grab).
   Follow-ups noted from step 2: `SearchProgressPanel.initial/1` still
   promises the three primary steps before the first broadcast, so the
   pre-event itinerary can show a series row a fit-first run never takes
   (replaced on the first event) — derive it from `SearchOrder` when
   convenient. The alternatives picker judges fit against the unit's own
   want, so for one episode of a whole-season plan it lists the episode
   term first while the plan ran season-first; same candidate set, only
   the recorded term can differ.
4. ~~Retry loop: fallback search once before exhausting; decision prompt
   when a pack contains the unit.~~ Done 2026-09-17, widened by F10, as
   two commits: `refactor(search): one builder for every search term`
   (`Search.SearchTerms` spells every constructed term; `QueryBuilder`
   and `Plans.SearchOrder` both build there; `QueryBuilder.fallback/1`
   is the episode's season-then-series widening) and
   `feat(acquisition): the pursuit side searches like the plan side`
   (the decision card searches the unit's terms in plan order through
   the corpus and lists only what `TitleMatcher.covers?/2` says contains
   the episode, a pack labelled as one; picking a pack covers every live
   unit of the pursuit its scope contains; the attempt that would
   exhaust runs the fallback terms once and asks "Only a pack has this
   episode. Picking it downloads the whole pack." instead of failing;
   the card repeats the worker's prompt). Movies and typed queries on
   the card are unchanged.
5. ~~Check what Status shows while a download client is unreachable; add
   a Needs-attention item if nothing does.~~ Done 2026-09-17. Status
   already owned the app's own link (`Downloads.IncidentContext`, three
   minutes' grace, plus an error on rejected credentials). Added
   `Pursuits.IncidentContext` for the link the app cannot see — Prowlarr
   to the client — read off the `download_client_unavailable` stamps
   from step 1 (warning while the latest word is a failure; clears on
   the next successful grab or 30 minutes after the last failed retry),
   composed into the acquisition assessor, and the Incoming Heads-up
   glyph now carries all three client faults with the search and
   storage cards.
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
