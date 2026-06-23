---
status: in-progress
started: 2026-06-23
last_updated: 2026-06-23
---
# Cour-aware acquisition

## Goal

Stop TV pursuits from silently never completing when a show's TMDB
"season" spans multiple broadcast runs (cours) that the release world
packages separately. Two fixes, both grounded in the per-episode
`air_date` we already store: a **coverage guard** that refuses to
credit a release with episodes it cannot physically contain, and
**cour-aware search** that queries correctly for a later run instead of
re-surfacing the first-run season pack. No new persistence — runs are
derived on demand.

## Status

**Both phases implemented and committed to local `main` (unpushed),
2026-06-23.** Full Elixir suite green (5139 tests), credo / boundaries /
sobelow / deps.audit clean, JS green. The full-suite run intermittently
trips the pre-existing SQLite "Database busy" setup flake in
`acquisition_live_test` (unrelated to this work — clean in isolation and
on a re-run); see [[project-suite-residual-concurrency-flakes]].

Phase 1 (commit `133730aa`): coverage guard + `CourSegmentation`.
Phase 2: cour-aware queries (`Search.CourQueries`), run-aware pack
classification (`Search.CourCoverage`), `Planner.Option.offer_only`,
`Criteria.run` + `QueryBuilder` cour branch, `Acquisition.Cours`
(season fetch + run detection), the `RunPlan` post-descent cour-offer
pass, and `PursueTarget` cour-aware re-search.

