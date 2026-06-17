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

**Phase 1 is effectively complete with that one fix.** Investigation of
the lifecycle (`IdentityVerifier`, `Policy.evaluate/1`) shows the re-grab
loop is now closed by three independent gates: (1) no false-satisfy
(reconciler fix); (2) the active pursuit *claims* E29–E38 so `DropPlanner`
creates no new plans; (3) `Policy.evaluate` returns `:no_action` for a
succeeded-but-unsatisfied unit, so the pursuit never re-grabs. The
`IdentityVerifier` primary path was already identity-strict
(`landed_unit` matches the published episode's exact `(season, episode)`),
so only the safety net needed the guard.

**Reclassified to Phase 2 (not a standalone Phase-1 item):**
*record-tried-on-no-new-coverage* and the *solver assigning a "Season 01
COMPLETE" pack to cover E29* (coverage-by-name in the **planner**). With
the loop already stopped, these only matter once re-search/solving is
numbering-aware — so they belong with the Phase-2 adapters, not as a
symptom-patch now.

**Interim behaviour (acceptable, honest):** a mis-grabbed episode unit
sits active+claimed at `:no_action` — "still pending," never falsely
"got it" — until Phase 2 makes the real cour-2 releases findable. After a
dev recompile the solver may grab the wrong S1 pack *once* more (planner
coverage-by-name), then settle into that quiet pending state; no loop.

**Still open:** dev re-verify — the `mc_dev` node runs pre-fix code
(manual iex; recompile/restart needed to load the guard).

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

### Phase 1 — Coverage-by-contents (stop the loop; no schema churn) ✅

The narrowest fix that ends the re-grab loop on real data, independent
of the identity refactor. **Shipped** (commit `37ab987e`).

1. ✅ **Red→green:** a unit for `S01E29` is not satisfied when a landed
   pack imported only E1–E28 (`library_reconciler_test.exs`,
   "coverage-by-contents").
2. ✅ **Satisfaction is identity-present, not folder-present.** Guard in
   `LibraryReconciler.landed_file/5`: a TMDB-tv unit with `(season,
   episode)` is satisfied **only** by `tmdb_match` (its own episode in the
   library); the coarse content-path/release-folder fallbacks stay for
   identity-less units (movies, `prowlarr_query`). The `IdentityVerifier`
   primary path was already identity-strict, so only the safety net needed
   the guard. 219 pursuit tests green; existing pack/movie behaviour intact.
3. **Dev re-verify** (still open): recompile the `mc_dev` node and confirm
   the false-satisfy is gone and pursuits settle to pending, not looping.

*Reclassified to Phase 2* (no standalone loop remains after the gates
above): record-tried-on-no-new-coverage, and the solver's coverage-by-name
(assigning a `Season 01 COMPLETE` pack to cover E29). The one-time
reconcile sweep is dropped — the wants are correctly open; the real fix is
findability in Phase 2.

*Done when:* red→green reconciler + planner tests; dev no longer
re-selects the wrong pack; no schema migration required.

### Phase 2 — First-class `EpisodeIdentity` + edge adapters

1. ✅ **`EpisodeIdentity` value module** (`lib/media_centaur/library/episode_identity.ex`,
   pure, `async: true`, 6 tests): `{series_tmdb_id, season, episode}`,
   `absolute_ordinal/2` (derive from TMDB season counts, Specials excluded),
   `to_key/1` (the `"s1e29"` form), `label/1` (`"S01E29"`). Boundary-exported
   from Library; Acquisition + ReleaseTracking already dep on Library.
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
5. **match-in coverage-by-contents in the *planner*** — the solver must
   credit a pack with the identities it *actually* covers (by absolute
   range / air-window), not by its season label, so a `Season 01
   [2023-2024] COMPLETE` pack is never assigned to cover E29
   (`planner.ex` consolidation/assignment). *(folded in from Phase 1)*
6. **record-tried-on-no-new-coverage** — once re-search is numbering-aware,
   a release that delivered nothing for a unit is added to
   `tried_release_guids` so it's excluded on the next attempt. *(folded in
   from Phase 1; harmless no-op until re-search exists)*

*Done when:* identity module + adapters with tests; a cour-2 file binds
to the correct TMDB episode; a search for E29 surfaces absolute-named
releases; the solver never assigns a pack outside its real coverage; the
broadcast-season best-effort limit is logged, not mis-bound.

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
