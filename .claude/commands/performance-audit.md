---
description: Systematic performance analysis — DB queries, process architecture, LiveView efficiency, concurrency, and caching.
argument-hint: "[module-or-path (optional)]"
allowed-tools: Read, Glob, Grep, Bash(mix compile *), Bash(mix deps.tree *), mcp__tidewave__project_eval, mcp__tidewave__execute_sql_query, mcp__tidewave__get_source_location, mcp__tidewave__get_ecto_schemas, mcp__tidewave__get_ash_resources, mcp__tidewave__get_docs
---

# Performance Audit

You are performing a systematic performance analysis of an Elixir/Phoenix codebase.
Your goal is to find **concrete, evidence-based** performance issues — not speculative
optimizations. Every finding must cite the exact file and line number, explain the
mechanism of waste, and propose a specific fix.

**Scope:** If `$ARGUMENTS` is provided, focus the analysis on that module or path only.
Otherwise, analyze the full application.

---

## Phase 1 — Orientation

Understand the project shape before diving into analysis.

1. Read `mix.exs` to identify dependencies and the tech stack (Phoenix, Ecto, Ash,
   Broadway, Oban, etc.).
2. Read `CLAUDE.md` if it exists — it describes architecture, hot paths, and design
   principles.
3. Identify the hot paths: web endpoints/channels, background pipelines, GenServers
   that handle frequent messages, LiveViews with real-time updates.
4. Use `mcp__tidewave__get_ecto_schemas` or `mcp__tidewave__get_ash_resources` to
   map out the data model.
5. Count approximate module count and identify the largest/most complex modules.

---

## Phase 2 — Targeted Analysis

For each category below, scan the relevant code and flag concrete issues. Always cite
`file_path:line_number` for every finding.

### 2.1 — DB / Query Efficiency

Look for:
- **N+1 queries**: Loops that issue a query per iteration instead of preloading or
  batch-loading. In Ash, look for `Ash.read!` or `Ash.get!` inside `Enum.map` or
  comprehensions.
- **Missing preloads**: Relationship access that triggers lazy-loading (or errors in
  Ash's case, since Ash doesn't lazy-load — meaning the data is fetched separately
  when it could be loaded together).
- **Unbounded queries**: `Ash.read!` or `Repo.all` without a limit, on tables that
  grow with usage.
- **Read-all-then-filter**: Loading full tables into memory and filtering with `Enum`
  instead of pushing predicates to the database.
- **Missing indexes**: Use `mcp__tidewave__execute_sql_query` to check for indexes on
  columns used in frequent lookups, filters, and unique constraints.
- **Full-table scans on hot paths**: Queries in request/channel handlers that scan
  entire tables.

### 2.2 — Process Architecture

Look for:
- **GenServer bottlenecks**: A single GenServer serializing work that could be
  parallelized or handled without a process. Remember: a GenServer processes one
  message at a time — if work is CPU-bound or IO-bound, it serializes everything.
- **Large state in GenServer**: GenServer state that holds large data structures
  (full entity lists, file contents) that get copied on every `handle_call` reply.
- **Synchronous calls where casts suffice**: `GenServer.call` blocking the caller
  when the caller doesn't need the result.
- **Missing Task.Supervisor**: `Task.async` without a supervisor in production code
  (unsupervised tasks crash silently or take down the caller).
- **Unnecessary processes**: GenServers used for code organization rather than
  runtime state management — a plain module with functions would be simpler and
  avoid process overhead.

### 2.3 — Message Passing & Channel Efficiency

Look for:
- **Large data in messages**: PubSub broadcasts, GenServer calls/casts, or channel
  pushes that send large data structures (data is copied between process heaps).
- **Unbounded list pushes**: Pushing entire entity lists over channels without
  batching/chunking.
- **Redundant broadcasts**: Multiple broadcasts for what could be a single batched
  notification.
- **Serialization in hot paths**: JSON encoding happening inside GenServer callbacks
  or other serialization points that block message processing.

### 2.4 — LiveView Efficiency

Look for:
- **Queries in connected mount**: Database queries in the connected `mount/3` callback
  that could be deferred to `handle_params` or loaded asynchronously with
  `assign_async`.
- **Full-collection reassigns**: Reassigning entire lists to socket assigns when only
  one item changed — use streams for large collections.
- **Over-assigned data**: Assigns that hold more data than the template actually uses
  (all assigns are diffed on every render).
- **Missing pagination/streaming**: Rendering unbounded lists without pagination or
  LiveView streams.