Outstanding (owner-gated): wiki note (Troubleshooting / FAQ — "why didn't
my season pack complete the show?") and `/ship`. Operational: the wedged
live Frieren pursuit still needs a manual cancel (this work prevents new
bad matches, it does not unstick the old one).

Design approved and committed
([`docs/superpowers/specs/2026-06-22-cour-aware-acquisition-design.md`](../docs/superpowers/specs/2026-06-22-cour-aware-acquisition-design.md),
commit `c2300841`). Phase 3 (TMDB episode-group enrichment) cut as
YAGNI.

### Reconciliation (2026-06-23, before any code)

Checked the design's stated sites against current code. Two findings
refine the plan (recorded here so the next session inherits them):

* **`PlanUnit` has no `air_date` column.** The coverage guard runs in
  `Jobs.RunPlan` (an Oban worker that *reloads* units from the DB at
  solve time), so the per-episode `air_date` the guard compares against
  must be **persisted on the plan unit** — it is not reachable from the
  reloaded row otherwise. This is raw episode data, not the derived
  cour model, so it does **not** contradict the
  "no-persist-the-cour-model / derive-on-demand" decision. Phase 1 adds
  an `air_date` column, populated at plan creation from the want /
  selection episode air dates (`drop_planner.ex`, `Plans.create_*`).
  Movie units carry `nil` (guard no-ops).
* **Phase 2's `QueryBuilder.build_tv` pointer is the wrong path for
  *surfacing*.** The autonomous descent that searches the corpus and
  surfaces offers on the plan board / decision card builds its terms via
  `Plans.LadderTerms` (driven by `Jobs.RunPlan`), **not**
  `QueryBuilder`. `QueryBuilder.build/1` is the *post-commit pursuit*
  path (`Jobs.PursueTarget` re-search). Cour-aware queries for the
  offer-surfacing path therefore belong in the draft descent
  (`LadderTerms` / `RunPlan` rungs). `QueryBuilder` may also want them
  for the pursuit re-search path; resolved at Phase 2 start.

### Implementation note — the guard stays in the pure `Planner`

The guard is realized as an optional per-`Planner.Option` **coverable
allow-list** (default `:all`). The impure caller (`RunPlan`, which holds
the units' air dates) computes the coverable unit set from each
candidate's `publish_date`; the pure `Planner` intersects scope-coverage
with that set everywhere it credits an option (consolidate, singles,
fit numerator, offers). Trimmed units fall through to `unfound`. Keeps
`Planner` pure and date-blind; no lossy scope rewriting.

## Motivating case (do not re-investigate — captured here)

*Frieren: Beyond Journey's End* (TMDB 209867). TMDB numbers it as one
Season 1 of 38 episodes across three cours:

| Cour | Episodes | Aired |
|------|----------|-------|
| 1 | E1–E16 | 2023-09-29 → 2023-12-22 |
| 2 | E17–E28 | 2024-01-05 → 2024-03-22 |
| 3 | E29–E38 | 2026-01-16 → 2026-03-27 |

Release-tracking correctly wanted E29–E38 (`provenance: :calendar`,
real air dates). The acquisition path searched `"Frieren Season 1"` and
matched `Frieren ... Season 01 [2023-2024] COMPLETE 1080p BDRip`, which
contains only E1–E28. The download completed, the reconciler found no
files for E29–E38, the 10 pursuit units stayed `active` pointing at an
already-`acquired` target, and the pursuit wedged permanently (it
neither completes nor re-searches). Live pursuit id at diagnosis:
`af3e2055-7067-4f17-994f-2e55e5713736`.

**Operational follow-up (separate from this code):** that wedged
pursuit must be cancelled by hand — this work prevents *new* bad
matches but does not unstick it. Cancel via
`MediaCentaur.Acquisition.Pursuits.Commands.Cancel` (or the Pursuits UI)
against the live node.

## Decisions made

* `2026-06-22` — Derive cour structure by **air-date-gap inference**,
  not a persisted model and not the TMDB episode group. Recomputed on
  demand (deriver model). (design doc)
* `2026-06-22` — Scope is **both** the coverage guard *and* cour-aware
  searches. The guard is the safety net that kills the silent-failure
  class; the searches are the cure. (design doc)
* `2026-06-22` — Cour-search candidates are **surfaced as offers /
  decision card**, never auto-grabbed (later-cour scene naming is too
  fuzzy to auto-trust). Reuses the existing offer path. (design doc)
* `2026-06-23` — Gap threshold is a **named code constant**
  (`@default_gap_days 56`, 8 weeks), parameterizable for tests — not a
  Settings entry. (design doc)
* `2026-06-23` — **Cut** TMDB episode-group enrichment (Phase 3) as
  YAGNI. (design doc)

## Next steps

Test-first throughout (`automated-testing` skill). Use **synthetic**
air dates and generic placeholder titles in tests — no real titles
(house rule). The Frieren data above is prod runtime, exempt, and for
reference only.

### Phase 1 — segmentation + coverage guard (kills the bug class)

1. **`MediaCentaur.Acquisition.CourSegmentation`** (new, pure module).
   - `runs(episodes, gap_days \\ @default_gap_days)` where `episodes`
     is `[%{season:, episode:, air_date:}]` (or a tolerant shape) →
     ordered `[%{index:, first_ep:, last_ep:, date_span:}]`.
   - `@default_gap_days 56`. Start a new run when the gap to the next
     episode's `air_date` exceeds `gap_days`. `nil` air_date → attach
     to current run (no split on missing data).
   - Helper to answer "which run is unit X in?" for the query side.
   - Unit tests: Frieren-shaped synthetic data → two runs
     ({E1–28},{E29–38}) at 56d; a continuous weekly season → one run;
     all-nil dates → one run; custom `gap_days` honored.
2. **Coverage guard** in the plan runner's per-candidate coverage step.
   - Site: `lib/media_centaur/acquisition/plans.ex` around line 467,
     `with {:ok, scope} <- TitleMatcher.coverage(result, criteria)` —
     after coverage is computed, trim from `scope` any unit whose
     `air_date` is after the candidate's `SearchResult.publish_date`.
   - Parse `publish_date` (string, nullable). **Monotonic opt-in**:
     `publish_date` nil → no trimming (mirror the fit-gate's
     don't-block-on-unknown rule).
   - The trimmed units fall through to `Planner.solve/3` as `unfound`
     rather than being credited to the pack.
   - Tests: candidate published 2024 vs want air_date 2026 → unit
     trimmed → `Planner` returns it `unfound`, not satisfied; nil
     publish_date → untouched.
3. `mix precommit` green. Commit Phase 1.

### Phase 2 design (decided 2026-06-23 — "build fully")

Two frictions surfaced during Phase 1 that the design hadn't seen; owner
chose to build through them rather than defer:

* **Run detection needs the full season's air dates.** `CourSegmentation`
  finds the gap that marks a later run only if it sees the whole season,
  but plan units carry just the *wanted* (late) units' dates. So the
  descent fetches the season via `TMDB.Client.get_season/3` (the source
  `Targeting` already uses; stub with `TmdbStubs.stub_get_season/3`),
  segments it, and detects whether the residual is in a later run.
  Recomputed on demand — still nothing persisted beyond the Phase-1
  `air_date`.
* **Cour-pack coverage is a contextual join, not title-only.**
  `ReleaseCoverage.classify` is title-only and returns `:unknown` for
  `"Title 2nd Season"` / `"Title 29-38"`, so it cannot map a cour pack to
  a TMDB episode range without run context. A new pure `CourCoverage`
  classifies *with* the run context (identity match + ordinal/range
  token → `{:episodes, season, first, last}`). Because later-cour naming
  is fuzzy, cour candidates are **offer-only**: a new `offer_only` flag on
  `Planner.Option` forces them into the offers bucket (never auto-grabbed,
  human confirms on the board), regardless of fit.

Pieces (each pure piece test-first):

* `Acquisition.CourQueries` — `build(title, run)` → run-shaped queries
  (absolute range, ordinal season, TMDB-numbered), ordered best-to-worst.
* `Acquisition.CourCoverage` — run-aware classification of a result title
  → `{:episodes, …}` or `:no_match`.
* `Planner.Option.offer_only` — cour candidates surface only as offers.
* `Search.Criteria.run` + `QueryBuilder.build_tv` — emit cour queries when
  criteria carry a later-run context (the pursuit re-search path).
* `Jobs.RunPlan` cour rung — fetch season, segment, search cour terms for
  later-run residual, classify offer-only via `CourCoverage`, feed solver
  → surfaces as board offers.

### Phase 2 — cour-aware queries + surfacing

4. **Cour-aware query generation**. When the residual units are in a
   *later* run (run index > 0), `QueryBuilder.build_tv`
   (`lib/media_centaur/search/query_builder.ex`) must emit run-shaped
   queries instead of (or ahead of) `"{title} Season {n}"`:
   - absolute range/episode — `"{title} {first}-{last}"`, `"{title} - {ep}"`
   - ordinal-season guess — `"{title} 2nd Season"`, `"{title} Season 2"`
   - TMDB-numbered — `"{title} S{ss}E{ee}"`
   Ordered best-to-worst (the worker tries each until acceptable).
   - This needs the criteria to know the residual's run. Thread run
     info through the recipe→criteria projection
     (`lib/media_centaur/acquisition/pursuits/recipe.ex`:
     `to_criteria/1`, `for_unit/2`) and/or
     `MediaCentaur.Search.Criteria`. Keep `QueryBuilder` pure — pass it
     what it needs, compute the run in the caller via
     `CourSegmentation`.
   - Trigger gate: only when segmentation reports multiple runs AND the
     residual is in a later one.
   - Tests: later-run residual emits absolute/ordinal queries and NOT
     `Season N`; first-run residual is unchanged (regression guard).
5. **Surfacing**. Verify the cour-search candidates reach the user as
   offers / decision card rather than auto-grabbing. The offer path
   already exists (`Plans.board_for/1` ~line 263 surfaces unfound +
   over-broad-pack offers; the decision card consumes it). Confirm the
   later-run candidates flow through it; add coverage if there's a gap.
   - Test: a later-run plan with cour candidates lands them as
     offers/alternatives, not committed grabs.
6. `mix precommit` green. Commit Phase 2.

### Close-out

7. Update this campaign's Status; reconcile against `git log`.
8. Wiki: note cour-aware acquisition behavior if user-visible
   (Troubleshooting / FAQ — "why didn't my season pack complete the
   show?"). Confirm with owner whether it warrants a wiki entry.
9. Ship per `/ship` once owner approves. Remove this campaign file on
   completion (git history is the archive).

## Completion criteria

* A release whose `publish_date` precedes a wanted episode's `air_date`
  is never credited with that episode; the planner reports it `unfound`
  instead. (Phase 1)
* A pursuit/plan whose residual is a later cour generates cour-shaped
  search queries (absolute/ordinal), not the first-run `Season N`
  query, and surfaces candidates as offers for the user to confirm.
  (Phase 2)
* `CourSegmentation` correctly splits a multi-cour show and merges a
  single continuous run, covered by unit tests with synthetic data.
* `mix precommit` green; no regression to single-run shows or movie /
  prowlarr_query pursuits.

## Pointers

* Design doc:
  [`docs/superpowers/specs/2026-06-22-cour-aware-acquisition-design.md`](../docs/superpowers/specs/2026-06-22-cour-aware-acquisition-design.md)
* Solver: `lib/media_centaur/acquisition/planner.ex`
  (`solve/3`, pure; fit-gating + granularity ladder).
* Plan runner / candidate coverage: `lib/media_centaur/acquisition/plans.ex`
  (`create_tracking_plan/2`, coverage step ~L467, `board_for/1`
  offers ~L263).
* Query generation: `lib/media_centaur/search/query_builder.ex`
  (`build_tv/1`).
* Recipe→criteria projection:
  `lib/media_centaur/acquisition/pursuits/recipe.ex`.
* Candidate dates: `MediaCentaur.Search.SearchResult` (`:publish_date`,
  string from Prowlarr `publishDate`).
* Want dates: `MediaCentaur.ReleaseTracking.Want` (`:air_date`,
  `:season_number`, `:episode_number`).
* Coverage type: `MediaCentaur.Search.ReleaseCoverage`,
  `MediaCentaur.Search.TitleMatcher.coverage/2`.
* Related ADR: [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
  (campaign convention).
