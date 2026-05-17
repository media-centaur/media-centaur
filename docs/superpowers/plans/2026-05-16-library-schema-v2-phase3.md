# Library Schema v2 — Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to execute task-by-task. Steps use checkbox (`- [ ]`). Invoke `automated-testing`, `otp-thinking`, `phoenix-thinking`, and `coding-guidelines` BEFORE touching code.

**Goal:** Push the remaining Library read paths into Pillar 2 (in-memory projections via the established Cache.Worker pattern from [ADR-041](../../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md)). After Phase 3, no LiveView mount/render path hits `MediaCentarr.Repo` directly for Library data — they read from `Library.Views.*` ETS tables. Watch progress moves to a Pillar-2 GenServer with debounced persistence.

**Architecture premise:** This is a local desktop app — statefulness is an asset. The four ADR-041 projections already live; Phase 3 fans the same pattern across the remaining read paths. Reads are microseconds (`:ets.tab2list/1` / `:ets.lookup/2`), not milliseconds. Writes go through Pillar-1 unchanged; projections rebuild on PubSub events.

**Campaign reference:** [`campaigns/done/library-schema-v2.md`](../../../campaigns/done/library-schema-v2.md). Phase 1 + Phase 2 shipped to main. This plan executes Phase 3.

**Tech stack:** Phoenix 1.7+, Ecto 3.12+, SQLite via ecto_sqlite3, ETS, `MediaCentarr.Cache` behaviour (ADR-041).

---

## Test-design principles (load-bearing — read before any task)

The user is explicit: **automated testing rigor is the bar for Phase 3.** Apply these rules to every task in this plan.

1. **Test through the public API only ([ADR-026]).** Never call `GenServer.call/cast` on a `Cache.Worker` from a test. Never use `:sys.get_state`. Never `:ets.lookup` from a test. The public seam is the projection's read API (`Library.Views.browse/1`, etc.). If a behaviour can't be exercised through that API, the API is wrong — fix the API, not the test.

2. **Test refresh-trigger correctness via PubSub, not state introspection.** The contract under test is "when X happens upstream, the next read reflects X." Implementation:
   ```elixir
   # ✗ WRONG — tests internals
   assert :ets.lookup(@table, :foo) == [...]

   # ✓ RIGHT — tests the contract
   broadcast_relevant_event()
   :ok = wait_for_view_updated_event()  # subscribe to the derived topic
   assert Library.Views.browse(filter: :movies) == [...]
   ```

3. **Use `async: false` for projection tests.** ETS tables are named/shared (per ADR-041). Concurrent tests touching the same table interfere. Per-test cleanup via `setup` re-initializing the table is the established pattern (see `continue_watching_test.exs`).

4. **Subscribe to the derived `*_view_updated` topic to deterministically synchronise.** Don't sleep/poll for the projection to refresh. Subscribe to `library:views` (or the appropriate `*_views` topic), trigger the upstream event, `receive` the `view_updated` message, then read. This is the only flake-free pattern.

5. **Test from cold start AND from incremental update.** Cold-start tests: the projection populates correctly on boot (`refresh_cache/0` called once). Incremental tests: upstream event → projection updates → read reflects the change. Both paths matter; mocking either is a smell.

6. **Page smoke tests update for every LiveView touched.** `test/media_centarr_web/page_smoke_test.exs` must keep covering every route/zone with a representative fixture. If Phase 3 changes how a LiveView reads its data, the smoke fixture still has to seed enough data to exercise the new read path.

7. **Extract LiveView logic into pure functions ([ADR-030]).** Phase 3 may introduce new view-model helpers. They live in pure modules and get unit-tested with `build_*` factory helpers (no DB), `async: true`. Never test rendered HTML.

8. **Test-first applies to bug fixes encountered along the way.** If a projection refresh causes a stale-read regression, the test reproducing it is written FIRST against the unmodified code — confirmed red — then the fix lands.

