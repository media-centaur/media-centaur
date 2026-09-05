---
status: in-progress
started: 2026-09-04
last_updated: 2026-09-05
---
# Audit remediation — September 2026

## Goal

Work off the findings of the four-audit sweep of 2026-09-04 (engineering,
performance, documentation, design) in discussable steps. The engineering
lane goes first; the other three lanes are staged here so nothing from the
sweep is lost, and each gets elaborated when its turn comes. Every stage is
scoped to be discussed in one sitting and resolved in the next.

## Working agreement

**Discuss a stage before resolving it.** Each stage carries an *Open
questions* block for the owner. The loop per stage:

1. Read the stage. Verify its facts still hold (`git log` plus the cited
   file:line) — the reconciliation rule applies per stage.
2. Bring the open questions to the owner and agree an approach.
3. Implement test-first, `mix precommit` green.
4. Update this file — move the stage to **Done**, append to *Decisions
   made* — and stop. Do not roll into the next stage unasked.

Lane order: **Engineering (E) → Performance (P) → Documentation (D) →
Design (DS)**. Within a lane the order below is recommended, not required.
Finding IDs (`E7`, `P1`, `D20`, `DS4`) are the audit's own; the raw audit
output was chat-only, so the evidence recorded here is the surviving copy.

**A count is not a fix** (August's lesson, eight clauses in
`git show 70ee6d2c`): reproduce before naming a cause, check the premise
every option shares, and when a probe names a module confirm the module is
running.

## Status

Engineering Pass 1 (E1–E6), Pass 2 (E7–E18) and Pass 3 (E19–E28)
resolved 2026-09-04 in the commits from `a661eea7` onward (plus E36, E41,
and the polling half of P2, which those passes pulled in). Reviewed and
ratified by the owner. Those 17 commits are **pushed** and shipped — they
rode out in v1.8.0/v1.8.1 alongside the HTTP campaign; `2ddd4b53` (v1.8.1)
is HEAD. Full `mix precommit` is green apart from the suite's known
concurrency flakes (relay timeout, "Database busy", a 60 s page-smoke
timeout), each passing in isolation. Sweep run 2026-09-04 against
`7e1df187` (v1.7.3): 57 engineering, 10 performance, 42 documentation, 25
design findings. Criticals: P1; DS4, DS14, DS15, DS16, DS25.

**Pass 4 part one done 2026-09-05** — Stage E-2's precommit items
(D13, E52, E42, E53) and Stage E-3's E56 dead-code batch, in commits
`3c764d2d`, `9dc0fb83` and `6200e014`.

**Pass 4 part two done 2026-09-05 — Stage E-5 resolved**, eight local,
**unpushed** commits `40b63794..c723c6c8` (E40/E37/E27, E32, E29, E31,
E38, E39, E30, E35 — see the stage). Full `mix precommit`: 6593/6594
Elixir + 795 JS; the one failure was the known
`Nostr.ConnectionTest` retry-log flake, green in isolation. **The
engineering lane is done except straggler E45**; the Performance,
Documentation and Design lanes remain.

## Resuming — start here (handoff written 2026-09-05)

**Reconcile first (ADR-042), but the expensive parts are already done.**
`git log 3c764d2d^..HEAD` is the 2026-09-05 work: thirteen commits on
`main`, **local and unpushed**. Confirm nothing was pushed or rebased
since, then pick up at *What's next* below. Do not push or tag without
being asked.

### Closed — do not re-audit these

* **The 2026-09-04 handoff's HTTP-convergence item.** No divergence
  existed: the parallel Req task built *on* `0a40c933` rather than
  replacing it. `HttpClient.new/2` is the one client-construction seam
  (Credo MC0029), `config :media_centaur, :req_test_stubs` the test stub
  seam, `Capabilities.save_integration/2` the one save path,
  `Capabilities.configured?/1` the one configured predicate;
  `invalidate_client/0` has zero occurrences and `Acquisition.Config`
  stays deleted. **E8/E9/E11 hold as ratified.**
* **E14 and E36** — verified closed 2026-09-05. All seven contexts
  (Acquisition, Downloads, HttpClient, Search, SelfUpdate, Social, TMDB)
  declare `@behaviour ...IncidentContext`, and the `function_exported?`
  structural probing is gone from `error_reports/incident_context.ex`.
  Pass 2 closed them; the stage text below still lists them as evidence.
* **E33, E41, E42, E52, E53, E56, D13, E49** — done. E33's
  `Watcher.record_seen/1` was *kept*: the showcase seeder still calls it.
* **E6** — closed in `a661eea7` (Pass 1); no `DDR-015` citation remains.
  The earlier handoff listed it as a straggler in error.
* **Stage E-5, all of it** — E29, E30, E31, E32, E35, E37, E38, E39, E40,
  E27. Commits and module map in the stage section. E34 stays deferred
  (Stage E-10).

### What's next: straggler E45, then the Performance lane

**E45 (Stage E-7 test policy):** `test/media_centaur/library/progress_test.exs`
drives `Library.Progress.Worker` by `GenServer.cast/call` against its own
moduledoc — either give the worker a public seam the test can use, or
extend MC0004 to catch the pattern. Discuss before resolving (working
agreement).

Then the lanes in order: **Performance** (elaborate P1–P10 into stages;
P3/P7 one-liners first, P1 last), **Documentation** (D-1 first),
**Design** (DS-1, DS-2 first). Each lane's findings and evidence are
below, unchanged since the sweep — re-verify line numbers before acting.

Still owed from Pass 2: a real-browser check of the Status page pipeline
tiles during an import on the dev server (`127.0.0.1:2160`), event-driven
since E18.

### Module map after Stage E-5 (so nobody re-derives it)

| Was | Now |
|---|---|
| `Library.FileEventHandler.delete_*` / `cleanup_removed_files` | `Library.Deletion` (handler is PubSub-only) |
| ReleaseTracking's Library schema queries | `Library.Episodes.ids_by_season_episode/1`, `last_season_episode/1`; `Library.Containers.existing_ids/2`, `list_tv_series/2`; `Library.ExternalIds.movie_ids_for_tmdb_ids/1` |
| `Maintenance.*_on_boot/1` | `MediaCentaur.BootHeal` |
| `Maintenance.clear_database/0` internals | `Review.clear_all/0` + `Library.EntityCascade.destroy_all!/0` |
| `Settings.Config.images_dir_for/1`, `staging_base_for/1`, `image_dirs_needing_monitoring/0`, `resolve_image_path/1` | `Library.ImageCache.dir_for/1`, `staging_dir_for/1`, `dirs_outside_media_dir/0`, `resolve_path/1`; Config's `:media_dir_images` holds **explicit overrides only** |
| `Library.Image.web_path/1` | `MediaCentaur.ImageFiles.web_path/1` |
| `Review.search_tmdb/2` | `Review.Search.tmdb/2` |
| `Review.Intake.create_pending_file/1`, `complete_review/1`, `receive_files_for_review/1` | `Review.add_pending_file/1`, `complete_review/1`, `add_files_for_review/1` |
| `Watcher.Supervisor.scan/0`, `rescan_unlinked/0` (+`_async`) | `Watcher.Rescan.*`; `Supervisor.watchers/0` lists `{dir, pid}` |
| `Plans.board_for/1` | `Plans.Board.build/1` |
| `Plans.alternatives_for/1`, `search_alternatives/1`, `gap_evidence/1`, `choose_rejected/2`, `choose_release/2` | `Plans.Alternatives.for_unit/1`, `search/1`, `gap_evidence/1`, `choose_rejected/2`, `choose_release/2`; `Plans.fetch_unit/1` public |
| `Refresher` library-event handlers | `ReleaseTracking.LibraryListener` → `ReleaseTracking.library_entities_changed/1` (`LibraryLinks.refresh_for/1` + `complete_movie_tracking_for/1` inline, `AutoTrackJob` → `AutoTrack.run/1` on the `:acquisition` queue) |
| `SelfUpdate.service_*` re-exports | callers use `Platform.Autostart` directly |
| `TargetEvents.event?/1` / `Pursuits.Events.event?/1` in a `cond` | `is_event/1` guards on `handle_info` heads |

