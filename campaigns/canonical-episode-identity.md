---
status: planning
started: 2026-06-17
last_updated: 2026-06-17
---
# Canonical episode identity

## Goal

Promote episode identity from an implicit, scattered `(tmdb_id, season,
episode)` convention (rebuilt in ~13 places, with no absolute ordinal)
into a **first-class `EpisodeIdentity` concept represented coherently in
every slice** — library, release tracking, acquisition, display — with
all numbering ambiguity confined to three named edge adapters. This
permanently kills the class of bug where a tracked show's aired-but-
missing episodes (Frieren S01E29–E38, which release groups name `S2`/
absolute) are never found or are "satisfied" by a wrong-cour pack that
delivers none of them. Decision: [ADR-058](../decisions/architecture/2026-06-17-058-canonical-episode-identity.md).

## Status

Phase 1 root cause pinpointed (2026-06-17): `LibraryReconciler.landed_file/5`
satisfies an episode unit via the **coarse fallbacks** — `release_match`
(release/folder name vs any present path segment) and the content-path
under-directory match — *after* the authoritative `tmdb_match` correctly
returns `:not_found`. The Frieren `Season 01 [2023-2024] COMPLETE` pack
imported E1–E28 under a release-named folder, so the S01E29 unit gets
satisfied by an E1–E28 file.

**Shipped (commit on `main`, unpushed):** the coverage-by-contents guard
in `LibraryReconciler.landed_file/5` — a unit with a canonical episode
identity (TMDB-tv + season + episode) is satisfied **only** by
`tmdb_match`; the coarse matchers (content-path under-dir, release-folder
name) stay valid for identity-less units (movies, `prowlarr_query`).
Red→green; 219 pursuit tests pass (existing pack/movie behaviour intact).
This stops the **false-satisfy** (the pursuit no longer reports
"satisfied" without delivering E29).

**Remaining Phase 1:** (a) record-tried-on-no-new-coverage in the
planner/commit path so `DropPlanner` stops re-grabbing the same wrong-cour
pack (the active pursuit now claims E29, which already blocks *new* plans,
but the pursuit itself must not re-grab the same useless release); (b) the
one-time reconcile sweep; (c) dev re-verify. NB: a pursuit that can only
ever find the wrong-cour pack stays unsatisfiable until **Phase 2**
(numbering) makes the real cour-2 releases findable — that's expected and
correct (honest "still looking" beats a false "got it").

ADR-058 accepted; design approved. Reconciliation-first so the loop stops
on the real library before any schema/identity refactor.

## Decisions made

* `2026-06-17` — Canonical identity = TMDB `(series, season, episode)` +
  derived absolute ordinal; TMDB is the only source of truth.
  ([ADR-058](../decisions/architecture/2026-06-17-058-canonical-episode-identity.md))
* `2026-06-17` — Absolute ordinal **derived on demand**, not persisted
  (recomputable per [ADR-057](../decisions/architecture/2026-06-14-057-derived-data-is-recomputable.md)); memoized helper, persist only if a query needs to sort by it. (owner)
* `2026-06-17` — Display shows **canonical `S01E29`** everywhere; a
  friendly broadcast label (`S02E01`) is a deferred display-only nicety. (owner)
* `2026-06-17` — Broadcast-season-named releases (`S2E01`) on TMDB-merged
  shows are **documented best-effort**; no Sonarr/XEM-style maintained
  mapping table, no second metadata source. (owner)
* `2026-06-17` — Composite pursuit per show (units = identities), **not**
  a parent-of-children aggregate (upholds [ADR-055](../decisions/architecture/2026-06-09-055-composite-pursuits.md)).

## Next steps

Test-first throughout (red → fix → green). Sequenced so each phase is
shippable and the data churn stops first.

### Phase 1 — Coverage-by-contents (stop the loop; no schema churn)

The narrowest fix that ends the re-grab loop on real data, independent
of the identity refactor.

1. **Red:** a unit/want for `S01E29` must NOT become satisfied when a
   landed pack imported only E1–E28. Test against `LibraryReconciler`
   (`lib/media_centaur/acquisition/pursuits/library_reconciler.ex`,
   `landed_file/5` / `tmdb_match/2`).
2. **Satisfaction is identity-present, not target-succeeded.** A unit
   satisfies iff *its own* canonical identity is present in the library
   (`Library.find_present_episode/3`); a `succeeded` target never folds a
   unit whose identity is still absent. Fix the satisfy path so target
   landing ≠ unit satisfied.
3. **Red:** the planner records a delivered-nothing release in the unit's
   `tried_release_guids` so the next tick excludes it.
4. **Record-tried-on-no-new-coverage** in the commit/reconcile path
   (`plans/commit_plan.ex`, `jobs/run_plan.ex` `excluded_release_guids`),
   so `DropPlanner` stops re-selecting the wrong pack.
5. **One-time reconcile** (idempotent maintenance action / sweep) that
   re-evaluates open wants against current library presence + tried
   releases, clearing the stuck Frieren churn. Mirror the
   `Wants.satisfy_present_wants/1` seam.