9. **`bun test` for any JS touched.** If a Phase 3 task adds JS (unlikely — projections are server-side), the JS tests live in `assets/js/.../__tests__/`.

10. **Pre-existing flakes are NOT new ones.** Track the known set: `AcquisitionLivePursuitModalTest`, `PageSmokeTest /history`, `ErrorReports.BucketsTest`, `Watcher.FilePresence`, `ConsoleLiveTest`. If they fire, re-run; if a NEW flake appears, **stop and diagnose** — never accept a flaky new test.

11. **`mix precommit` is the gate, not a guideline.** Every commit boundary in Phase 3 must produce a green precommit. Zero warnings (Credo strict, format, boundaries, deps.audit, sobelow, full suite, JS bun tests).

---

## Pre-flight

- [ ] Read `lib/media_centarr/cache.ex` end-to-end — the `MediaCentarr.Cache` behaviour is the contract every projection implements.
- [ ] Read `lib/media_centarr/library/views/continue_watching.ex` and its test as the canonical example.
- [ ] Read `lib/media_centarr/topics.ex` — the PubSub topic registry. Phase 3 adds derived topics; the pattern is `library:views` for derived events, `library:updates` for source events.
- [ ] Confirm `mix precommit` is green on `main` before starting (it shipped clean after Phase 2 — should be a no-op).
- [ ] `jj new` off main for the Phase 3 branch.

## Sub-task graph

```
A (Library.Views.Browse — list/filter projection)            ─┐
B (Library.Views.Detail — per-PlayableItem read projection)  ─┼─ each independent of the others
C (Library.Views.Search — in-memory entity index)            ─┘
D (Library.Progress — Pillar-2 GenServer + debounced flush)  — independent
E (Audit + retire DB-on-render reads)                        — depends on A, B, C, D
```

**Execution order:** A → B → C → D → E. Each subagent dispatch lands one task with test-first discipline.

---

## File Structure

| Task | Creates | Modifies |
|------|---------|----------|
| A | `lib/media_centarr/library/views/browse.ex`, `lib/media_centarr/library/views/browse_item.ex`, `test/media_centarr/library/views/browse_test.exs` | `lib/media_centarr/library.ex` (add `Views.browse/1` reader), `lib/media_centarr/topics.ex` if new topic atom needed, `lib/media_centarr/application.ex` (start the Cache.Worker for this projection), `lib/media_centarr_web/live/library_live.ex` (read from projection on mount) |
| B | `lib/media_centarr/library/views/detail.ex`, `lib/media_centarr/library/views/detail_item.ex`, `test/media_centarr/library/views/detail_test.exs` | `Library` context, application supervision, `DetailLive` / `EntityModal` consumers |
| C | `lib/media_centarr/library/views/search.ex`, `lib/media_centarr/library/views/search_item.ex`, `test/media_centarr/library/views/search_test.exs` | `Library` context, application supervision, search consumers |
| D | `lib/media_centarr/library/progress.ex`, `lib/media_centarr/library/progress/cache.ex` (or wherever fits the Cache.Worker shape), `test/media_centarr/library/progress_test.exs`, possibly `test/media_centarr/library/progress/debounced_flush_test.exs` | `Library.WatchProgress` writer paths (Playback session writes via Library.Progress now), `MpvSession`, application supervision |
| E | — | Every LiveView mount/handle_info that still hits `Repo` for Library data; `test/media_centarr_web/page_smoke_test.exs` to verify zero DB queries in render paths |

---

## Task A — `Library.Views.Browse`

**Goal:** ETS projection of the library browse grid. Replaces the per-render `Library.Browser.list/2` query. Filterable view-side (by media type, watched-state, etc.).

**Public read API:**
```elixir
@spec Library.Views.browse(filter :: keyword()) :: [BrowseItem.t()]
def browse(filter \\ [])
```

