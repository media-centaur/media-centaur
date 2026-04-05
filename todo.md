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

## Engineering

### E1. Console LiveView duplication
**Severity**: Medium — cosmetic, deferred intentionally
**Files**:
- `lib/media_centaur_web/live/console_live.ex`
- `lib/media_centaur_web/live/console_page_live.ex`

`ConsoleLive` (sticky drawer) and `ConsolePageLive` (full-page `/console`
route) share ~100 lines of near-identical code: `safe_to_existing_atom/1`,
`entry_dom_id/1`, all four `handle_info` clauses, and most of the eleven
`handle_event` clauses. The original plan deferred extraction because the
two modules could diverge over time — but they haven't, and a shared
helper would prevent drift.

**Fix options**:
1. Extract a `MediaCentaurWeb.ConsoleLiveCommon` module with the shared
   helpers and a macro that injects the `handle_info`/`handle_event`
   clauses into both LVs
2. Move the shared bodies into pure functions that both LVs call from
   their own thin callback stubs
3. Use Phoenix LiveView's `on_mount` + `attach_hook` to share event
   handling — more invasive, probably overkill here

Option 2 is cleanest. Each LV keeps its own `handle_info/handle_event`
clauses but delegates to `ConsoleLiveCommon.handle_log_entry(socket, entry)`
etc. Tests stay where they are; the shared module gets its own unit tests
for the pure helpers.

**Effort**: Medium. ~200 lines touched, clean refactor, no new tests
required beyond verifying existing LV tests still pass.

---

### E2. `View.only_search_changed?` naming
**Severity**: Minor — readability
**File**: `lib/media_centaur/console/view.ex`

Function name is slightly ambiguous. It means "the ONLY difference
between these two filters is the search field" — used to skip server-side
re-streaming when text search changes. Consider renaming to
`only_search_query_differs?` or adding a clearer `@doc` explaining the
intent.

**Effort**: Low. One-line rename + docstring + callsite updates (there's
one caller in `ConsoleLive.handle_info({:filter_changed, _})`).

---

### E3. Settings coupling documentation
**Severity**: Minor — architectural documentation gap
**Files**:
- `lib/media_centaur/console/buffer.ex`
- `CLAUDE.md` (Bounded Contexts section)

The Console context persists its filter and buffer cap to `Settings.Entry`
rather than owning its own settings table. ADR-029 says bounded contexts
should own their data, so this technically crosses boundaries. In practice
`Settings` is shared infrastructure (not a true bounded context), so the
coupling is fine — but it's not documented.

**Fix**: Add a one-line note in `CLAUDE.md` under the Bounded Contexts
table, or in the Console moduledoc, explaining that Console uses
`Settings.Entry` for persistence because (a) no per-console table is
justified and (b) `Settings` is shared infrastructure treated as an
extension of any context that needs key/value persistence.

**Effort**: Low. Pure documentation.

---

## Performance

### P1. Handler render cost in caller's process
**Severity**: Moderate — only observable at high log volume
**File**: `lib/media_centaur/console/handler.ex`

`log/2` runs `build_entry` synchronously in the caller's process on every
log event. `build_entry` calls `render_message` which does `strip_ansi`
(regex) and `truncate` (`String.slice`) on the rendered binary. For a
500-byte SQL query log, this is ~100µs per call. At 100+ logs/sec during
heavy Ecto activity, this adds up to measurable latency in the calling
process.

**Fix**: Defer rendering to the Buffer GenServer. Store the raw `msg`
tuple + metadata in a "lazy entry" struct, and render on demand at view
time (console UI rendering, clipboard copy, download, `Diagnostics.log_recent`).
The hot path in the caller becomes: minimal Entry struct + `Buffer.append/1`
cast + return.

**Tradeoffs**:
- Adds complexity to the Buffer snapshot path (needs to know how to
  render lazily)
- The search filter in the console UI currently operates on the rendered
  `message` string — would need to either render-then-match (no savings) or
  rework to match against the raw structure
- Worth doing only if profiling shows the handler is a bottleneck

**Effort**: Medium-high. Architectural change. Recommend measuring first
(via Tidewave under load) before committing.

---

### P2. Redundant `String.downcase` in Filter search path
**Severity**: Minor — sub-microsecond per call
**File**: `lib/media_centaur/console/filter.ex:201-204`

