---
description: Evidence-based performance analysis — SQLite query and transaction behaviour, process architecture, PubSub payloads, LiveView efficiency, pipeline/job concurrency, and the profiling suite.
argument-hint: "[module-or-path (optional)]"
allowed-tools: Read, Glob, Grep, Bash(mix compile *), Bash(mix deps.tree *), Bash(scripts/profile *), Bash(ls *), mcp__tidewave__project_eval, mcp__tidewave__execute_sql_query, mcp__tidewave__get_source_location, mcp__tidewave__get_ecto_schemas, mcp__tidewave__get_docs, mcp__tidewave__get_logs, mcp__tidewave__search_package_docs
---

# Performance Audit

You are performing a systematic performance analysis of the Media Centaur backend:
Phoenix LiveView on Bandit, Ecto on **SQLite** (`ecto_sqlite3`/`exqlite`), Broadway
for the import pipeline, Oban (Lite engine) for jobs, `image`/`vix` for artwork, and
a single BEAM node that is also the user's desktop media center. Findings must be
**concrete and evidence-based** — a mechanism of waste with `file_path:line`, not a
speculative optimisation.

**Scope:** If `$ARGUMENTS` is provided, analyse that module or path only. Otherwise
the full application.

---

## Phase 1 — Orientation

1. Read `CLAUDE.md`, `docs/architecture.md` (bounded contexts, PubSub topics,
   supervision tree, key principles) and `docs/pipeline.md`.
2. Read `mix.exs` for the dependency set and `config/config.exs` for Oban queues,
   Broadway stages, and Repo settings (`busy_timeout`, transaction mode).
3. Map the data model with `mcp__tidewave__get_ecto_schemas`.
4. Identify hot paths: LiveView mounts and `handle_params` for every route in
   `lib/media_centaur_web/router.ex`, PubSub fan-out (`MediaCentaur.Topics`, the
   `BroadcastCoalescer`), the projection caches (ETS, `refresh_cache`), the Broadway
   pipeline stages, Oban workers, the queue monitor and watcher polling loops, and
   image serving (`MediaCentaurWeb.Plugs.ImageServer`).
5. Check whether a profiling baseline exists under `priv/profiling/` — `mix profile`
   ([ADR-041]) seeds representative data, runs every `MediaCentaur.Profile.Suite`
   through Benchee, times every top-level LiveView mount, and diffs against the
   baseline. `scripts/profile` is the one-button entry point (it sets the config
   override so it can never touch the real DB).

---

## Phase 2 — Targeted Analysis

Cite `file_path:line` for every finding.

### 2.1 — SQLite query and transaction behaviour

- **N+1 queries:** `Repo.get`/`get_by`/`one` inside `Enum.map`, comprehensions, or
  per-row callbacks; `Repo.preload` per entity instead of on the collection.
- **Unbounded reads:** `Repo.all` without `limit`/`where` on tables that grow with
  the library, watch history, console entries, diagnostic events, or pursuits;
  read-all-then-`Enum.filter` where the predicate belongs in the query.
- **Single-writer discipline:** SQLite serialises writers. Flag long-running
  transactions that hold the write lock while doing I/O or computation, write bursts
  that could be one `insert_all`/`update_all`, and code that opens a deferred
  transaction and upgrades to a write (the lock-upgrade returns `SQLITE_BUSY`
  immediately, ignoring `busy_timeout`; the Repo runs `:immediate` transactions for
  this reason — anything bypassing that is a finding).
- **Indexes:** with `mcp__tidewave__execute_sql_query`, check `EXPLAIN QUERY PLAN`
  for the hot queries and look for `SCAN` on large tables; confirm indexes back the
  columns used by lookups, filters, and unique constraints.
- **Retention:** tables with unbounded growth that no `Retention` sweep policy
  covers.

### 2.2 — Process architecture

- A single GenServer serialising CPU- or I/O-bound work that could be parallel or
  needs no process at all (plain functions).
- Large state copied on every reply; `GenServer.call` where the caller does not need
  a result; unsupervised `Task.async` in production paths (web code uses owned
  async — MC0019 — but library code is unchecked).
- `init/1` doing DB or filesystem I/O instead of `handle_continue`; startup races
  between processes (the pipeline reconcile-on-boot race was a real one).