`BrowseItem` is a typed struct (`%BrowseItem{id, kind, name, year, poster_url, ...}`) — same shape as today's `Library.Browser` output, but pre-shaped.

**Cache.Worker shape:** Named ETS table `:library_view_browse`, `:ordered_set`, `:public`, `:read_concurrency, true`. Keyed by display order. Reads bypass the GenServer.

**Refresh triggers:**
- `library:updates` (entity create/edit/delete — already coalesced)
- `library:availability` (file presence changes — affect "owned" filters)

**Derived topic broadcast:** `{:library_view_updated, :browse}` on `library:views`.

### Test plan (write FIRST — this is the spec)

The test file follows the existing `continue_watching_test.exs` pattern:

```elixir
defmodule MediaCentarr.Library.Views.BrowseTest do
  use MediaCentarr.DataCase, async: false
  import MediaCentarr.TestFactory
  alias MediaCentarr.Library.Views
  alias MediaCentarr.Library.Views.{Browse, BrowseItem}
  alias MediaCentarr.Topics

  setup do
    # Re-init the cache so each test starts cold
    Browse.refresh_cache()
    :ok
  end

  describe "cold start" do
    test "returns empty when library is empty"
    test "returns all standalone movies sorted by name"
    test "returns TV series, movie series, video objects alongside movies"
    test "respects :kind filter (movies only)"
    test "respects :present-only filter (excludes entities with no present WatchedFile)"
  end

  describe "refresh on library:updates" do
    test "newly created Movie appears in next read after :entities_changed broadcast"
    test "deleted entity disappears in next read"
    test "renamed entity's BrowseItem.name reflects the update"

    # The non-flaky synchronisation pattern:
    test "broadcasts :browse on library:views after refresh" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())
      movie = create_standalone_movie(%{name: "Movie A"})

      Phoenix.PubSub.broadcast(MediaCentarr.PubSub, Topics.library_updates(),
        %Library.Events.EntitiesChanged{entity_ids: [movie.id]})

      assert_receive {:library_view_updated, :browse}, 500
      assert [%BrowseItem{name: "Movie A"}] = Views.browse()
    end
  end

  describe "refresh on library:availability" do
    test "file becoming present surfaces the entity under :present-only"
    test "file becoming absent removes the entity from :present-only"
  end

  describe "BrowseItem shape" do
    test "has typed fields (no string-key map access)"
    test "year derived from container.date_published"
    test "poster_url populated when entity has a poster image"
  end
end
```

**Why these tests:** they exercise the contract through the read API (`Views.browse/1`), not the internals. The PubSub-synchronisation pattern (subscribe to derived topic, broadcast source event, assert_receive) is the flake-free way to wait for the projection to update.

### Implementation steps