`Filter.search_passes?/2` calls `String.downcase(search)` on every match
check, even though `search` doesn't change between calls. The optimization
is to cache the downcased version in the Filter struct:

```elixir
defstruct level: :info, components: %{}, default_component: :show,
          search: "", search_lower: ""

def new(opts \\ []) do
  filter = struct(__MODULE__, opts)
  %{filter | search_lower: String.downcase(filter.search)}
end
```

And update `search_passes?/2` to use `filter.search_lower` instead.

**Effort**: Low. Single-file change + update to `from_persistable/1` so
the round-trip populates `search_lower`.

---

### P3. Multi-pass Enum chain in library_live reload
**Severity**: Minor — cosmetic
**File**: `lib/media_centaur_web/live/library_live.ex:539-540`

```elixir
entries
|> Enum.reject(fn entry -> MapSet.member?(gone_ids, entry.entity.id) end)
|> Enum.map(fn entry -> Map.get(updated_map, entry.entity.id, entry) end)
```

Two traversals of the entries list. Typical list size is <1000 items so
the perf impact is negligible, but a single comprehension is cleaner:

```elixir
for entry <- entries,
    not MapSet.member?(gone_ids, entry.entity.id),
    do: Map.get(updated_map, entry.entity.id, entry)
```

**Effort**: Low. One-line replacement.

---

### P4. Unbounded `Library.list_images/0`
**Severity**: Minor — footgun for future refactors
**File**: `lib/media_centaur/library.ex:252-253`

`list_images/0` calls `Repo.all(Image)` with no limit. The function name
suggests it's safe to call, but a large library could load thousands of
images into memory in one query. Currently used only in a batch-filtered
path, so it's not a hot issue — but the API shape invites misuse.

**Fix**: Either
1. Rename to `list_all_images/0` to signal unbounded scope
2. Add a default limit parameter: `list_images(limit \\ 5_000)`
3. Document the memory cost in the moduledoc

Option 1 is lowest risk.

**Effort**: Low. Rename + callsite update.

---

### P5. Full stream reset in library_live reload
**Severity**: Minor — causes DOM teardown of all grid items
**File**: `lib/media_centaur_web/live/library_live.ex`

`reload_entities` handler resets the stream with `reset: true` whenever
the gone-ids set is non-empty OR new entries are added. This tears down
the entire grid's DOM instead of surgically updating only changed items.
The `touch_stream_entries/1` helper exists for selective updates but isn't
used aggressively enough.

**Fix**: Narrow the reset condition. Only reset when the sort order or
type filter changed. For typical progress updates (watch status toggle),
use `touch_stream_entries` to update only the affected entry.

**Effort**: Medium. Requires understanding the reload paths and which
state changes warrant a full reset vs a partial update.

---

### P6. Over-fetched `tracking_status` on non-selection navigation
**Severity**: Minor — duplicate DB queries
**File**: `lib/media_centaur_web/live/library_live.ex:884-908`