### House rules this campaign added — respect them

* **MC0032** — one *top-level* module per `lib/` file. Nested submodules
  are the house pattern and stay legal.
* **MC0033** — a `Log.*` tag must equal its context's component per
  `MediaCentaur.Log.Component`. Add a context to that table rather than
  fighting the check. Adding a *component* also needs a `.chip-<name>` in
  `assets/css/app.css` and a `mix assets.build` (watchers are off).
* **Renumbered checks:** RawBadgeClass **MC0010**, DestructiveFileQuery
  **MC0030**, PursuitStateContract **MC0031**. MC0008 is typed component
  attrs, MC0015 is row-mutation-in-schema-migration.
* `EntityModal`'s blanket `handle_async` exit clause is now injected by
  `@before_compile`, so a host LiveView can handle its own async failures.
  **DS16 is half-done**; the rest (logging the swallowed exit, the files
  sub-view's `:loading | {:ok,_} | :failed` assign) is Stage E-8.

**Incremental `mix compile` does not re-check Boundary for modules it
did not recompile.** A missing `deps:`/`exports:` entry can pass an
incremental compile and only surface on `mix compile --force` (it
happened twice in Stage E-5). Force-compile once before committing any
change that adds a cross-context reference.

Known suite flakes (pass alone, fail under load): Nostr connection and
one-shot timeouts, `Mix.Tasks.Social.DevTest` relay timeout, "Database
busy" in `IncomingLiveTest` setup, a 60 s page-smoke timeout. None
appeared in the 2026-09-05 full run. **Do not run two `mix test` runs
concurrently** — they share the test DB and produce ~25 bogus failures
across unrelated suites.

## Decisions made

* `2026-09-04` — Four-audit sweep run; campaign created with the
  engineering lane first, other lanes staged for later elaboration.
* `2026-09-04` — Owner directed: resolve engineering Pass 1, then Pass 2
  and Pass 3 under the `unify_design` skill, commit as we go, review
  before continuing. The stage grouping below stays as the map of what
  remains; the pass order is what was executed.
* `2026-09-04` — **E7 decided: the entity-map is the read contract, typed.**
  `Library.EntityView` is one struct that both adapters fill in full
  (`DetailItem.to_entity_view/1` from the projection,
  `EntityShape.to_entity_view/2` from a record). Task E (consumers on
  `%DetailItem{}`) was rejected: playback and the Browse rebuild read the
  database by design (ADR-041), so two sources into one typed view is the
  coherent shape, not a compromise.
* `2026-09-04` — **E9 decided: an integration client is a function of its
  settings.** Drivers take `%ClientConfig{}` per call; TMDB, Prowlarr and
  the drivers build their Req client per call; `invalidate_client/0` is
  gone everywhere. Tests reach `Req.Test` through `MediaCentaur.HttpClient`
  and `config :media_centaur, :req_test_stubs` instead of writing clients
  into `persistent_term` — two tests that had been quietly hitting the
  real TMDB API surfaced and were stubbed.
* `2026-09-04` — **Owner review: all five Pass 1–3 decisions ratified**
  (E7 EntityView, E9/E11 integration clients and save path, E19/E26
  corpus keying, E23 compat layers removed, E18 pipeline stats
  broadcasts). A parallel task is reworking the Req client setup;
  reconciling it with commit `0a40c933` stays the first item under
  *Next steps*. Campaign **paused** at the owner's request after review.
* `2026-09-04` — **E11 decided:** `Capabilities.save_integration/2` is the
  one save path (blank secrets leave the value, a change clears the test
  result); `Capabilities.configured?/1` the one configured predicate.
  `Acquisition.Config` deleted.
* `2026-09-04` — **E18 decided:** `Pipeline.Stats` and `Image.Stats`
  broadcast a coalesced `{:pipeline_stats_updated, :content | :image}` on
  `pipeline:stats` (≤1 per 500 ms, none idle); Status and Library pages
  subscribe. This also resolves the polling half of **P2**; the
  `retrying_count` DB read now runs only on image-pipeline updates.
* `2026-09-04` — **E12:** Pipeline declares its dependency on Review
  (`PendingFile.parsed_attrs/1`); it was already building Review's row.
* `2026-09-04` — **E19/E26 decided: the corpus keys on the term (plus
  `:year`).** `:type` never reached Prowlarr, so two keys held one result
  set and the commit path had to guess which — every movie approve
  missed and grabbed without an infohash. Ladder terms are plain strings;
  `QueryBuilder`/`CourQueries` keep `{query, opts}` because `:year` is a
  real option; `CommitPlan.rehydrate/1` reads the assigned term alone.
  `Search.SearchProvider` (E41) deleted with it. `commit_plan_test.exs`
  pins the landed target's infohash and quality.
* `2026-09-04` — **E24 decided without a migration:** a `:movie` tracking
  item linked to a `MovieSeries` is a TMDB collection; any other movie
  item is one film. The link already carried the answer, so the
  Refresher dispatches on it instead of probing `/collection` first.
* `2026-09-04` — **E23 decided: all of it goes.** `watch_dirs` now stops
  the boot with the fix named; the cwd `data/` fallbacks, the
  `body_excerpt` fallback, `Acquisition.Artwork`, `Playback.Iso639`, the
  `/download`, `/upcoming` and `?section=` redirects, and the artwork-
  layout boot migration (shipped 2026-08-11) are removed. Nothing in the
  README, docs-site or wiki linked the retired routes.
* `2026-09-04` — **E22:** `OwnerRef`'s per-type shorthand lives with the
  fixtures as `TestFactory.OwnerRef`; production writes the owner pair.
* `2026-09-04` — **E28 partial:** the `Watcher.Reconciler` moduledoc keeps
  describing the unreachable `to_replace` case until Stage E-3's E56
  collapses the branch; `Reconciliation`'s deferred-follow-ups moduledoc
  stays (deliberate: its campaign was retired per ADR-042).
* `2026-09-04` — **Storybook:** the detail stories build `%EntityView{}`
  fixtures; the components read struct fields with dot access.
* `2026-09-05` — **D13 decided by citation weight.** `TypedComponentAttrs`
  keeps MC0008 and `RowMutationInSchemaMigration` keeps MC0015, because
  that is what every existing doc, plan and migration comment means by
  those ids. `RawBadgeClass` → MC0010, `DestructiveFileQuery` → MC0030,
  `PursuitStateContract` → MC0031. `check_registry_test.exs` holds ids
  unique from here on; writing it surfaced that `event_chokepoint.ex` is a
  shared AST matcher, not a check, and correctly carries no id.
* `2026-09-05` — **E52 decided: a ref to match on is not ownership.**
  MC0019 now covers `async_nolink` and `async_stream_nolink` as well as
  `start_child`, and does not require the supervisor in the first argument
  (a pipe moves it). Fixing the two sites required moving `EntityModal`'s
  blanket `handle_async(_name, {:exit, _}, …)` into a `@before_compile`
  hook — injected by `__using__` it preceded every host clause, so no host
  could handle its own async failure and `SettingsLive`'s own exit clause
  was already unreachable. That is **DS16's mechanism**; DS16 proper
  (logging the swallowed exit, the files sub-view's loading state) stays
  in Stage E-8.
* `2026-09-05` — **E42 decided: siblings, not nesting.** Enforced to the
  letter of AGENTS.md the new MC0032 flagged 43 files, but 38 were nested
  submodules — `Library.Events.EntitiesChanged` in `library/events.ex`,
  the view-model and component item structs — which is the house pattern
  and is namespaced by the file's own module. The check holds one
  *top-level* module per `lib/` file; AGENTS.md line 90 was rewritten to
  say that, since its old wording had been contradicted 38 times by its
  own codebase. Test files stay exempt.
* `2026-09-05` — **E53 decided: one table, everything derives.**
  `MediaCentaur.Log.Component` owns the component vocabulary and the
  owning-context map; Console's chip row, grouping, chip classes and
  crash attribution all read it, and MC0033 holds a `Log.*` tag to its
  context's component. The map is many-to-one on purpose (downloads,
  search and release_tracking all log as `:acquisition`). `:review`,
  `:apps` and `:settings` became components; `:retention` folded into
  `:library` and `:integration_health` into `:system`. A Nostr crash now
  carries `:nostr` — the fold onto the friends tile is `HealthBoard`'s
  job, and doing it twice meant the Console could not filter Nostr
  crashes at all.
* `2026-09-05` — **E56: two entries were wrong.**
  `ReleaseTracking.create_release/1` stays — it is how the identity unique
  index is asserted, and removing it would weaken those tests to
  `assert_raise`. `Watcher.record_seen/1` stays — the showcase seeder
  still calls it. Everything else in the batch went, plus E49's four
  leftovers on `SettingsLive.ConnectionTest`. The Reconciler's
  `to_replace` branch was confirmed *unreachable* (the only caller keys
  `id` on `dir` and nils `images_dir` on both sides), which also finishes
  E28's deferred moduledoc clause.
* `2026-09-05` — **HTTP convergence resolved with no rework.** The
  parallel HTTP/Req task extended the E9 seam instead of competing with
  it; `HttpClient.new/2` + `:req_test_stubs` + `save_integration/2` is
  the single design, and MC0029 now enforces the construction seam.
* `2026-09-05` — **Stage E-5 resolved** in eight commits (`40b63794`
  E40/E37/E27, `dbed960f` E32, `0f6f66e8` E29, `04e6f7e8` E31,
  `fda56205` E38, `f5ed36ea` E39, `2b864d0d` E30, `c723c6c8` E35).
  Decisions inside the stage: `Config.media_dir_images` now stores only
  explicit `images_dir` overrides, `Library.ImageCache` owns the default
  layout; the `/media-images/` prefix belongs to `ImageFiles`, not a
  Library schema; Config's TOML-parsing tests reimplemented the parser
  in the test file and were rewritten against `Config.load!/0` (the
  "legacy `media_dir` key" test was fictional — Config never supported
  that key — and was deleted); auto-track network work runs on the
  `:acquisition` Oban queue; `Plans.fetch_unit/1` became public so
  `Plans.Alternatives` could share it. **E6 found already closed** in
  `a661eea7`.
* `2026-09-04` — **Declined for now:** the three Settings-key separator
  styles (Pass 1 minor). Renaming persisted keys needs a data migration
  for a cosmetic gain; revisit if a fourth style appears. **E34**
  (god-module LiveViews) untouched per Stage E-10.

---

# Engineering lane

## Stage E-1 — Movie approve rehydrates under the wrong corpus key

**Why first.** A user-visible correctness gap in the one module that gates
every grab, hidden by a fallback chain and not covered by any test.

**Evidence.**
* **E19 (H)** `lib/media_centaur/acquisition/plans/commit_plan.ex:166-183`
  — `rehydrate/1` looks the assigned candidate up under
  `Corpus.candidates_for(term, type: :tv)`, then `candidates_for(term, [])`.
  Movie terms are keyed `type: :movie` (`plans/ladder_terms.ex:75-78`;
  `Corpus.search_key/2` at `corpus.ex:188-200` folds `@keyed_opts [:type,
  :year]` into the key; `run_plan.ex:476,558` records with those opts). Both
  lookups miss for every movie; the fallthrough builds a `%SearchResult{}`
  with no `info_hash`/`magnet_url`/`download_url`/`protocol`/`size_bytes`,
  so `InfoHash.resolve/1` returns nil (no grab-time infohash, pairing
  degrades to title matching) and `ReleasePicked` records "Unknown" quality
  and no size.
* **E46 (M)** No `commit_plan_test.exs`; approve is reached only via
  `plans_test.exs` and nothing asserts the persisted `torrent_hash` on a
  movie approve.
* **E26 (M)** `search/prowlarr.ex:122-123` builds `[query:, type: "search"]`
  and ignores the `:type` opt that `acquisition.ex:245-247` and
  `search/search_provider.ex:14-16` document and `Corpus` keys on
  (`corpus.ex:37`). Identical HTTP queries land under two cache keys.

**Approach.** Red-first test: approve a movie plan, assert `torrent_hash`
and quality on the target. Key the rehydrate lookup on the plan's own type;
delete the `[]` fallback. Then decide `:type` for Prowlarr: map it to
categories, or remove it from the docs and `@keyed_opts` (which collapses
the corpus-key split that caused E19).

**Open questions for the owner**
* Prowlarr `:type`: implement the category narrowing, or drop the option?
* Are existing movie targets with nil infohash worth a one-time backfill,
  or do they age out?

**Verification.** New `commit_plan_test.exs` red → green; approve a real
movie plan on the dev server and read the target's `torrent_hash` via the
context.

---

## Stage E-2 — Things `mix precommit` should catch and doesn't — **DONE 2026-09-05**

**Why.** CLAUDE.md prefers code-as-spec. Each item below is a rule the
repo already states in prose that a check could hold.

**Evidence.**
* **E53 (M-H)** Log component tags disagree with the Console's model:
  ~23 sites in Acquisition (`targets.ex:127,147,311`;
  `jobs/pursue_target.ex:88,148,304-362`; `acquisition.ex:403`), Downloads
  (`queue_monitor.ex:351`), ReleaseTracking (`refresher.ex:102-527` ×13;
  `scanner.ex:16,27`), TmdbArtwork (`tmdb_artwork.ex:355-391`), Review
  (`review.ex:426-518`, `review/intake.ex:91-118`),
  `Pipeline.ImageRepair`/`ImageRefresh` (`image_repair.ex:53-196`,
  `image_refresh.ex:68,89`) and `settings/config.ex:347,498,550` all tag
  `:library`. `console/view.ex:10-25` `@known_components` lacks `:review`,
  `:release_tracking`, `:self_update`, `:apps`, `:retention`, `:settings`,
  `:integration_health` — five are used today and unfilterable.
  `console/entry.ex:164` maps SelfUpdate crashes to `:self_update` while
  every deliberate SelfUpdate log tags `:system`; `:161` maps WatchHistory
  crashes to `:library` while `watch_history/recorder.ex:56-63` logs
  `:playback`.
* **E52 (M)** MC0019 loophole: `live/library_live.ex:213` and
  `live/settings_live.ex:606` use `Task.Supervisor.async_nolink` (matching
  `{ref, result}`/`:DOWN` clauses at `:314`, `:1301`);
  `credo_checks/owned_async_in_web.ex:67-70` matches only `:start_child`.
* **E42 (L)** `profile/suites/{continue_watching,recently_added,coming_up,
  hero_candidates,watch_history_summary}_suite.ex` each define two modules;
  AGENTS.md forbids it; nothing enforces it.
* **D13 (M, cross-lane)** Credo check IDs collide:
  `credo_checks/raw_badge_class.ex:3` and `typed_component_attrs.ex:3` both
  `id: "MC0008"`; `destructive_file_query.ex`, `pursuit_state_contract.ex`,
  `row_mutation_in_schema_migration.ex` all `id: "MC0015"`. Every doc
  citation of those IDs is ambiguous.
* **E6 (L)** "DDR-015" cited in `router.ex:64`, `components/layouts.ex:175`,
  `incoming/status_pill.ex:6`, `incoming/shelf.ex:3`,
  `live/incoming_live.ex:3`, UIDR-017/018. The record is **UIDR-015**.
* **E45 (M)** `test/media_centaur/library/progress_test.exs:111-112,253-257`
  drives `Progress.Worker` via `GenServer.cast/call` while its own moduledoc
  (lines 12-14) denies it; MC0004 covers only `:sys`.

**Approach.** `Console.View.@known_components` becomes the single list
(crash table and `@app_components` derive from it); retag by owning
context. Extend MC0019 to `async_nolink`/`async_stream_nolink`; replace the
two sites with `start_async`/`handle_async`. Add
`credo_checks/one_module_per_file.ex`. Renumber the four colliding checks
(MC0010 is free, then MC0029+) and update citations. `sed` DDR→UIDR. For
E45: a public write seam + `flush/0` in `Progress`, or extend MC0004 to
`GenServer.call/cast` in `test/` with a grandfather entry.

**Resolved.** The owner chose the Credo check over a one-time sweep, so
E53 is permanent: MC0033 reads `Log.Component`'s owning-context table.
D13, E52 and E42 landed with it (`3c764d2d`, `9dc0fb83`). **Still open
in this stage: E6** (DDR-015 → UIDR-015 citations) and **E45** (seam or
check for `Progress.Worker` being driven by `GenServer.cast/call` from
its own test) — neither was in this sitting's scope.

**Verification.** `mix precommit`; each new/extended check demonstrated to
fire against a deliberate violation before it lands (August clause 3).

---

## Stage E-3 — Retire the Schema-v2 leftovers and dead code — **E56 DONE 2026-09-05**

**Why.** The first engineering rule is "no compatibility layers or
fallbacks". Library Schema v2 closed 2026-05-17; its temporary shims are
now load-bearing, and ~400 lines of verified dead code sit beside them.

**Evidence.**
* **E7 (H)** Two producers of the polymorphic entity-map.
  `library/views/detail_item.ex:405-410` ("temporary compatibility shim —
  Task E retires it"), `library/entity_shape.ex:54-93`,
  `library/progress_records.ex:207-211`. `DetailItem.to_entity_map/1`
  and `EntityShape.to_view_model/2` build the same bare map;
  `ProgressRecords.list_for_container/2` and `EntityShape.extract_progress/2`
  the same progress list. Web/ModalEntry/ProgressBroadcaster consume the
  first pair; Browser and the Playback resolvers (`resolver.ex:76-77,
  139-140,245-257`, `next_episode.ex:49-50,91`) the second. Every detail
  component's attr doc now says "entity-map produced by `to_entity_map/1`".
* **E22 (M)** `library/owner_ref.ex:9-11` `normalise/2` serves only
  fixtures; call sites `library/images.ex:26,39`, `extras.ex:32`,
  `external_ids.ex:115`; `test/support/factory.ex:86,98,153,421-425`
  already normalises.
* **E23 (M)** Compat inventory: `settings/config.ex:540-557` "permanent"
  `watch_dirs` fallback; `plugs/image_server.ex:118-124`
  `find_in_legacy_data/1`; `tmdb_artwork.ex:404-407` cwd `data` fallback
  (its own `root/0` refuses it); `self_update/storage.ex:144-150`
  `body_excerpt` fallback + unknown classification → `:up_to_date`;
  `acquisition/artwork.ex` argument-order shim; `playback/iso639.ex`
  defdelegate shim with duplicate test file
  `test/media_centaur/playback/iso639_test.exs`;
  `controllers/legacy_redirect_controller.ex` + `router.ex:63-69` and
  `settings_live.ex:253-258` section aliases (judgment);
  `tmdb_artwork.ex:309-362` + `release_tracking.ex:496-513` self-retiring
  artwork-layout boot migration (shipped 2026-08-11).
* **E16 (L-M)** Year-from-date ×5: `format.ex:48-49`, `date_util.ex:9-11`,
  `live/library_formatters.ex:73-85`, `components/detail/logic.ex:141-156`
  (both "retained for legacy storybook fixtures"; `poster_card.story.exs:297`
  now passes a `Date`), `components/detail_panel.ex:543`;
  `test/media_centaur_web/components/detail/logic_test.exs:179-191` pins
  the dead clauses.
* **E49 (L)** `settings_live/connection_test.ex:23-53,83-92` `parse/1`,
  `serialize/1`, `stale?/2`, `storage_key/1` — only caller is
  `connection_test_test.exs:60-109`; persistence moved to `Capabilities`.
* **E41 (L)** `search/search_provider.ex` has no dispatch site
  (`acquisition.ex:252`, `corpus.ex:539`, `commit_plan.ex:146`,
  `pursue_target.ex:288` call Prowlarr directly).
* **E33 (M)** `watcher.ex:149-152` `record_seen/1` = `Library.Files.link/1`,
  sole caller `showcase.ex:1235`; `test/media_centaur/watcher/record_seen_test.exs`.
* **E37 (L)** `self_update.ex:224-247` re-exports five `Platform.Autostart`
  functions consumed only by `settings_live.ex:334,446,465,488`.
* **E56 (M, batch)** Dead with zero `lib/` callers (tests only where noted):
  `watcher/supervisor.ex:405-410` `media_dir_healthy?/0`;
  `library/last_activity.ex` whole module;
  `library/availability.ex:36-46,220-238` `available?/1`,
  `entity_media_dir/1`, `entity_file_path/1`, `longest_prefix/2`;
  `library/browser.ex:111-179,231-274` `fetch_typed_entries_by_ids/2` +
  five `*_by_ids` fetchers, `:97-99` `apply_sort(:alpha)`;
  `maintenance.ex:284-310,458-465` `refresh_movie_series_credits/0` +
  `library/movie_series.ex:103-114` `update_credits_changeset/2`;
  `pipeline/stats.ex:96-124`, `pipeline/image/stats.ex:79-96`
  `empty_snapshot/0`; `watcher/reconciler.ex:59-69` `to_replace` branch
  (unreachable, see `watcher/supervisor.ex:47-54,81-83`);
  `library/change_log.ex:26-28,37-39` 1-arity `record_*`;
  `library/episode_list.ex:114-123` `find_content_url/3`;
  `pipeline/image_queue_entry.ex:34-37` owner_type `"entity"`;
  `acquisition.ex:222` `queue_snapshot/0`; `release_tracking.ex:452`
  `open_wants_summary/0` + `wants.ex:102-111`; `release_tracking.ex:63-65`
  `track_item!/1`, `:271-273` `create_release/1`, `:440`
  `dismiss_wants_before/2` + `wants.ex:118-130`;
  `downloads/download_client.ex:48` `list_downloads/1` + both impls
  (`qbittorrent.ex:52-74`, `sabnzbd.ex:70-85`, exercised only by
  `showcase/stubs_test.exs`); `pursuits/watcher.ex:130-134`,
  `pursuits/snapshots.ex:78-82` `rescue _ -> :unknown` around a
  `:persistent_term` read.

**Approach.** Decide the entity-map once (below), then a deletion pass with
each item's test. `watch_dirs`: read `media_dirs` only and raise at
`load!/0` naming the rename if `watch_dirs` is present.

**Resolved.** All three questions were answered in Pass 3 (E7 EntityView,
E23 "all of it goes"). E56, the dead-code batch, landed 2026-09-05 in
`6200e014` — with two entries corrected: `create_release/1` and
`record_seen/1` are not dead. Nothing remains in this stage.

**Verification.** `mix precommit`; `grep` confirms zero callers of each
deleted symbol; MC0023 grandfather list may only shrink.

---

## Stage E-4 — Configuration and integration state, derived once

**Why.** ADR-029: contexts own their data. Four copies of "is Prowlarr
configured?" already disagree, the web layer writes Settings rows the
context owns, and the Setup tour and Settings page save the same keys with
different rules.

**Evidence.**
* **E8 (M)** `capabilities.ex:225-236`, `acquisition/config.ex:15-20`,
  `downloads.ex:133-140`, `integration_health.ex:210-217` — the last checks
  only the Prowlarr API key, not the URL: key-only Prowlarr shows
  "configured" with a `:pending` test forever.
* **E9 (M)** `downloads/client_config.ex:5-8` built by the Dispatcher;
  `download_client/qbittorrent.ex:231,252-253` and `sabnzbd.ex:154,180`
  re-read `Settings.Config`; `integration_health/verifier.ex:45-47`
  documents the workaround.
* **E10 (M)** `live/settings_live.ex:733-838` nine `toggle_*` handlers
  flip → `Settings.find_or_create_entry!`; `"letterboxd_links"` (`:737`)
  and `"spoiler_free_mode"` (`:770`) are literals while
  `Settings.Preferences.LetterboxdLinks` / `SpoilerFree` own the keys.
* **E11 (M)** `settings_live.ex:928-1076` save_* recipes vs
  `setup_live.ex:164-226,305-336` (writes only-if-changed, never clears the
  persisted test result). `start_async_test/3` (`:2740`) goes with it.
* **E17 (L)** `"services:#{env}:#{service}"` composed in
  `settings_live.ex:2811`, `application.ex:302`,
  `acquisition/auto_grab_service.ex:51`.
* **E21 (M)** `settings_live.ex:351-357` gates `assign_update_snapshot` on
  `connected?` although `SelfUpdate.view_status/0` is a pure cache read
  (ADR-051); `console_live/shared.ex:39-50` same shape.
* **E48 (L-M)** ADR-030 extractions: `setup_live.ex:164-226`,
  `review_live.ex:187-201`, `status_live.ex:421-466` (duplicates
  `EntityModal.handle_modal_pubsub/2` at `entity_modal.ex:369`),
  `incoming_live.ex:1329-1345`, `settings_live.ex:1079-1093`.

**Approach.** `Capabilities.prowlarr_configured?/0` / `client_configured?/1`
public, three private copies deleted. Drivers take `%ClientConfig{}`.
`BooleanSetting.set/2` + one `toggle_preference` handler.
`Capabilities.save_integration/2` (write → invalidate → clear test) used by
both views. `Settings.Services.key/1` + `set/2`. Drop the two `connected?`
guards.

**Open questions for the owner**
* Where does `save_integration` live: `Capabilities` or `Settings.Config`?

**Verification.** `mix precommit`; Setup tour and Settings save the same
Prowlarr key and both clear the stale test result.

---

## Stage E-5 — Context boundaries that drifted from their moduledocs — **DONE 2026-09-05**

**Why.** Boundary is honest where it is declared; these are the places the
declaration or the moduledoc claims a design the code lacks.

**Evidence.**
* **E29 (H)** ReleaseTracking queries six Library schemas
  (`release_tracking/wants.ex:386-399,413-420,451-458`,
  `release_tracking/helpers.ex:81-95`,
  `release_tracking/refresher.ex:421-422,451-463`) while
  `release_tracking.ex:28` says "Fully isolated from the Library context".
* **E30 (M)** `refresher.ex` = two timers + a Library-events reactor;
  `do_auto_track_tv_series/3` (`:485-529`) does TMDB HTTP inside
  `handle_info`, blocking during imports.
* **E31 (M)** `maintenance.ex:11-13` "operator-driven destructive
  operations" vs credits refresh (`:393-395`), subtitle backfill
  (`:504-515`), three `*_on_boot/1` heals (`:621-677`); deps list lacks
  `Review` — bare module atom in `resources_in_delete_order/0` slips past
  Boundary.
* **E32 (M)** `library/file_event_handler.ex:1-16` GenServer hosting plain
  `delete_*` functions (`:44-93`) called from `live/entity_modal.ex:1450-1485`,
  `live/review_live.ex:303`, `review.ex:309`.
* **E36 (M)** `console.ex:3` depends on all of SelfUpdate for
  `console/journal_source.ex:312` → `SelfUpdate.detected_unit/0` →
  `Platform.Autostart.detected_unit/0`. Closes the cycle that forces
  **E14 (M)**: `error_reports/incident_context.ex:36-47` behaviour fulfilled
  "structurally" via `function_exported?` by Downloads, Search, Acquisition,
  SelfUpdate, Social; only TMDB declares it.
* **E35 (M)** `status_live.ex:117-135` reads eleven subsystems directly and
  subscribes to ten topics (`:40-50`); only `overview`/`storage` go through
  `Status.Views`; `docs/architecture.md` calls `Status` "composition only";
  `status.ex:50` reads `Library.list_recently_added/1` from the DB
  instead of `Views.recently_added/1`.
* **E38 (L-M)** `settings/config.ex:370-412` owns image-directory layout
  (`images_dir_for/1`, `image_dirs_needing_monitoring/0`,
  `staging_base_for/1`, `resolve_image_path/1`); `apps/artwork.ex:16,83`
  reaches into `Library.Image.web_path/1`.
* **E39 (L-M)** `review.ex:48-50,127-129,357-393` + `review/intake.ex:32-105`
  ("Public API" on a PubSub GenServer; `FileReviewed` broadcast from both
  `:62` and `review.ex:395-397`); `watcher/supervisor.ex:9,14,17,366-393`
  runs Ecto; `acquisition/plans.ex` (886 lines) domain dividers.
* **E40 (L)** `library/continue_watching_progress.ex:16` `top_level?: true`
  hatch for `components/library_cards.ex:12,113`; `search.ex:3` declares
  `Capabilities` unused; `profile.ex:7` declares `Watcher` unused;
  `integration_health.ex:3` depends on all of Acquisition for
  `Acquisition.test_prowlarr/0`; `library.ex` exports `Writes` unused.
* **E27 (L)** `incoming_live.ex:2206-2236` `handle_info` dispatches on
  struct via `cond`.

**Approach.** Library exposes `present_episode_ids_for_series/1`,
`movie_ids_for_tmdb_ids/1`, `last_episode_for_series/1`,
`container_ids_existing/2`; ReleaseTracking drops schema imports.
`ReleaseTracking.LibraryListener` + Oban job for auto-track network work.
`Library.Maintenance.clear_all/0` + `Review.clear_all/0`; boot heals to
`Library.BootHeal`. `Library.Files.delete_*` (or `Library.Deletion`).
JournalSource → `Platform.Autostart`, then `@behaviour IncidentContext`
on all six. Status: finish the projection migration or amend the doc.

**Both open questions answered 2026-09-05 — do not re-ask.**
* **E35 → amend `docs/architecture.md`.** Describe the Status page that
  exists rather than building eleven projections for reads that aren't hot.
* **E39 → all three splits now**, as part of this stage.

**E14 and E36 in the evidence above are already closed** (verified
2026-09-05): all seven contexts declare `@behaviour IncidentContext` and
the `function_exported?` probing is gone. Current line numbers for the
rest are in the *Resuming* section — the audit's originals have drifted.

**Verification.** `mix boundaries` + `mix precommit`; each moduledoc names
one thing.

**Done 2026-09-05.** Commits `40b63794` (E40, E37, E27), `dbed960f`
(E32), `0f6f66e8` (E29), `04e6f7e8` (E31), `fda56205` (E38), `f5ed36ea`
(E39), `2b864d0d` (E30), `c723c6c8` (E35). The module map in *Resuming*
records where every moved function went. `mix precommit` 6593/6594
(known Nostr flake, green alone) + 795 JS.

---

## Stage E-6 — Duplication sweep and vocabulary

**Evidence.**
* **E12 (M)** `search_params/1` ×3: `pipeline/discovery.ex:177-203`,
  `pipeline/stages/search.ex:43-49`, `review/intake.ex:142-160`;
  PendingFile attrs assembled twice.
* **E13 (M)** `library/home_feed.ex:305-336` vs `459-493`;
  `:324-333,421-426,475-486` vs `progress_records.ex:335-350` vs
  `progress_summary.ex:21-30`.
* **E15 (L-M)** `pad/1` ×4 (`plans.ex:205`, `run_plan.ex:638`,
  `drop_planner.ex:345`, `ladder_terms.ex:83`) with `Format.pad2/1` present;
  `scope_display` ≡ `scope_label`; `unit_label/3` ×2.
* **E24 (M)** `release_tracking/refresher.ex:186-208` tries
  `/collection/{id}` then `/movie/{id}` — one guaranteed 404 per solo movie
  per cycle; `release_tracking/item.ex:15-18` claims `:movie → :movie_series`
  1:1 while `track_from_search` creates container-less items.
* **E25 (M)** `release_tracking/acquisition.ex:164-183` older 2-image
  downloader with a NOTE saying the newer path is a follow-up.
* **E20 (M)** `pipeline/image_refresh_worker.ex:15-18` whitelists
  `"episode"`; `pipeline/image_refresh.ex:93-96` has no `:episode` clause —
  raises and Oban retries, the exact thing the comment says it prevents.
* **E18 (L)** `:tick_pipeline` 1 s poll in `status_live.ex:58,376-387` and
  `library_live.ex:67,305-310` (also **P2** — resolve together).
* **E2 (L)** `topics.ex:165-166` `friends_updates/0`/`friends_connections/0`
  → `social_*`. **E3 (L)** `:warn` vs `:warning`
  (`status_widgets/system.ex:22-23,102`, `status_widgets/acquisition.ex:107-147`).
  **E4 (L)** `status.ex:59-66` `fetch_*` returning bare values.
  **E5 (L-M)** `tmdb_artwork.ex:395-396` `{:ok, nil}` on failure.
* Minor: `Pipeline.Stats`/`Pipeline.Image.Stats` same GenServer twice;
  `image_repair.ex:37,207-266` re-derives TMDB CDN URLs; `queue_item.ex:236-240`
  verbatim copy of `Pursuits.Identity.normalize_title/1`; `progress_width/1`
  ×3; `downloads/health.ex:148-180` user copy in a context;
  `Settings.destroy_entry/1`; Settings-key separators ×3;
  `watch_history.ex` says `WatchEvent`.

**Open questions for the owner**
* E24: add `:movie_collection` to the enum (paired safe migration +
  idempotent backfill) or accept the extra TMDB call?

---

## Stage E-7 — Test policy

**Evidence.**
* **E43 (M)** `test/media_centaur_web/page_smoke_test.exs:39-43` mounts
  `?subsystem=friends` (board has `:social`) → tests the bare page;
  `watcher`, `tmdb`, `playback`, `acquisition`, `social` drill-ins and
  `/discovery`, `/guide`, `/guide/:slug` have no smoke.
* **E44 (M)** Six fixed-sleep tautologies: `home_live_test.exs:128`,
  `watch_history_live_test.exs:193`, `incoming_live_test.exs:2653,2989,3003,3252`.
* **E47 (L)** Hand-rolled `on_exit` restores in `page_smoke_test.exs:566,659`,
  `apps_live_test.exs:23`, `settings_live_update_automation_test.exs:36-37`,
  `settings_live_test.exs:428`, `settings_live_system_test.exs:51`,
  `setup_live_test.exs:19`, `settings_live_exclude_dirs_test.exs:28`;
  `Availability.__reset_for_test__/0` (`availability.ex:150-162`) and
  `shell_badges.ex:36-39,96-100` test-only resets in `lib/`.
* **E50 (L)** `issue_url_test.exs:2,90-92` async + `Application.put_env`;
  real title in `confidence_test.exs:13-15`, `exclude_dirs_test.exs:58`;
  `recommendations/sync_test.exs:167-169` sleeps after `assert_receive`.
* **E51 (L)** MC0023 grandfather list stale: `maintenance_test.exs:27-42`
  and the pursuits files have factory builders available.
* ADR-027: `0dbb5a21` loosened `assert is_integer(delay) and delay > 0` in
  `test/media_centaur/pipeline/producer_test.exs` — restore.
* Five private poll-with-deadline helpers → one `TestSupport.eventually/2`.

---

## Stage E-8 — Failure paths that go silent

Pairs with design lane **DS16/DS17**; resolve together.

**Evidence.**
* **E54 (M)** `reconciliation.ex:279-293` `else _ -> :error`;
  `reconciliation/spine.ex:31-33,43-45` `{:error, _} -> []` (rejected TMDB
  key becomes "no proposals"); zero `MediaCentaur.Log` calls in
  Reconciliation. `review.ex:184-206,265-286` reduces changeset errors to
  a count; `self_update/storage.ex:158` corrupt `published_at` → "now".
* **DS16 (Critical)** `live/entity_modal.ex:331`
  `handle_async(_name, {:exit, _}, socket)` swallows the detail-files task
  crash; Manage panel renders "0 files, 0 B" as if true.
* **DS17 (M)** `review_live.ex:418-421` and `settings_live.ex:1722-1725`
  catch-all exits leave `searching`/`*_testing` flags `true` → buttons stuck.
* **DS21 (M)** `manage_panel.ex:221,577-579` "0 files, 0 B" while loading.

**Approach.** Per-task `handle_async` exit clauses: reset the flag,
`MediaCentaur.Log` (reaches Status), flash; `:loading | {:ok, _} | :failed`
assign for the files sub-view. `Log.warning` at each Reconciliation
branch (Discovery's 401/403 routing at `pipeline/discovery.ex:76-90` is
the model).

---

## Stage E-9 — Stale moduledocs and the code-side glossary

**Evidence.**
* **E28 (M, batch)** `downloads/health.ex:186-187` "nothing reads this"
  (read by `incoming_live/logic.ex:326`); `watch_history_live.ex:47-56`
  describes a task load that no longer exists; `library/views.ex:59-60`
  "alphabetical" vs `inserted_at desc`; `downloads.ex:27-43`, `search.ex:45`,
  `search/search_provider.ex:5`, `showcase/stubs.ex:7-9` name modules and
  functions that don't exist; `acquisition.ex:340,367`,
  `acquisition/targets.ex:24,90,133,261` document positional tuples
  replaced by `%TargetEvents.*{}`; `acquisition/target.ex:6-7`,
  `acquisition.ex:95-97` cite `current_target_id` (gone since ADR-055);
  `settings_live/connection_test.ex:11-13`, `console.ex:7`, `storage.ex:13`,
  `integration_health.ex:17-19`, `console_live/shared.ex:14,21`,
  `library/extra_progress.ex:7-8`, `watcher/reconciler.ex:6-8`.
* Minor: `reconciliation.ex:58-92` campaign follow-ups in a moduledoc;
  `incoming_live.ex:239-248,2527` orphaned comments; `home_live.ex:39-44`
  duplicated sentence; `boolean_setting.ex:8-9` "Four flags" (ten).
* **E1 (M)** / **D36 (M)** `docs/GLOSSARY.md` covers Apps and Social only.
  Undefined project terms: entity/entry, container, playable item,
  rendition vs cut, presentable, pursuit, target, plan, unit, ladder,
  descent, residual, offer, pack, want, hoist, entity-map, presented_as,
  pillar, source vs derived topic, projection, capability, incident/bucket,
  ladder/gate/profile, zone, tier, orientation, straggler.

**Approach.** One sweep; prefer deleting counts-in-prose to correcting
them. Glossary: one row per term with the owning module/ADR, acquisition
family first.

---

## Stage E-10 — The two event god-modules (deferred by default)

**E34 (M)** `settings_live.ex` 2,914 lines / 81 `handle_event` clauses /
26 direct `Config.update`; `incoming_live.ex` 3,121 lines / 65 handlers /
~70 mount assigns of which 20 are `plan_*`. E-4 removes ~250 lines first.
Incremental approach if taken: per-section `handle_event/3` delegated by
event prefix; a `%PlanState{}` struct for IncomingLive's plan cluster.
**Owner call whether this stage exists.**

---

# Performance lane (to elaborate when reached)

Runtime snapshot 2026-09-04: 787 processes, 169 MB, 0 LiveViews, all
queues 0; 17 series / 732 episodes / 28 movies / 800 images; every hot
column indexed; profiling baseline `priv/profiling/baseline-small.*`
(2026-05-20, Elixir 1.19/OTP 28) is stale versus the current toolchain —
rebaseline before the next `scripts/profile` diff.

* **P1 (Critical)** Detail projection partial refresh is O(N²) during a
  series import. `library/views/detail.ex:158-171` (`Enum.each(ids,
  &rebuild_row/1)`), `:824-846`, `:469-483`, `:700-706` + `:1093-1136`,
  `:572-582`; trigger `library/inbound.ex:89` broadcasts the top-level id
  per episode, `library/playable_items.ex:139-147` expands to all items.
  161-episode series ≈ 1,600 queries + ~48 MB ETS copy per flush; ~161
  flushes per season pack. Fix: group by `grouping_key`, build like
  `build_all_items/0` (`:454-466`), one shared insert + one broadcast per
  flush.
* **P2 (M)** `status_live.ex:58,376-387,674-680` 1 Hz `COUNT(*)` on
  `pipeline_image_queue` + three GenServer calls while open;
  `library_live.ex:67,305-310` same tick. (= E18.) Fix: event-driven or
  conditional tick; move `retrying_count` into RetryScheduler state or the
  Overview projection.
* **P3 (M)** Oban Stager at default 1 s takes the SQLite write lock forever
  at idle (`config/config.exs:74-116`). Fix: `stager: {Oban.Stager,
  interval: :timer.seconds(10)}`.
* **P4 (M)** `settings_live.ex:328` mounts `Maintenance.missing_images_summary()`
  → `image_health.ex:62-78,98-112` stats every image file, twice per
  navigation (13 ms at 800 images, linear). Fix: read from
  `Status.Views.Overview`; live probe via `start_async` from the Repair
  button only.
* **P5 (M)** `acquisition/corpus.ex:94-131` one autocommit per search
  result. Fix: `insert_all` with `on_conflict` in one transaction. (= E55.)
* **P6 (M)** `plans/commit_plan.ex:185-215,218-230` 3–4 unwrapped writes
  per unit, no atomicity; `plans.ex:633-638` already does it in one
  transaction. Keep the `Prowlarr.grab` HTTP call outside.
* **P7 (M)** `cache/worker.ex:63-84` — seven workers retain ≈36 MB of
  rebuild garbage. Fix: `{:noreply, state, :hibernate}` after refresh.
* **E55 (M)** further per-row writes: `release_tracking/wants.ex:162-173,
  248-266,366-383`; `library/file_event_handler.ex:215-232,264-271`
  per-episode delete; `pipeline/image/retry_scheduler.ex:79-86,98-100`
  while `ImageQueue.update_statuses/2` exists; `library/change_log.ex:44-54,91`.
* **P8 (Minor)** `console/buffer.ex:180-184` `Enum.take` per log line.
  **P9 (Minor, droppable)** `status.ex:51-52` `length(list)` counts.
  **P10 (Minor, droppable)** `library_live.ex:118-137,566-571` grid
  re-stream per filter patch.

Suggested order: P3, P7 (one-liners) → P2+E18, P4 → P5, P6, E55 → P1.

# Documentation lane (to elaborate when reached)

Forcing-function surfaces are current (wiki to the day, `decisions/README.md`,
config docs). Everything else describes the app as of roughly April–June
2026. Recurring cause: prose copies of facts whose authority is code
(`Topics`, `Events` moduledocs, `router.ex`, `application.ex`,
`Diagnostics`, `credo_checks/`). Durable fix: fewer copies, more pointers.

**D-1 Campaign hygiene (cheap, first).** **D18 (H)** `campaigns/README.md:24-33`
says friends-recommendations is in design; it shipped v1.6.0–v1.7.2 —
close or rewrite. **D19 (M)** macOS README entry contradicts its file
(Phases 1–6 shipped 2026-05-21; only a real-Mac smoke remains).

**D-2 Skills and commands that misdirect every session.**
**D20 (H)** `user-interface` skill: page table describes retired `/` zones,
UIDR table stops at 011, modal recipe binds `phx-click-away` (banned by
MC0006), inventory names `cw_card/1`, `track_modal.ex`, `upcoming_cards.ex`
(none exist), `format_iso_duration/1` missing, theme-toggle contradiction.
**D21 (H)** `media-library` skill: every function in its table
(`fetch_movie_with_associations/1`, `find_by_external_id/2`, …) is
undefined; real: `Library.Containers.fetch_with_associations/2`,
`ExternalIds.find_by_external_id/2`. **D22 (H)** `troubleshoot` skill +
`scripts/troubleshoot:100,266` call `Diagnostics.log_recent/1`, undefined
— the script's default health check raises. **D23 (H)** `parser-rule`
command queries `WatchedFile` for parse fields that live on
`Review.PendingFile`. **D24 (H)** `gen-docs` command targets a `backend/`
repo that no longer exists — delete. **D25 (M)** `automated-testing`
(`?zone=` smoke rule, `:image_downloader`, `Pipeline.process_payload/1`,
three nonexistent helpers), `coding-guidelines` (`Watcher.AbsencePolicy`,
`DownloadImages`), `input-system` (`dashboard`; DevTools MCP contradiction
with `design-audit.md:155-156`), `storybook` (`Mix.env() == :dev`; `~> 1.0`).
**D15 (L, droppable)** CLAUDE.md skill names lack the `elixir:` prefix.

**D-3 Subsystem docs that state retired contracts.**
**D1 (H)** `docs/library.md` — WatchedFile `state`/`absent_since`,
WatchProgress keyed by season/episode, `library_identifiers`,
`Library.Identifier`, `Library.Removal`; `PlayableItem` absent.
**D2 (H)** `docs/playback.md` — positional `playback_state_changed`,
`child_targets_delta`, 60 s save (is 10 s), classifier categories,
`Playback.DisplayEnv`, `WatchProgress.upsert_progress`. **D3 (H)**
`specs/DATA-FORMAT.md` — `Library.Browser.list_entries/0` shape invented,
under a "spec wins" rule. **D4 (H)** `docs/pipeline.md` — image-queue
handoff misattributed (`{:enqueue_images, …}`, producer creates rows),
payload table, supervisor list. **D5 (H)** `docs/input-system.md` —
`home_behavior.js`, `upcoming` zones, `data-section-type`,
`data-nav-zone-value`, `MediaCentaur.Controls.Catalog`. **D6 (M)**
`docs/architecture.md` supervision tree + Library schema list + contexts
table; **D39 (H)** links `friends.md` ×3 (is `social.md`). **D7 (M)**
`Topics` moduledoc lacks `integration_health:updates`,
`reconciliation:updates`, `:browse`/`:search`/3-tuple `:detail`,
`:recommendation_deleted`. **D8 (M)** `docs/watcher.md`; **D9 (M)**
`docs/tmdb.md` scoring formula; **D10 (M)** `specs/IMAGE-CACHING.md`;
**D11 (M)** `docs/mpv.md` HDR recovery block + menu; **D28 (M)**
`docs/social.md`, `GLOSSARY.md` `:synced` state, `social-protocol.md:105`
`oldest - 1`; **D29 (L)** `docs/storybook.md` triage table + dead anchor;
**D38 (L, droppable)** historical residue.

**D-4 Public surfaces.** **D16 (H)** README/docs-site say "pre-1.0" at
v1.7.3; README "UI overhaul in progress" table lists pages that don't
exist. **D17 (M)** README + docs-site omit Discovery/Watchlist, Apps,
friends' recommendations; `feature-release-tracking.html` sells the
Upcoming calendar. **D26 (H)** wiki `Installation.md:78` "There is no
auto-update" — false. **D27 (M)** wiki Settings paths (`Overview`,
`Language & Subtitles`), missing Maintenance/Data-directory cards, TOML
seed. **D37 (L)** wiki "entity" ×9, "floor", "Phoenix LiveView". **D42 (L)**
README doc links all point at wiki root.

**D-5 Placement/duplication/hygiene.** **D32 (M)** precommit description
×3 diverged (CLAUDE.md, AGENTS.md:103-104, CONTRIBUTING.md:28). **D33 (M)**
test policy duplicated across two skills, disagreeing. **D34 (M)**
AGENTS.md:41-46 prescribes "smooth page transitions" that UIDR-012
forbids. **D12 (M)** AGENTS.md `current_scope`/auth boilerplate,
storybook "dev-only", `touch_stream_entries`/`reset_stream` as helpers.
**D14 (L)** CONTRIBUTING `bun test assets/js/input/`, port 1080.
**D35 (L)** troubleshoot skill release section. **D30 (L)** UIDR-010 no
amendment note, ADR-058 `superseded` vs `amended`, UIDR-021 no status.
**D40 (M)** UIDR-015:85 "ADR-006" → UIDR-006. **D31/D41 (droppable)**.

# Design lane (to elaborate when reached)

Verified: one theme, Heroicons only, glass tiers respected, no hardcoded
colors, clean consoles on all 13 routes, 24 of 29 UIDRs compliant in code.
Screenshots from the sweep were in the session scratchpad only; re-shoot
with `page-shot --viewport 1920x1080 --wait-ms 3000` when the stage opens.

**DS-1 Input-system runtime contract (two Criticals).**
**DS4 (Critical)** daisyUI `.card` base `outline: 2px solid #0000` +
`app.css:1610-1620` pre-set `outline-color: primary` on `[data-nav-item]`
= every poster card (`library_cards.ex:53`) shows a permanent primary
outline in keyboard/gamepad mode; focused and unfocused compute
identically, so the cursor is invisible on the library grid. Probe:
`/library` with `data-input="keyboard"`, all cards
`outline: oklch(0.62 0.16 250) solid 1.9px`. Fix: zero the outline on
`.card[data-nav-item]:not(:focus)` under keyboard/gamepad (or drop `card`
from `poster_card`); switch selection at `:55` from `ring-2` to inset; bun
or E2E assertion on computed `outline-width`. Only the live DOM exposed
this.
**DS14 (Critical)** `components/modal.ex:55-66` never emits
`data-detail-mode`; `dom_adapter.js:25,315` recognises overlays only via
`[data-detail-mode='modal']`; only `incoming_live.ex:3032` adds it by hand.
Clear-database (`settings_live.ex:2488-2492`, `:persistent`), recommend
(`recommend_modal.ex:32-38`, zero nav items), apps-manage
(`apps_live.ex:211-218`), history Removed (`watch_history_live.ex:129-135`)
are d-pad traps. Fix: `<.modal>` emits `data-detail-mode` and
`data-dismiss-event` itself; `data-nav-item` on every control inside.
**DS19 (M)** `review_live.ex:975,1004,1029,1039,1044,1088,891` TMDB search
panel mouse-only. **DS20 (M)** `discovery_live.ex:294-304,325`,
`roster_block.ex:34-41,47-64`, `config.js:269-272` scope toggles + Friends
tab outside any zone.

**DS-2 Readable-text contrast.** **DS25 (Critical)** `text-base-content/40`
(155 sites), `/30` (36), `/35` (7), `/45` (5) all `text-xs`/`text-sm`;
composited `/40` = 3.22:1 on base-100; `/50` (219 sites) = 4.21:1
borderline; `/55` = 4.75, `/60` = 5.38. Skill prescribes `/50` headers
and `/60,/40,/20` hierarchy, so the drift is systemic. Fix: floor readable
text at `/55`+, reserve `/40` and below for separators/icons/disabled;
update the skill; Credo check on `text-base-content/(2|3|4)0` outside an
allowlist.

**DS-3 Destructive actions without the arm (MC0027 tier 2).**
**DS15 (Critical)** `reconcile_live.ex:107-114,245` "Dismiss all" —
`Reconciliation.dismiss_awaiting` per file, no restore path.
**DS18 (M)** `review_live.ex:121-128,765-771` Dismiss All;
`settings_live.ex:1270-1273` + `controls.ex:33-39` Reset all controls;
`watch_history_live.ex:311-320,401-419` delete then post-hoc modal, row
button lacks `data-nav-item`; `title_modal.ex:177-185` Stop tracking;
`pursuit_activity.ex:108-116`, `decision_card.ex:85` Cancel pursuit while
the orphan-queue cancel on the same page is modal-gated. Fix: one shared
armed-button pattern.

**DS-4 Failure paths** — DS16, DS17, DS21: handled in **Stage E-8**.

**DS-5 UIDR compliance.** **DS1 (M)** colored left borders
(`health_components.ex:36-37`, `status_widgets/acquisition.ex:39,146-148`)
— banned accent-bar idiom. **DS5 (M)** UIDR-001 end-truncated paths
(`settings_live/library.ex:84-95,190`,
`library_overview_components.ex:174,290`, `manage_panel.ex:397`,
`setup_steps.ex:330`). **DS6 (M)** UIDR-013 form dialogs `:ephemeral`
(`settings_live.ex:2544-2548`, `apps_live.ex:211-217`). **DS7 (M)**
UIDR-002 solid badges for state (`orphan_queue.ex:54-61`,
`logic.ex:478-489`, `plan_modal.ex:256`). **DS8 (M)** UIDR-012 `:for` roots
without ids (`review_live.ex:554,566,589`, `season_list.ex:172,264`,
`incoming_live/search.ex:52`; minor `media_results.ex:135`,
`review_live.ex:935`, `extras_section.ex:44`, `cast_panel.ex:247`).
**DS9 (Minor)** three `primary` buttons in one section
(`system_settings.ex:97,299,327`); Manage toggle never flips to Back
(`view_controls.ex:176-191`) vs UIDR-003 — pick one. **DS10 (Minor)**
`items-center` on mixed-size rows ×5. **DS24 (M)** UIDR-029: two
sentence-makers on the plan board (`incoming_live.ex:2779-2780`,
`plan_modal.ex:733-739`, `descent_narrative.ex:58-89`) — add a searching
world to `GapVerdict`, delete `DescentNarrative.headline/1`.

**DS-6 Consistency and states.** **DS12 (M)** three h1 sizes and two
alignment models across pages (`library_live.ex:388`, `settings_live.ex:1832`
3xl; `status_live.ex:586` etc. 2xl; `discovery_live.ex:289`,
`apps_live.ex:152` lg; containers `max-w-5xl`/`3xl`/`6xl` vs left-aligned)
— one `<.page_header>` + a rule for centering. **DS22 (M)**
`home_live.ex:238-246` bare-sentence empty state on a fresh install.
**DS2 (Minor)** `root.html.heex:11-13` title "MediaCentaur · Media Centaur"
on 10 of 13 pages — assign `page_title` everywhere. **DS13 (Minor)**
`style="z-index: 60;"` ×3. **DS23 (Minor)** history empty state.
**DS3, DS11 (droppable).**

---

## Next steps

0. ~~Reconcile the Req client seam~~ — done, no divergence (2026-09-05).
1. ~~Stages E-1 through E-5~~ — done (E-4's E14/E36 closed by Pass 2).
2. **E45** (test drives `Progress.Worker` by `GenServer.call/cast`) —
   discuss seam vs. MC0004 extension, then resolve. E34 and the rest of
   Stage E-10 stay deferred by default.
3. Elaborate the Performance lane into stages (P3/P7 one-liners first,
   P1 last) once the engineering lane is done or paused.
4. Documentation lane, D-1 first (it is the cheapest and the README entry
   is actively misleading a resuming session).
5. Design lane, DS-1 and DS-2 first.

## Completion criteria

* Every non-droppable finding is resolved, explicitly declined with a
  dated decision, or handed to a named campaign.
* Each new mechanical rule (E-2, DS-2) has been shown to fire against a
  violation before landing.
* Stale-doc fixes replace prose with pointers wherever the fact has a
  code authority.
* `campaigns/README.md` reconciled; this file removed on close (ADR-042).

## Pointers

* Previous sweep: `campaigns/audit-remediation-2026-08.md` (removed —
  see `git show 70ee6d2c` and `git log -- campaigns/audit-remediation-2026-08.md`).
* Audit commands: `.claude/commands/{engineering,performance,docs,design}-audit.md`.
* ADR-029 (data decoupling), ADR-041 (projections), ADR-049 (owned async),
  ADR-051 (first paint), UIDR-012, UIDR-018/020 (nav outline), MC0027.