- [ ] **A.1 Write `browse_test.exs`** covering all cases above. Run it — expect failures on every test (modules don't exist yet).
- [ ] **A.2 Write `BrowseItem` typed struct** with `@type t :: %__MODULE__{...}`, factory helper in `test/support/factory.ex` (`build_browse_item/1`).
- [ ] **A.3 Implement `Library.Views.Browse`** — Cache behaviour module: `subscribe/0`, `relevant?/1`, `refresh_cache/0`. Source: `Library.Browser.list/2` output (or a new optimised query). ETS table init, replace-all on refresh.
- [ ] **A.4 Wire `Cache.Worker`** into `lib/media_centarr/application.ex` supervision tree.
- [ ] **A.5 Implement `Library.Views.browse/1` reader** in `lib/media_centarr/library/views.ex` (the umbrella read module — already exists, you're adding to it).
- [ ] **A.6 Migrate `LibraryLive` mount path** to read from `Library.Views.browse/1` instead of `Library.Browser.list/2`. Subscribe to derived topic. Section_reloader pattern from existing projections.
- [ ] **A.7 Update page smoke test** if the LibraryLive zone count or fixture shape changed.
- [ ] **A.8 `mix precommit` green.** Run `mix test --repeat-until-failure 3 test/media_centarr/library/views/browse_test.exs test/media_centarr_web/page_smoke_test.exs` for flake check.
- [ ] **A.9 Commit:** `jj describe -m "feat(library): Views.Browse projection — LibraryLive reads in microseconds"`

---

## Task B — `Library.Views.Detail`

**Goal:** Per-PlayableItem read projection. Detail modal opens → single `:ets.lookup` returns the full view-model (container metadata + cast/crew + extras + watch progress + present files). Replaces `TypeResolver.resolve_by_playable_item/2 + Repo.preload(...)` on the render path.

**Public read API:**
```elixir
@spec Library.Views.detail(playable_item_id :: Ecto.UUID.t()) :: DetailItem.t() | nil
def detail(playable_item_id)

# Companion: lookup by container UUID (for back-compat with URLs like /library?selected=<container_id>)
@spec Library.Views.detail_by_container(container_type :: atom(), container_id :: Ecto.UUID.t()) :: DetailItem.t() | nil
def detail_by_container(container_type, container_id)
```

**Cache.Worker shape:** Named ETS table `:library_view_detail`. Keyed by `playable_item_id`. Probably `:set` (one entry per PlayableItem). Reads bypass GenServer.

**Refresh triggers:**
- `library:updates` (entity create/edit/delete + image-ready + metadata-refresh)
- `watch_history:events` (watch_event_created/deleted — affects progress)
- `playback:events` (entity_progress_updated — keeps progress bar live)
- `library:availability` (file presence — affects "playable now" gate)

**Derived topic broadcast:** `{:library_view_updated, :detail, playable_item_id}` on `library:views` — partial broadcast lets DetailLive subscribe to only its current playable_item_id.

### Test plan (write FIRST)

```elixir
describe "cold start" do
  test "returns nil for unknown id"
  test "returns full DetailItem for a movie with all preloads"
  test "returns DetailItem for an episode with parent TVSeries metadata"
  test "returns DetailItem for a movie-series-child with parent MovieSeries metadata"
  test "DetailItem includes preloaded cast/crew structs"
  test "DetailItem includes present file paths only"
end

describe "refresh on library:updates" do
  test "metadata edit reflects in next read"
  test "image-ready broadcast updates poster_url"
end

describe "refresh on watch_history:events" do
  test "completion event updates watch_progress shape"
end

describe "refresh on playback:events" do
  test "entity_progress_updated keeps position_seconds current without page reload"
end

describe "partial broadcast" do
  test "broadcasts {:detail, playable_item_id} on library:views, not a firehose"
end

describe "detail_by_container/2 lookup" do
  test "resolves container UUID to first PlayableItem's DetailItem"
  test "multi-cut Movie returns the canonical (position=1) cut by default"
end
```

### Implementation steps

- [ ] **B.1 Write `detail_test.exs`** with all cases above. Run → red.
- [ ] **B.2 `DetailItem` typed struct** with full view-model shape (container metadata + cast/crew + extras + progress + present_files). Factory `build_detail_item/1`.
- [ ] **B.3 Implement `Library.Views.Detail`** Cache behaviour module. Cold-start build: one query per PlayableItem with full preload. Refresh: per-entity targeted update (don't rebuild every entry on every event — use `entity_ids` from `EntitiesChanged`).
- [ ] **B.4 Application supervision wiring.**
- [ ] **B.5 `Library.Views.detail/1` + `detail_by_container/2` readers** in `Library.Views`.
- [ ] **B.6 Migrate `DetailLive` (or `EntityModal`)** to read from the projection. Subscribe to the partial-broadcast derived topic.
- [ ] **B.7 Page smoke test update** if Detail rendering changed.
- [ ] **B.8 `mix precommit` green** + flake check.
- [ ] **B.9 Commit:** `jj describe -m "feat(library): Views.Detail projection — DetailLive reads in microseconds"`

---

## Task C — `Library.Views.Search`

**Goal:** In-memory full-text-ish search across the library. Replaces ad-hoc `where ilike` queries. For ≤10K entries, an in-memory scan (`Enum.filter` over the ETS table) is sub-10ms with a cheap Jaro/contains-match scorer.

**Public read API:**
```elixir
@spec Library.Views.search(query :: String.t(), opts :: keyword()) :: [SearchItem.t()]
def search(query, opts \\ [])
# opts: :limit, :kind_filter
```

`SearchItem` is a minimal struct (`%SearchItem{playable_item_id, container_type, container_id, name, year, score}`).

**Cache.Worker shape:** Named ETS table `:library_view_search`. Each row is a `(playable_item_id, normalised_search_text, container_type, container_id, name, year)` tuple. Read does `:ets.foldl/3` with the scorer.

**Refresh triggers:**
- `library:updates` (entity create/edit/delete)

**Derived topic broadcast:** `{:library_view_updated, :search}` on `library:views`. (Less time-critical; consumers re-search on demand.)

### Test plan (write FIRST)

```elixir
describe "search/2" do
  test "returns empty for unknown query"
  test "exact name match returns the entity"
  test "case-insensitive match"
  test "partial substring match scored lower than exact"
  test "results sorted by descending score"
  test "respects :limit option"
  test "respects :kind_filter (e.g. :movies only)"
  test "filters out absent-only entities when :present_only is true"
end

describe "refresh on library:updates" do
  test "newly created entity becomes searchable on next read"
  test "renamed entity is no longer matched by old name"
  test "deleted entity disappears from results"
end

describe "scoring" do
  test "Jaro score is higher for closer matches"
  test "exact match wins over substring"
end
```

### Implementation steps

- [ ] **C.1 Write `search_test.exs`** — red.
- [ ] **C.2 `SearchItem` typed struct** + factory.
- [ ] **C.3 Implement `Library.Views.Search`** with scorer (pure function — `Library.Views.Search.Scorer` if it grows; unit-test independently with `async: true`).
- [ ] **C.4 Application supervision wiring.**
- [ ] **C.5 `Library.Views.search/2` reader.**
- [ ] **C.6 Migrate existing search consumers** — find them via grep (likely in `Library` context functions and any LiveView search input).
- [ ] **C.7 Page smoke test update** for the route hosting search if it changed.
- [ ] **C.8 `mix precommit` green** + flake check.
- [ ] **C.9 Commit:** `jj describe -m "feat(library): Views.Search in-memory entity index"`

---

## Task D — `Library.Progress` (Pillar-2 GenServer)

**Goal:** Move active watch progress to a Pillar-2 GenServer. Position updates from MpvSession write to the GenServer's state; the GenServer debounce-flushes to the DB every ~5 seconds. LiveView reads (Continue Watching, Detail) come from the GenServer (or its ETS-backed read snapshot) — never from a DB query during active playback.

**Public API (writes):**
```elixir
@spec Library.Progress.record(playable_item_id, position_seconds, duration_seconds) :: :ok
def record(playable_item_id, position_seconds, duration_seconds)

@spec Library.Progress.complete(playable_item_id) :: :ok
def complete(playable_item_id)
```

**Public API (reads):**
```elixir
@spec Library.Progress.get(playable_item_id) :: %WatchProgress{} | nil
def get(playable_item_id)
```

Reads bypass the GenServer via `:ets.lookup` on a worker-owned table.

**Internal flush:** `handle_info(:flush, state)` writes any dirty progress to `library_watch_progress` via `Library.upsert_watch_progress/1`. Flush interval ~5s. On `terminate/2`, flush synchronously so a clean shutdown doesn't lose state.

**Derived broadcasts:** `{:entity_progress_updated, playable_item_id, position_seconds}` on `playback:events` — preserves the existing live-progress-bar UX.

### Test plan (write FIRST — this is the most stateful task; tests must NOT use :sys.get_state or GenServer.call internals)

```elixir
describe "record/3 → get/1 round trip" do
  test "writes are immediately visible via get/1 (read-after-write)"
  test "concurrent writes serialize correctly (no torn updates)"
end

describe "debounced flush" do
  # Tests via the public effect: WatchProgress row in DB after the flush window
  test "flush writes pending progress to library_watch_progress within 5s"
  test "multiple writes within the window coalesce to one DB row"
  test "graceful shutdown synchronously flushes (terminate/2 contract)"

  # Synchronisation: use the broadcast that fires on flush completion, not Process.sleep
  test "broadcasts :progress_flushed on flush completion" do
    subscribe_to_progress_flushes()
    Library.Progress.record(id, 30.0, 100.0)
    assert_receive {:progress_flushed, ^id}, 6_000
    assert %WatchProgress{position_seconds: 30.0} = Repo.get_by(WatchProgress, playable_item_id: id)
  end
end

describe "complete/1" do
  test "writes a completed: true progress row"
  test "broadcasts watch completion on watch_history:events"
end

describe "boot hydration" do
  test "hydrates from DB on start so in-progress entries survive restart"
end
```

**Critical:** all tests use the PUBLIC `Library.Progress.record/3` + `Library.Progress.get/1` + `Repo.get` (for DB-side verification after flush). NEVER `:sys.get_state(Library.Progress.Worker)`. NEVER `GenServer.call(Worker, :something_internal)`. If a test feels like it needs those, the public API is missing a function — add it.

### Implementation steps

- [ ] **D.1 Write `progress_test.exs`** — red against the missing module.
- [ ] **D.2 Implement `Library.Progress`** — `Cache.Worker` behaviour: GenServer holds the in-memory table reference, debounced flush via `Process.send_after/3`, public API delegates to GenServer cast for writes and direct ETS read for `get/1`.
- [ ] **D.3 Wire into application supervision.**
- [ ] **D.4 Migrate `MpvSession.handle_event(:progress, ...)`** to write via `Library.Progress.record/3` instead of `Library.create_or_update_watch_progress/1`.
- [ ] **D.5 Audit any other writer of WatchProgress** (Maintenance, Showcase, factory) — confirm the new path is the only production writer; tests + showcase can still use the existing factory/seed helpers, which write directly to DB.
- [ ] **D.6 Page smoke tests** affected? (Continue Watching is already projection-fed; Detail will be too after Task B.) Verify nothing regresses.
- [ ] **D.7 `mix precommit` green** + repeat-until-failure on `progress_test.exs` (this is the most flake-prone task; the debounce window must be tested deterministically).
- [ ] **D.8 Commit:** `jj describe -m "feat(library): Progress Pillar-2 GenServer with debounced flush"`

---

## Task E — Audit + retire DB-on-render reads

**Goal:** Final cleanup. Every LiveView mount/handle_info that still calls `MediaCentarr.Repo.*` for Library data either:
- (a) moves to a `Library.Views.*` projection
- (b) carries an explicit `# Direct DB read by design: <reason>` comment

**Approach:** Grep `Repo\.` in `lib/media_centarr_web/live/`, evaluate each hit, fix or annotate.

### Test plan

```elixir
# In test/media_centarr_web/page_smoke_test.exs (or a dedicated module):
describe "no DB-on-render contract" do
  # Optional but high-value: use Ecto.Adapters.SQL.query_count or similar
  # to count queries during mount, and assert ≤ N for the section's projection
  # cold-start cost.
  test "LibraryLive mount issues 0 Repo queries for the render path"
  test "DetailLive mount issues 0 Repo queries for the render path"
  test "HomeLive mount issues 0 Repo queries (already projection-fed; baseline)"
end
```

If the query-count helper doesn't exist, write it first as part of this task (it's reusable across LiveViews). It probably belongs in `test/support/query_counter.ex` or similar.

### Implementation steps

- [ ] **E.1 Inventory:** `grep -rn 'Repo\.' lib/media_centarr_web/live/` and categorise each hit.
- [ ] **E.2 Write the query-counter test helper** if it doesn't exist. Use `:telemetry.attach/4` against `[:media_centarr, :repo, :query]`.
- [ ] **E.3 Write `no_db_on_render_test.exs`** that asserts each LiveView's mount issues 0 (or N, with N documented) queries for the render path. Run — red where Repo is still being hit.
- [ ] **E.4 Fix each LiveView** by moving to projection reads or annotating with rationale.
- [ ] **E.5 `mix precommit` green** + the new test suite stays at 0 queries.
- [ ] **E.6 Commit:** `jj describe -m "refactor(web): retire DB-on-render reads; LiveViews read from projections"`

---

## Workflow per task

Each task above gets a fresh subagent dispatch:
1. Implementer subagent (general-purpose) — **TDD strictly**: write the failing test, see red, implement, see green, run precommit, commit (no `jj new`).
2. Combined spec + quality reviewer (general-purpose) — verify spec compliance, evaluate quality, flag issues.
3. If issues, fix subagent — `jj squash` into the task's commit.

**Per-task budget:** ~40 minutes from dispatch to completion. Phase 3 has 5 tasks → ~3.5 hours.

## Conventions

- **Jujutsu:** `-m` flags always.
- **No real show titles:** placeholders only.
- **`# Follow-up:`** not `# TODO:` (Credo strict).
- **No raw SQL inspection** of state in production code — use context functions.
- **Architectural fixes, not symptom covers** — if a read path needs N queries on mount, the right fix is a projection, not a `Repo.preload`.
- **One ETS table per view** (per ADR-041) — don't multiplex; keep snapshots independent.
- **Subscribe-canonical-emit-derived** PubSub pattern (per ADR-041) — projections subscribe to source topics, broadcast on derived topics; LiveViews subscribe to derived topics only.

## Completion criteria

- Every Library read path used by a LiveView reads from a `Library.Views.*` projection.
- `Library.Progress` is a Pillar-2 GenServer with debounced flush; MpvSession writes via its public API; no DB writes on the playback tick path.
- `grep -rn 'Repo\.' lib/media_centarr_web/live/` returns zero hits without an explanatory `# Direct DB read by design` annotation.
- `mix precommit` green; all baselines stable across three consecutive `scripts/profile` runs.
- Per-task spec tests + per-route page smoke tests all green and deterministic.
- ADR added (or amended) documenting the new projections and the watch-progress GenServer.
- Campaign file updated: Phase 3 marked complete + follow-ups listed.

## Out of scope

- Distributed projection (`:pg` / Horde) — single-node desktop app.
- Cross-context projections (e.g. unifying ReleaseTracking + Library views) — out of scope; each context owns its projections.
- Multi-user / Scope-aware projections — already paradigm-clean per `desktop-rearchitecture` campaign.
- Real-time search-as-you-type latency tuning — Task C delivers the substrate; UX-level latency is a follow-up.
- Component-contracts (separate campaign).

## Pointers

- [ADR-041 — In-memory projection architecture](../../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md)
- [`campaigns/done/library-schema-v2.md`](../../../campaigns/done/library-schema-v2.md)
- [`campaigns/done/desktop-rearchitecture.md`](../../../campaigns/done/desktop-rearchitecture.md) — partner campaign; Phase 3's projections feed Workstream A
- `lib/media_centarr/cache.ex` — Cache.Worker behaviour
- `lib/media_centarr/library/views/continue_watching.ex` — canonical projection
- `test/media_centarr/library/views/continue_watching_test.exs` — canonical projection test
- `lib/media_centarr/topics.ex` — PubSub topic registry