`load_tracking_status/1` is called on every `handle_params`, including
when the user is just toggling a filter chip or sorting the grid (i.e.,
when `selected_entity_id` didn't change). The query is fast but wasteful.

**Fix**: Track `previous_selected_entity_id` in socket assigns. Only call
`load_tracking_status/1` when the selected entity changes. Skip otherwise.

**Effort**: Low. 10-15 line change in the handle_params flow.

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

### P9. Rescan task deduplication
**Severity**: Minor — idempotent but wasteful
**File**: `lib/media_centaur/console.ex`

`Console.rescan_library/0` spawns a new `Task.Supervisor.start_child` on
every call, so rapid clicks spawn parallel scans. Scans are idempotent, so
there's no data corruption, but it's wasted CPU and confusing console
noise.

**Fix**: Add a `scanning?` flag to the Console context (via a tiny
GenServer or `:persistent_term` + compare-and-set). If a scan is already
running, reject the second request with a `{:error, :already_scanning}`
and log a `[library]` entry explaining. Alternatively, client-side debounce
the button.

**Effort**: Low for client-side debounce, medium for server-side flag.

---

### P10. Verify library_browser N+1 claim
**Severity**: Unknown — audit's remediation was wrong, underlying claim may or may not be real
**File**: `lib/media_centaur/library_browser.ex`

The audit flagged `Repo.all(query) |> Repo.preload([...])` as N+1 and
suggested replacing with `Repo.all(query, preload: [...])`. Those are
equivalent at the SQL level, so the fix is wrong. But the underlying claim
— that library page loads issue too many preload queries — might still be
real.

**Fix**: Verify with Tidewave + EXPLAIN whether there's an actual N+1.
Count the queries fired during a library page mount with 50 TV series.
If it's 1 query per association level (expected), no action. If it's 1
query per entity per association (actual N+1), consider using SQL joins
via `from t in TVSeries, join: s in assoc(t, :seasons), preload: [seasons: s]`.

**Effort**: Low for verification (just EXPLAIN), medium for any actual
fix.

---

## Documentation

### D1. `mix seed.review` clarity
**Severity**: Minor — undocumented build command
**File**: `CLAUDE.md` (Build & Run section)

`mix seed.review` is listed alongside `mix setup` / `mix phx.server` /
`mix test` / `mix precommit` as if it's a standard task. In reality it's
a one-shot seeding utility for the review UI's visual test cases.

**Fix**: Move it to a separate "Seeding" subsection with a one-line
explanation: "Populate the review UI with visual test cases. Run once
after initial setup. Idempotent, safe to re-run."

**Effort**: Trivial. 2-3 line edit in CLAUDE.md.

---

### D2. `PIPELINE.md` staleness verification
**Severity**: Unknown — may or may not be stale
**File**: `PIPELINE.md` (dated 2026-03-26)

Predates the console feature shipped 2026-04-05. May not reflect how logs
flow through `MediaCentaur.Console` now, or how rescan dispatch works
post-refactor. Content may also be accurate — unknown without reading it
end-to-end against current code.

**Fix**: Read PIPELINE.md in full, cross-reference against
`lib/media_centaur/pipeline/` and `lib/media_centaur/broadway/`, and
update any stale claims.

**Effort**: Medium. The document is long.

---

### D3. CLAUDE.md architecture principles expansion
**Severity**: Minor — dense for new contributors
**File**: `CLAUDE.md` (Architecture Principles section, ~lines 95-102)

Current principles are terse one-liners that assume deep familiarity:
- "This app owns all writes"
- "Schema.org is the data model"
- "UUIDs are stable forever"
- "Images: one copy per role"
- "All mutations broadcast to PubSub"
- "The pipeline is a mediator, not a side effect"

Each would benefit from a 1-2 sentence explanation of the WHY — the
constraint or past incident that made it a principle.

**Fix**: Expand each bullet with a short reason. Example: "UUIDs are
stable forever — once assigned, a UUID never changes. This ensures image
directories (`data/images/{uuid}/`) and external references remain valid
across entity updates."

**Effort**: Low-medium. Requires knowing the history behind each
principle.

---

### D4. Variable naming examples in CLAUDE.md
**Severity**: Minor — rule without clear examples
**File**: `CLAUDE.md` (Variable Naming section)

The "Never abbreviate" rule doesn't distinguish between domain
abbreviations (bad: `wf`, `e`, `res`) and established short names (fine:
`id`, `ok`, `msg`, `pid`). New contributors can't tell which side of the
line `idx`, `acc`, `ctx` fall on.

**Fix**: Add a clarifying table or bullet list:
- **Acceptable**: `id`, `ok`, `msg`, `pid`, `ref`, `fn` (established
  conventions)
- **Unacceptable**: `wf` (watched_file), `e` (entity), `res` (result),
  `s` (season), `ep` (episode)
- Rule of thumb: if you can't say the name aloud and have it be clear,
  it's too short.

**Effort**: Trivial. Small addition to the existing section.

---

## Priority clusters

If picking a batch, these cluster cleanly by effort/risk:

- **Quick wins (1 session, all low-effort)**: E2, P2, P3, P4, P6, P9, D1, D4 — each is <30 minutes, all low-risk, can be bundled into a single "chore: minor perf + docs polish" commit.

- **One focused refactor (1 session, medium effort)**: E1 — console LiveView extraction. Clean scope, clear payoff, no cross-cutting concerns.

- **Verification-first items (low effort but need measurement)**: P1, P10 — need Tidewave profiling before committing to a fix. Useful to scope before implementing.

- **Bigger polish items (1 session each)**: P5 (stream reset), E3 + D3 (docs depth), D2 (PIPELINE.md staleness verification).

- **Defer**: P7 (config caching — no observable impact), P8 (handler install timing — theoretical only).

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
