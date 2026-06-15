---
status: in_progress
started: 2026-06-15
last_updated: 2026-06-15
---
# Engineering Audit Remediation

## Goal

Close the 37 findings from the 2026-06-15 full-tree engineering audit
(`lib/`, ~93k LOC) without letting them sprawl into open-ended rewrites.
The codebase is structurally healthy — zero compiler warnings, no
`Repo.*` in the web layer, no `String.to_atom`, disciplined Boundary
declarations. The findings cluster in three predictable bands: one real
cross-platform crash (`Autostart` seam), a thin band of input-validation
gaps (unguarded `String.to_existing_atom` on params), and copy-paste
between sibling modules that has *already drifted* (release-persistence,
image-download, the setting-aware traits). Fix the correctness band
first, then retire the drift with small shared helpers, then shed
cohesion from the three modules that have outgrown a single file.

## Status

**Session 1 (2026-06-15, unpushed): correctness band + abstractions +
ReleaseTracking split done.** Complete: A1–A5 (correctness),
B1/B2/B3/B4/B5/B6 + B8 (abstractions & dedup), C2 (ReleaseTracking.
Acquisition split), C3/C4/C5 (dead code, schema API, boundary), D3/D5
(readability), E1–E6 (consistency, some documented-as-intentional),
F1/F3 + subtitles_row F2, status_live mount split (D2). All test-first
where behavior changed; full `mix precommit` green at each checkpoint.

**Session 2 (2026-06-15, pushed): library cluster + readability done.**
B7 (per-type fetcher dedup, all 3 rows) + present-file-subquery dedup into
PresentableQueries + **C1** (HomeLive facade → `Library.HomeFeed`,
library.ex 3458→2661) + **D2** (status_live mount split, detail_panel
split) + **F2** subtitles_row. All behaviour-preserving, verified.

**What's intentionally NOT done** (judgment calls, documented inline):
pursuit_status (idiomatic dispatch — @dispatch map is a lateral move),
F2 more_info/detail (would reduce integration coverage), D4 (cosmetic/
risky correlated-subquery rewrite). **Genuinely remaining = D1 only**
(settings_live's 14 section renders → per-section modules — a focused
*attended* sprint on an interactive surface; ~14 cross-module extractions)
plus low-value deferred residues (C2 image, E1 Movie parity, F4, A5/C3).

**Discovered, deferred:** `library_test.exs:234` (list_in_progress N+1
query-count) is order-fragile under full-suite parallelism — passes in
isolation and per-file, intermittently fails full-suite (warm
global/ETS state shifts the baseline). Pre-existing (path untouched this
campaign). Harden into a deterministic measurement (test-suite-stability
follow-up); not blamed on these changes.

## Decisions made

* `2026-06-15` — Campaign opened from the engineering-audit findings; 37
  findings bucketed into six workstreams (A correctness → F test policy),
  executed in that priority order. Audit report lives in the session that
  produced it; this file is the durable backlog.
* `2026-06-15` — The `Autostart` neutral-`state()` fix (A1) **coordinates
  with the active `macos-platform-support` campaign** (whose next item is
  `Autostart.Launchd`). Owned here because it's a live crash on the
  macOS code path that already exists; the macOS campaign consumes the
  neutralized contract.
* `2026-06-15` — Library per-type fetcher consolidation (B7) and the
  `library.ex` HomeLive-facade extraction (C1) are the two largest items;
  they are sequenced last within their workstreams and may spill to a
  follow-on session. Everything else is small-to-medium.

## Next steps

Ordered by workstream; within each, by value/risk.

### A — Correctness ✅ COMPLETE
1. ✅ **A1** Autostart `state()` neutralized to
   `under_supervisor`/`supervisor_available` across behaviour, both impls,
   `settings_live`; per-impl key-set contract tests added. *(coordinates
   w/ macos-platform-support)*
2. ✅ **A2** `release_coverage` en-dash via `(?:-|–)` alternation (chosen
   over `/u` to preserve `\d`/`\b` semantics); red-first tests.
3. ✅ **A3** Shared `LiveHelpers.safe_existing_atom/2` (consolidated the
   status_live copy); upcoming dispatches on the string + `Integer.parse`;
   review forgiving default; settings controls reject unknown; image Oban
   worker whitelists `entity_type` → `{:cancel, {:bad_entity_type, _}}`.
