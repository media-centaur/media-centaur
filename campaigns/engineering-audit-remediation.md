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

**Workstream A (correctness) COMPLETE** (2026-06-15, unpushed). A1–A5
shipped test-first (red→green): Autostart OS-neutral state, en-dash
classification, param→atom guards, release-tracking parse safety, and
the backfill N+1. Two A5 sub-items deferred-with-reason (see below).
Workstreams B–F remain.

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
6. **B1** Unify `spoiler_free_aware.ex` + `library_card_info_aware.ex`
   into one parameterized `SettingAware` on_mount trait (fixes the
   opposite-default-polarity bug + double-subscribe).
7. **B2** Extract acquisition `Commands.Helpers` (`insert_seeking_target/1`,
   `enqueue_pursue/1`, `maybe_fail_current_target/1`).
8. **B3** Single `persist_releases/2` in the ReleaseTracking context
   (drift fix: `release_type`, `part_tmdb_id` missing in 2 of 4 copies).
9. **B4** Scanner image download → richer `pending_image_downloads` path
   (Scanner-tracked items currently miss logos / re-download).
10. **B5** `Pipeline.QueueDispatch` shared producer mechanics (3 producers).
11. **B6** `Playback.PlayableFks` shared FK-resolution module.
12. **B8** Small verbatim dups: `max_dt`/`min_dt`, `Diagnostics.format_seconds`,
    `count/2`, settings `toggle_*` (8×) + `save_*`-and-test (3×) handlers.
13. **B7** Library per-type fetcher helper (~700 lines, last).

### C — Structure
14. **C3** Delete dead code: `ResumeTarget.compute_child_targets/2` (+
    `child_targets_delta` field), `Storage.stale?/1`, `plans.ready_plan/1`,
    `deletion_buffer.reset/1`; make `maintenance.refresh_movie_series_credits/0`
    private/removed.
15. **C4** Schema context fns: `Subtitles.create_track/1`; drop redundant
    `settings/entry.ex upsert_changeset/1`.
16. **C5** Playback `Repo.get` reach-ins → narrow `Library` accessors
    (`mpv_session.ex:713,726`, `language_context.ex:173,183`).
17. **C2** Split `ReleaseTracking.Acquisition` out of `release_tracking.ex`.
18. **C1** Move `library.ex` HomeLive facade → `Library.Views.*` (large, last).

### D — Readability
19. **D3** Fix stale `watching_tracker.ex:17` "20 seconds" comment + docs (10s).
20. **D4** Raw SQL `fragment` ordering subqueries → Ecto DSL (`library.ex:2826-2961`).
21. **D5** Dense one-liners (`config.ex:550`, `maintenance.ex:287`, `helpers.ex:40`).
22. **D2** Decompose `pursuit_status.ex` (378 LOC), `review_live detail_panel/1`,
    `status_live mount/3`.
23. **D1** `settings_live.ex section_content/1` per-section components (large, last).

### E — Consistency / naming
24. **E5** `metadata_stats.ex` init opts + `rate_limiter.ex:16` register under
    resolved `name`.
25. **E6** Stale docs: `ingest.ex:3` stage number, `checker_job.ex:90`,
    `library.ex:1330` `find_by_external_id/3`→`/2`.
26. **E1** Library bang contract (`destroy_x!` returns) + `Movie.update_changeset`
    / `Library.update_movie` parity.
27. **E2** `link_file_changeset/1,2` → `create_changeset`/`update_changeset`.
28. **E3** Route Start/StartFromPick commands through `Runner.run/3`.
29. **E4** Unify `resolve_unit/2` fallback (`lead` vs `single!`).

### F — Test policy
30. **F1** Add `profile/json_formatter` + `markdown_formatter` tests.
31. **F2** Replace render-HTML assertions in `detail_panel_render_test`,
    `more_info_panel_test`, `subtitles_row_test` with pure-helper tests.
32. **F3** `home_live_test.exs:22` `assert true` → real assertion or delete.
33. **F4** `maintenance_test.exs` seed helpers → `TestFactory`.

## Completion criteria

* All 33 backlog items above resolved or explicitly deferred-with-reason
  (campaign-closure-by-destination: ship / verify / defer-to-X).
* `mix precommit` green (full suite; known concurrency flakes excepted and
  confirmed on `main`).
* No new compiler warnings; `--warnings-as-errors` clean.
* Each correctness fix (A) has a red→green regression test.
* This file removed on completion (git history is the archive, per
  README / ADR-042 amendment).

## Pointers

* Audit report: session of 2026-06-15 (engineering-audit slash command).
* Coordinates with `macos-platform-support.md` (A1 Autostart seam).
* [ADR-027] regression-tests-append-only, [ADR-030] LiveView logic
  extraction, [ADR-042] campaigns convention, [ADR-054] subsystem health.