6. **Verify on dev** via the `mc_dev` node: Frieren no longer re-grabs the
   `Season 01 [2023-2024]` pack; the 10 wants are no longer "due" against
   a release that can't satisfy them.

*Done when:* red→green reconciler + planner tests; dev no longer
re-selects the wrong pack; no schema migration required.

### Phase 2 — First-class `EpisodeIdentity` + edge adapters

1. **`EpisodeIdentity` value module** (pure, `async: true` tests):
   `{tmdb_series_id, season, episode}`, `absolute_ordinal/2` (derive from
   TMDB season `episode_count`s, Specials excluded; memoized), `parse/1`,
   `to_key/1` (replaces `"s1e29"`), `label/1`.
2. **Route the ~13 sites through it** (behaviour-preserving, tested):
   `Want.unit_key`, `Library.find_episode_by_season_episode`,
   `LibraryReconciler.tmdb_match`, `Pursuits.Unit` label/position,
   `library_formatters` `episode_label`.
3. **parse-in adapter** — filename → `EpisodeIdentity`, absolute-first +
   air-date tiebreak. `Parser` stays a syntactic extractor; a new
   resolver maps its result to canonical. Anime filename tests are
   **append-only** ([ADR-027]); cour-2 names (`Frieren - 29`,
   `Frieren S2 - 01`) bind to E29–E38 where resolvable.
4. **query-out adapter** — identity-set → indexer search terms emitting
   absolute + season/episode variants so cour-2 releases are *findable*
   (`Corpus`/`RunPlan` search-term construction).

*Done when:* identity module + adapters with tests; a cour-2 file binds
to the correct TMDB episode; a search for E29 surfaces absolute-named
releases; the broadcast-season best-effort limit is logged, not
mis-bound.

### Phase 3 — Composite pursuit + want↔pursuit linkage

1. **Activate multi-unit pursuits for the tracking/auto path** (lift the
   `Units.single!/1` gate where safe; ADR-055 Phase 3): one pursuit per
   show, units = identities, per-unit satisfy (no whole-pursuit
   cancel/satisfy — builds on `campaigns/pursuit-identity-and-lifecycle.md`).
2. **Want ↔ pursuit linkage** — a want resolves to its pursuit so the
   tracker can answer "out, not in library yet → pursuit."
3. Multi-unit lifecycle tests (per-unit states fold to pursuit state).

*Done when:* Frieren is one composite pursuit with episode units; wants
link to it; landing one episode never cancels the others.

### Phase 4 — Display (show-collapsed, pursuit-linked)

1. `/upcoming` collapses a show to one entity; **separate "catching up"
   (aired-but-missing, pursuit-linked) from "upcoming" (future)** in
   `UpcomingFeed` + components (update stories first per `storybook`).
2. Single canonical identity formatter (`S01E29`).
3. Surface pursuit status + deep-link to the Downloads pursuit; no wall
   of identical "TODAY" cards.

*Done when:* the Frieren case renders as one "catching up" entity with
live pursuit status; stories + page-smoke updated.

## Completion criteria

* `EpisodeIdentity` is the single internal vocabulary; no slice rebuilds
  `(s,e)` ad hoc or parses `"s1e29"` strings outside the identity module.
* A release is credited only with the identities it actually delivers; a
  unit satisfies only when its identity is present in the library.
* A cour-2 (split-season) episode is findable, grabbable, and bindable;
  broadcast-season-named releases degrade to a logged best-effort, never
  a mis-bind.
* The Frieren case end-to-end: one composite pursuit, tracker-linked, one
  collapsed `/upcoming` entity — no re-grab loop, no wall of cards.
* `mix precommit` green; wiki updated where user-visible behaviour
  changed (upcoming "catching up" surface).

## Pointers

* Decision: [ADR-058](../decisions/architecture/2026-06-17-058-canonical-episode-identity.md); ancestors [ADR-055](../decisions/architecture/2026-06-09-055-composite-pursuits.md), [ADR-056](../decisions/architecture/2026-06-10-056-release-tracking-wants.md), [ADR-057](../decisions/architecture/2026-06-14-057-derived-data-is-recomputable.md).
* Acquisition: `acquisition/pursuits/library_reconciler.ex`, `acquisition/jobs/run_plan.ex`, `acquisition/planner.ex`, `acquisition/plans/commit_plan.ex`, `acquisition/drop_planner.ex`, `acquisition/pursuits/{pursuit,unit,units}.ex`.
* Release tracking: `release_tracking/wants.ex`, `release_tracking/want.ex`.
* Library/identity: `parser.ex`, `library.ex` (`find_episode_by_season_episode/3`, `find_present_episode/3`), `library/inbound.ex`, `library/{episode,season}.ex`, `tmdb/mapper.ex`.
* Display: `live/upcoming_live.ex` + `UpcomingFeed`, `live/library_formatters.ex`, downloads unit board.
* Sibling campaigns: `pursuit-identity-and-lifecycle.md`, `plan-solver-consolidation.md`, `residual-driven-descent.md`.