4. ✅ **A4** Shared `Helpers.parse_tmdb_id/1` ({:ok,int}|:error); scanner,
   refresher, wants skip malformed rows instead of crashing.
5. ◐ **A5** `backfill_extra_files/0` batched (shipped). DEFERRED:
   `perform_relinks/2` (operates on small move-batches; relink-campaign
   hot path — batch only if a profile shows it) and `buckets
   rebuild_from_store/0` (bounded by `max_active_buckets`, boot-only,
   sub-ms SQLite, nil-fingerprint crash already fixed — a windowed
   top-N-per-fingerprint SQLite query is disproportionate risk).

### B — Duplication / missing abstractions
6. ✅ **B1** Unified into `SettingAware` on_mount (polarity moved to each
   context's `enabled?/1`; subscribe-once; literal hook name).
7. ✅ **B2** Extracted `Commands.Helpers` (`insert_seeking_target/1`,
   `enqueue_pursue/1`, `fail_current_target/2` — reason parameterized).
8. ✅ **B3** Single `ReleaseTracking.persist_release!/2`; all 4 TV-side
   writers routed through it (drift fixed).
9. ✅ **B4** Shared `Helpers.download_images_async/sync` (3-role idempotent);
   Scanner now gets logos / skips re-downloads.
10. ✅ **B5** Extracted `Pipeline.ProducerQueue.dequeue/3` + `to_messages/2`
    (the byte-identical mechanics); each producer keeps its own dispatch +
    telemetry (image's metric differs).
11. ✅ **B6** Extracted `Playback.PlayableFks` (`resolve/2` + `context_by_url/2`).
12. ◐ **B8** DONE: `count/2` → `ViewModels.Formatting`; `Diagnostics
    .format_seconds` delegates to `Format`. DEFERRED: `max_dt`/`min_dt`
    (trivial one-liners) and settings `toggle_*`/`save_*` families (→ D1).
13. ✅ **B7** Per-type fetcher dedup, done in 3 verified steps (Recently
    Added → Hero → Continue Watching). Recently Added & Hero collapsed
    fully (one `fetch_*/2-3` over a per-type base-query list; Hero's parent
    alias standardized to `:item` so the named present-file subqueries
    compose). Continue Watching deduped only the movies/hoisted pair (#2.5);
    its TV/video/movie_series fetchers are genuinely different (per-type
    progress aggregation) and left as-is. Behaviour-preserving — added
    video_object (recently-added) + tv/movie_series/video_object (hero)
    characterization tests first; N+1 query-count tests stayed green.

### C — Structure
14. ◐ **C3** DONE: removed `compute_child_targets/2` + `child_targets_delta`,
    `Storage.stale?/1`; inlined `plans.ready_plan/1`. DEFERRED:
    `deletion_buffer.reset/1` (tested pure helper, harmless) and
    `maintenance.refresh_movie_series_credits/0` (tested + documented —
    "make private" breaks its tests; removal is a judgment call → confirm).
15. ✅ **C4** Dropped redundant `Entry.upsert_changeset/1` (use create_changeset).
    `Subtitles.create_track/1` was a false positive — already exists.
16. ✅ **C5** Playback reads Library schemas via `fetch_movie/fetch_episode/
    fetch_tv_series`; both modules dropped `Repo` entirely.
17. ✅ **C2** Split `ReleaseTracking.Acquisition` out. The 4 search/track-only
    private helpers moved with it; `broadcast_releases_updated/1` promoted
    public; context keeps thin delegators so all callers are unchanged.
    (Residual noted: track-from-search's image downloader is the same
    2-image no-logo form B4 replaced for Scanner — route through
    `Helpers.download_images_async/3` in a follow-up.)
18. ✅ **C1** Extracted the HomeLive facade into `Library.HomeFeed`
    (list_in_progress / list_recently_added / list_hero_candidates + all
    facade-only helpers; ~800 lines). Context keeps thin delegators —
    callers (Views.* projections, Status) unchanged. library.ex 3458→2661.
    Behaviour-preserving (moved as exact source; 296 home-feed-surface tests
    green). **D4 deferred** (the raw-SQL last_watched `order_by` fragments
    rode along into HomeFeed): converting a correlated-subquery order_by to
    Ecto DSL is tricky and purely cosmetic — the SQL is correct/tested, not
    worth risking Continue Watching's row order. **Bonus done:** the
    `browser.ex` present-file subquery dup (below) was folded into
    PresentableQueries while scoping this.
    --- ORIGINAL NOTE (done) ---
    Relocate the `library.ex` "HomeLive Facade" (`list_recently_added`,
    `list_hero_candidates`, `list_in_progress` + their fetchers/shapers/
    present-file subqueries/`maybe_take`/`maybe_limit`/`overlay_in_memory_progress`/
    `build_in_progress_*`, ~1100 lines) into a `Library.HomeFeed` (or the
    `Views.*` modules) with thin delegators kept in the context (C2 pattern).
    **Feasibility confirmed:** every facade helper is facade-only — the
    cross-file name matches (`browser.ex`, `progress_broadcaster.ex`) are
    *independent* private copies, so the move is clean and behaviour-
    preserving. **ATTENDED:** it's the home page and the real acceptance test
    is "renders identically" — verify with the page open (home_live_test +
    page_smoke + Views tests + Status test are the automated net; the visual
    is the human net). Public API (`list_*`) has callers in the Views
    projections + Status — keep them callable via delegators.
    **Bonus dup found:** `browser.ex:241,256` re-defines
    `tv_series_present_file_subquery`/`video_object_present_file_subquery`
    (copies of library.ex's) — fold into a shared `PresentableQueries` (or
    Library) helper while here.

### D — Readability
19. ✅ **D3** Fixed stale `watching_tracker` "20 seconds" → 10s + docs/playback.md.
20. ◐ **D4** DEFERRED (now in `Library.HomeFeed`). The `last_watched_at`
    `order_by` fragments are correlated subqueries; a DSL conversion is
    tricky and purely cosmetic (SQL is correct + tested). Low value /
    real risk to Continue Watching row order — leave unless it blocks
    something.
21. ✅ **D5** Unpacked the three dense one-liners (`config`, `maintenance`,
    `release_tracking/helpers`).
22. ✅ **D2** DONE: `status_live mount/3` → connected/disconnected;
    `review_live detail_panel/1` (221 lines) → parsed_info / tmdb_match /
    episode_list render helpers (~110-line composition). NOT DONE (by
    judgment): `pursuit_status.ex` — it's idiomatic multi-clause pattern
    dispatch, and the audit's `@dispatch`-map suggestion is a lateral move
    (arguably *less* readable) that risks wrong user-facing statuses for no
    real gain. Left as-is intentionally.
23. ◐ **D1** IN PROGRESS (session 3, attended). Foundation + 4 sections
    done: extracted the shared UI kit (`SettingsLive.Components`:
    settings_row / card_header / field / status_dot / phx_values), then
    moved **Preferences, Services, Language, Library** into
    `SettingsLive.*` render modules (delegated via explicit attrs, matching
    the `Controls` precedent). **settings_live.ex 4607 → 4003.** All
    behaviour-preserving (settings + page_smoke green per step). MC0008
    (loose-attr doc) is the per-section tax — handled inline.
    **REMAINING 8 sections**: updates, system, tmdb, acquisition, pipeline,
    playback, release_tracking, danger. Helper-coupled ones need their
    section-specific render helper relocated first — `connection_status` +
    `path_status` (shared by tmdb/acquisition/pipeline → move to the
    Components kit), `service_card` (system → its module),
    `auto_grab_defaults_form` (acquisition → its module). The rest are
    kit/core-only moves. Each is now a known-pattern mechanical extraction.
    --- ORIGINAL ANALYSIS ---
    `settings_live.ex section_content/1` — DEFERRED as a focused
    sprint. Reality (confirmed): it's **14 pattern-matched clauses** (one
    per section: system ~340 lines, library ~280, acquisition ~260,
    language ~240, danger ~225, …), all in the 4,600-line `settings_live.ex`.
    The section *logic* is already extracted (`Overview`, `SystemSection`,
    `*_logic` are pure modules). Remaining = move each section's **HEEx
    render** out to its module as a render component (cross-module, ~14×,
    each with assign-mapping). NOTE: the existing section modules live in
    `live/settings_live/` (pure-logic, no stories) — a render component
    there is also exempt from MC0009 (which targets `components/**`), so the
    story tax is lighter than first thought; the cost is the volume + per-
    section assign passing. **Attended** because it's an interactive surface
    (update buttons, intervals, toggles) — verify each section renders +
    works in the running app, not just page_smoke. Also absorbs the
    deferred B8 settings `toggle_*`/`save_*` handler families.

### E — Consistency / naming
24. ◐ **E5** DONE: `metadata_stats` init takes `opts`. `rate_limiter` left
    as-is — singleton (`wait/0` hardcodes `__MODULE__`).
25. ✅ **E6** Stale docs fixed: Ingest stage 4, `checker_job` replace form,
    `find_by_external_id/2` cross-ref.
26. ◐ **E1** DONE: documented the deliberate `destroy_bang!` → `:ok`
    contract. DEFERRED: `Movie.update_changeset`/`Library.update_movie`
    parity (net-new API for symmetry; Movie is create-only by design —
    children update via credits/Inbound — confirm before adding surface).
27. ✅ **E2** `link_file_changeset/1,2` → `create_changeset`/`update_changeset`.
28. ✅ **E3** Documented why Start/StartFromPick run their own transaction
    (creation, not mutation — Runner operates on an existing pursuit).
29. ✅ **E4** Documented the deliberate `lead` vs `single!` divergence at
    both `resolve_unit` fallbacks (ADR-055).

### F — Test policy
30. ✅ **F1** Added `json_formatter` (round-trip + error) + `markdown_formatter` tests.
31. ◐ **F2** DONE: `subtitles_row` → pure `language_label/1`. NOT DONE (by
    judgment): `more_info_panel_test` / `detail_panel_render_test`. On
    inspection these are 20+ tests that are genuine *integration* coverage
    (cast-filter cap, meta blocks, TMDB/IMDb link logic across movie/TV);
    the one extractable decision (`filter_crew`) is a trivial one-liner
    where a shared module would be premature, and a story already covers the
    render. Ripping out the render assertions would *reduce* useful coverage
    for a judgment-call policy item (these are component, not `*_live`,
    tests). Left as-is — consistent with the "three lines beat a premature
    abstraction" discipline.
32. ✅ **F3** Deleted the redundant `assert true` home_live test.
33. **F4** `maintenance_test.exs` seed helpers → `TestFactory`. LOW —
    deferred: the helpers attach `:tmdb_collection` external-ids for the
    movie-series case; confirm `create_movie_series(tmdb_id:)` maps the
    same source before switching, or the test silently changes shape.

## Remaining work (next session)

**The one substantial item left:** **D1** — relocate settings_live's 14
section HEEx renders into their `live/settings_live/*` modules as render
components; section_content becomes a thin 14-clause router. Attended
sprint (interactive surface). See item 23 for the confirmed shape.

**Deliberately not doing** (documented why at items 22, 31, 20): D2
pursuit_status, F2 more_info/detail, D4 raw-SQL ordering.

**Low-value deferred residues (confirm-first):** C2 image-downloader
residual (route track-from-search through `Helpers.download_images_async/3`
— it's a behaviour change: adds logos but shifts the post-download
broadcast), A5 (perform_relinks, buckets rebuild — bounded loops), C3
(deletion_buffer.reset, refresh_movie_series_credits — both still tested),
E1 Movie create-only parity (net-new API), F4 (maintenance factory —
:tmdb_collection nuance). **Suite hygiene:** harden the order-fragile
`list_in_progress` N+1 query-count test.

## Completion criteria

* Every backlog item resolved or explicitly deferred-with-reason
  (campaign-closure-by-destination: ship / verify / defer-to-X).
* `mix precommit` green (full suite; the known `list_in_progress`
  query-count flake excepted, confirmed order-dependent not regression).
* No new compiler warnings; `--warnings-as-errors` clean.
* Each correctness fix (A) has a red→green regression test.
* This file removed on completion (git history is the archive, per
  README / ADR-042 amendment).

## Pointers

* Audit report: session of 2026-06-15 (engineering-audit slash command).
* Coordinates with `macos-platform-support.md` (A1 Autostart seam).
* [ADR-027] regression-tests-append-only, [ADR-030] LiveView logic
  extraction, [ADR-042] campaigns convention, [ADR-054] subsystem health.