### 2.3 — PubSub and message payloads

- Broadcasts carrying whole entity lists or projections instead of ids/deltas
  (data is copied into every subscriber's heap; every LiveView is a subscriber).
- Redundant broadcasts where the coalescer should batch; JSON encoding or heavy
  computation inside GenServer callbacks.
- Detail/modal live updates that re-read a cached projection before it was
  refreshed (react to `{:library_view_updated, :detail, _}`-style events, not to the
  raw mutation).

### 2.4 — LiveView efficiency

- Queries in `mount/3` that belong in `handle_params` or `assign_async`; work done
  on the static render that is thrown away on the connected mount.
- Full-collection reassigns where streams fit; assigns holding more than the
  template uses (every assign is diffed); helper calls in HEEx that do non-trivial
  work per render.
- Desktop rendering defaults ([UIDR-012]): images must be eager and sync-decoded
  with stable ids and no entrance animations — lazy loading or keyframe-per-row
  patterns are perf regressions here, not polish.
- `phx-update`/stream resets that redraw whole lists on single-item changes.

### 2.5 — Enumeration and data shaping

- Multi-pass `Enum` chains over the same list, intermediate lists that are
  immediately consumed, repeated `length/1` or `Enum.find` on the same collection,
  `Enum` where `Stream` avoids materialising a large intermediate (file walks,
  console ring buffer scans).

### 2.6 — Caching

- Identical reads repeated within one request or pipeline run; `Application.get_env`
  or Settings lookups inside loops; derived data recomputed from stable inputs.
- Existing caches (projection ETS tables, `:persistent_term` for the update check)
  with unclear invalidation — a stale cache is a correctness bug reported here only
  when it also causes redundant work.

### 2.7 — Pipeline, jobs, and external I/O

- Broadway stage concurrency and batch sizes versus the actual work (I/O-bound
  TMDB/image fetches versus CPU-bound hashing or vix transforms).
- Oban queue limits (`acquisition`, `self_update`, `images`, `maintenance`) versus
  outbound rate limits (Prowlarr fans out per indexer; TMDB has its own limiter).
- Sequential HTTP calls that are independent (`Task.async_stream` candidates) and
  the reverse: unbounded fan-out against a VPN-tunnelled service.
- Watcher and queue-monitor poll intervals that wake the system when idle.

---

## Phase 3 — Runtime evidence (when the dev server is up)

The dev service on `127.0.0.1:2160` is the daily driver against the real database.
Use it read-only:

- `mcp__tidewave__project_eval` for message-queue lengths of the named processes,
  ETS table sizes, `:erlang.memory()`, and `Process.list()` counts.
- `mcp__tidewave__execute_sql_query` for `EXPLAIN QUERY PLAN`, table row counts, and
  index lists (`PRAGMA index_list`).
- `mcp__tidewave__get_logs` for slow-query or timeout noise.
- `scripts/profile --scale=small` when a claim needs numbers. Read the median, not
  the p99: microsecond-scale p99 variance is noise on this machine, and a regression
  is only real when it reproduces across two runs.

Never mutate data through Tidewave; never point a mix task at the real DB.

---

## Phase 4 — Severity

| Severity | Criteria |
|----------|----------|
| **Critical** | Observable latency, UI jank, or resource exhaustion under normal library sizes |
| **Moderate** | Wastes resources without visible impact yet; degrades as the library, history, or logs grow |
| **Minor** | Suboptimal but negligible at any realistic scale |

---

## Phase 5 — Output

Number findings **P1, P2, …**, grouped by severity (Critical first), ordered within a
group by impact-to-effort. For each: **Location**, **Issue** (one sentence),
**Mechanism** (what work is wasted or what resource is contended), **Severity**,
**Fix** (specific change, not "consider caching").

---

## Rules

- **Evidence, not speculation.** "This could be slow if…" is not a finding. A query
  inside a per-entity loop is.
- **Cite every finding** with `file_path:line`.
- **Skip what's fine.** "No issues found" is a valid section result; do not pad.
- **No unearned praise.**
- **Analysis only.** Do not modify files. Output goes to the chat.
- **Scope to arguments.** Do not expand scope unless asked.