- **Expensive computations in render**: Function calls in HEEx templates that perform
  non-trivial work on every render.

### 2.5 — Enumeration Efficiency

Look for:
- **Multi-pass chains**: `Enum.map |> Enum.filter |> Enum.map` chains that traverse
  lists multiple times when a single `Enum.flat_map`, `for` comprehension, or
  `Enum.reduce` would do.
- **Intermediate list construction**: Building lists that are immediately discarded
  (e.g., `Enum.map` only to pass to `Enum.join`).
- **Eager evaluation of large datasets**: Using `Enum` where `Stream` would avoid
  materializing large intermediate collections.
- **Repeated traversals**: Calling `Enum.count`, `Enum.find`, `length()` on the same
  list multiple times.

### 2.6 — Caching Opportunities

Look for:
- **Repeated identical reads**: The same database query or API call executed multiple
  times in the same request/pipeline with no caching.
- **Config lookups in hot paths**: `Application.get_env` or config GenServer calls
  inside loops or frequently-called functions where the value rarely changes —
  candidates for `:persistent_term` or ETS.
- **Recomputed derived data**: Values derived from stable inputs that are recomputed
  instead of cached.

### 2.7 — Startup & Supervision

Look for:
- **Blocking init**: `GenServer.init/1` callbacks that perform I/O (DB queries, HTTP
  calls, file reads) synchronously, delaying application startup. Should use
  `handle_continue` or send self a message.
- **Race conditions**: Processes that depend on other processes being started (e.g.,
  querying the DB before Repo is up, or using a GenServer before its init completes).
- **Heavyweight supervision**: Too many children started eagerly when some could be
  started lazily or on demand.

### 2.8 — Concurrency Utilization

Look for:
- **Sequential work that could parallelize**: Independent I/O operations (API calls,
  file reads, DB queries) done sequentially when `Task.async_stream` or similar
  concurrency would help.
- **Under-utilized concurrency**: Broadway/Oban configurations with low concurrency
  limits when the work is I/O-bound.
- **Over-utilized concurrency**: Too many concurrent processes for CPU-bound work,
  causing contention.

---

## Phase 3 — Runtime Introspection (when applicable)

If the application is running and MCP tools are available:

- Use `mcp__tidewave__project_eval` to check:
  - Process message queue lengths: `:erlang.process_info(pid, :message_queue_len)`
  - ETS table sizes: `:ets.info(table, :size)`
  - Process counts: `length(Process.list())`
  - Memory usage: `:erlang.memory()`
- Use `mcp__tidewave__execute_sql_query` to:
  - Check for missing indexes on frequently-queried columns
  - Inspect query plans with `EXPLAIN QUERY PLAN` (SQLite) or `EXPLAIN ANALYZE` (Postgres)
  - Check table sizes and row counts

---

## Phase 4 — Severity Classification

Rate each finding:

| Severity | Criteria |
|----------|----------|
| **Critical** | Causes observable latency or resource exhaustion under normal load |
| **Moderate** | Wastes resources but doesn't cause user-visible issues yet; will degrade as data grows |
| **Minor** | Suboptimal but negligible real-world impact at any realistic scale |

---

## Phase 5 — Remediation Plan

For each finding, provide:

1. **Location** — exact `file_path:line_number`
2. **Issue** — one-sentence description of the performance problem
3. **Mechanism** — brief explanation of *why* this is slow (what work is wasted, what
   resource is contended, what scales poorly)
4. **Severity** — Critical / Moderate / Minor
5. **Fix** — concrete, specific change to make (not vague advice like "consider caching")

Group findings by severity (Critical first). Within each severity group, order by
impact/effort ratio — highest-impact, lowest-effort fixes first.

---

## Rules

- **Evidence, not speculation.** Only flag patterns with concrete evidence of waste.
  "This *could* be slow if..." is not a finding. "This queries the DB inside a loop
  that runs once per entity" is.
- **Cite every finding.** Every issue must include the exact file path and line number.
  No exceptions.
- **Skip what's fine.** If a category has no issues, say "No issues found" and move on.
  Do not pad the report.
- **No unearned praise.** If an area is clean, one sentence suffices. Spend your
  words on problems, not compliments. A clean report is a valid outcome — but only
  if you genuinely found nothing.
- **No implementation changes.** This command produces analysis only. Do not modify
  any files.
- **Scope to arguments.** If `$ARGUMENTS` names a specific module or path, analyze
  only that area. Do not expand scope unless explicitly asked.
