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

**Remaining = the home-page query cluster + judgment-heavy items**,
deliberately left for an attended session (see "Remaining work"): B7
(library fetcher dedup) + C1 (HomeLive-facade → Views) + D4 (raw SQL) —
all the same hot-path query area, unsafe to verify unattended; D1
(settings sections); D2 remainder (pursuit_status, detail_panel); F2
remainder (more_info, detail); plus small deferred sub-items.

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
13. **B7** Library per-type fetcher dedup (~700 lines). LARGE/HIGH-RISK —
    ~15 near-identical `from |> Repo.all |> preload |> map(&shape_*)`
    fetchers across recently-added / hero / in-progress; the
    "container-present?" subquery is reimplemented ≥5× with differing
    aliases. Approach: standardize the parent alias to `:item` so the named
    present-file subquery composes into hero; extract
    `fetch_typed(query, shaper, preload, limit)` + a per-type query/shaper
    table. CAUTION: this is the home-page hot path AND the area of the
    order-fragile N+1 test — change in small steps, run page_smoke + the
    in-progress/hero/recently-added tests after each. Best paired with C1.

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
18. **C1** Move the `library.ex` "HomeLive Facade" (~`:2167-3270`, ~1100
    lines of `poster_url`/`progress_pct`-shaped maps) → `Library.Views.{
    ContinueWatching, RecentlyAdded, HeroCandidates}` (the `Views.*` structs
    already exist). VERY LARGE — do alongside B7 (same fetchers). Move
    function + its tests together; `home_live_test` + `page_smoke` are the
    safety net. The context should return data, not LiveView-shaped maps.

### D — Readability
19. ✅ **D3** Fixed stale `watching_tracker` "20 seconds" → 10s + docs/playback.md.
20. **D4** Raw SQL `fragment` ordering subqueries → Ecto DSL (`library.ex`
    in-progress fetchers, `last_watched_at` ordering). MEDIUM/RISKY —
    same hot-path query code as B7 and the order-fragile N+1 test; the
    `exists(...)` filters above prove it's expressible in DSL. Do it with
    B7 so the query area is touched once, not twice.
21. ✅ **D5** Unpacked the three dense one-liners (`config`, `maintenance`,
    `release_tracking/helpers`).
22. ◐ **D2** DONE: `status_live mount/3` split into connected/disconnected.
    REMAINING: `pursuit_status.ex` (378-LOC state machine → `@dispatch` map
    or sub-module — real regression risk, attended) and `review_live
    detail_panel/1` (200+ lines → file/tmdb/search sub-panels). Lower
    priority than structure.
23. **D1** `settings_live.ex section_content/1` (~`:1593-4668`, ~14 HEEx
    sections in one fn) → per-section components. VERY LARGE — the
    extraction pattern already exists (`settings_live/overview.ex`,
    `system_section.ex`); each new component needs an MC0009 story. Also
    absorbs the deferred B8 settings `toggle_*`/`save_*` handler families.

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
31. ◐ **F2** DONE: `subtitles_row` → pure `language_label/1` test (story
    covers the row structure). REMAINING: `more_info_panel_test` and
    `detail_panel_render_test` — larger (multiple decisions; a `filter_crew/2`
    duplicated byte-for-byte across movie_credits/series_credits that a
    public extraction would both dedup and make testable). Per-component
    design work, attended.
32. ✅ **F3** Deleted the redundant `assert true` home_live test.
33. **F4** `maintenance_test.exs` seed helpers → `TestFactory`. LOW —
    deferred: the helpers attach `:tmdb_collection` external-ids for the
    movie-series case; confirm `create_movie_series(tmdb_id:)` maps the
    same source before switching, or the test silently changes shape.

## Remaining work (next session)

**Large structural (attended — home-page hot path, can't verify render
unattended):** B7 + C1 + D4 (library fetcher dedup / HomeLive-facade →
`Library.Views.*` / raw-SQL ordering — all the same query area, do
together in small verified steps), D1 (settings-section components).
**Medium (attended judgment calls):** D2 remainder (pursuit_status state
machine, detail_panel split), F2 remainder (more_info/detail → pure
helpers; bundle the `filter_crew/2` dedup), C2 image-downloader residual
(route track-from-search through `Helpers.download_images_async/3`).
**Low / confirm-first:** A5 residue (perform_relinks, buckets rebuild),
C3 residue (deletion_buffer.reset, refresh_movie_series_credits), E1
Movie create-only parity, F4 (maintenance factory). **Suite hygiene:**
harden the order-fragile `list_in_progress` N+1 query-count test.

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
