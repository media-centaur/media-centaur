# Audit Backlog

Remaining items from the `/audit-all` run on 2026-04-05. The top 5
cross-cutting improvements (Ash→Ecto docs drift, dead log API purge,
library FK indexes, `toggle_watched` refactor, README polish) were
completed and shipped as three jj commits on top of `main`.

Every item below has been verified as a credible finding — false
positives (Ash/Ecto confusion in release_tracking/settings, hallucinated
Rust frontend claim in ADR-028, wrong N+1 remediation for
library_browser) have been discarded.

Structure: each item has a severity, location, fix summary, and a rough
effort estimate. Pick any batch that fits the available time — nothing
here is blocking.

---

## Performance

### ~~P1. Handler render cost in caller's process~~ — resolved 2026-04-05

**False positive.** The audit estimated "~100µs per 500-byte SQL log."
Measured via `:timer.tc` on `Console.Handler.build_entry/3` across
50,000 iterations: a 500-byte SQL-shaped log actually takes **~8µs**,
off by ~12×. Size is essentially flat (7-8µs) across the 100B-1500B
range that Ecto actually produces.

During a real library page load (25 queries, 268B-1176B, mean 403B),
total handler time is **~227µs across all events** — **0.47% of the
48ms wall time**. The handler is not a bottleneck and the proposed
lazy-entry refactor is not justified.

**Known edge case (not worth preemptively fixing)**: `truncate/2` uses
`String.slice/3` which walks codepoints and costs **~72µs per call**
for messages >2000 bytes. Nothing in normal operations triggers this;
only giant inspect output, crash reports, or SQL with hundreds of
parameters would. Document the cliff if someone hits it.

---

### P7. Config lookups in dashboard
**Severity**: Minor — repeated reads of rarely-changing config
**File**: `lib/media_centaur_web/live/dashboard_live.ex`

`load_config/0` is called on every mount and handle_params and reads 4+
config keys via `MediaCentaur.Config.get/1`. Config values rarely change
once loaded into `:persistent_term`, so memoizing the whole config map
per request (or caching with a short TTL) would save a handful of
`persistent_term` lookups.

**Fix**: Read once in mount, store in socket assigns, skip re-read in
handle_params unless a `settings:updates` broadcast arrives.

**Effort**: Low. Small caching change.

---

### P8. Logger handler installation timing
**Severity**: Minor — theoretical race window
**File**: `lib/media_centaur/application.ex`

The `:logger` handler is added before the supervision tree starts. During
the window between handler install and `Console.Buffer` boot (~10-20ms),
log events hit the handler but `Process.whereis(Buffer)` returns nil, so
the entries are silently dropped. The handler has a safety guard so
nothing crashes, but startup logs in that window are lost.

**Fix options**:
1. Move handler installation to `handle_continue` after the supervision
   tree is fully started
2. Accept the behavior as-is and document it explicitly in
   `application.ex` + the troubleshoot skill
3. Add a tiny in-process queue that buffers log events until Buffer is up

Option 2 is probably right — it's a 10-20ms window, the missed logs are
boot-time noise, and adding complexity to fix it isn't worth it.

**Effort**: Low for documenting, medium for actually fixing.

---

### ~~P10. Verify library_browser N+1 claim~~ — resolved 2026-04-05

**False positive.** Measured against the dev library via Tidewave
(`:telemetry` on `[:media_centaur, :repo, :query]`): `fetch_all_typed_entries/0`
fires **29 queries** total, constant regardless of library size. This is
standard Ecto preload (one query per `(association, parent type)` pair via
`IN` clause), not N+1. The audit's suggested fix (`Repo.all(query, preload: [...])`)
was SQL-equivalent to the pipe form already in use.

Locked in as a regression guard — see the `query count (N+1 regression guard)`
describe block in `test/media_centaur/library_browser_test.exs`. The test
runs the fetcher against two differently-sized fixtures and asserts both
produce the same bounded query count.

---

## Documentation

### ~~D2. `PIPELINE.md` staleness verification~~ — resolved 2026-04-05

Read end-to-end and cross-referenced against `lib/media_centaur/pipeline/`
and `lib/media_centaur/image_pipeline*`. Eight stale/incorrect claims found
and fixed:

1. Supervision diagram said `ImagePipeline.Supervisor` held "Pipeline.Stats
   (shared)" — actually `ImagePipeline.Stats`, a separate module
2. `ImagePipeline.RetryScheduler` was missing from the supervision tree
3. Startup reconciliation (ADR-023) — the `:reconcile` rescan trigger in
   `Discovery.Producer.init/1` was entirely undocumented
4. `Payload.entry_point` field listed but does not exist in the struct
5. `Payload` fields `match_title` / `match_year` / `match_poster_path` /
   `candidates` / `ingest_status` were missing from the table
6. Import processing flow omitted the 100 MB disk space check between
   Parse and FetchMetadata
7. Image pipeline was missing its batcher config (size 20, 5s), the
   `handle_failed/2` permanent-vs-transient classification, the
   `library:updates` broadcast at batch end, and the retry scheduler hookup
8. Idempotency section referenced the pre-decomposition
   `entity_id`-keyed unique indexes for `seasons` and `images`. Updated
   to reflect the type-specific `library_images` unique indexes on
   `(tv_series_id, role)`, `(movie_series_id, role)`, `(video_object_id, role)`.

Side-finding retraction (was wrong, corrected 2026-04-05): an earlier
revision of this note claimed `library_images` was missing unique
indexes on `(movie_id, role)` and `(episode_id, role)`. That was a
false alarm caused by a grep for `unique_index.*library_images`, which
missed the two legacy indexes created on the old `:images` table
before it was renamed to `:library_images` in migration
`20260326074156_rename_tables_with_context_prefix.exs`. Indexes
survive table renames; names do not. All five unique indexes are live:
`images_unique_movie_role_index`, `images_unique_episode_role_index`,
and three `library_images_unique_*_role_index` entries. Verified
directly against `sqlite_master`. The legacy names are cosmetically
inconsistent but functionally equivalent — not worth a rename
migration.

---

## Priority clusters

If picking a batch, these cluster cleanly by effort/risk:

- **Bigger polish items (1 session each)**: D2 (PIPELINE.md staleness verification).

- **Defer**: P7 (config caching — no observable impact), P8 (handler install timing — theoretical only).

- **Verified as false positives on 2026-04-05**: P1 (handler render cost — ~0.5% of a library load), P10 (library_browser N+1 — regression test guards the constant-query invariant).

---

## How to use this document

1. Pick a cluster or individual items.
2. Start a new session with `/audit-all` available for re-verification if
   the code has drifted since 2026-04-05.
3. Execute per the existing patterns in this repo — the `superpowers:`
   skills cover the planning → implementation → verification flow.
4. Strike completed items from this file as they ship.

When this file is empty, either re-run `/audit-all` or move on to a
different initiative.
