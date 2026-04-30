# Durable Acquisition Search Session — Design

**Date:** 2026-04-30
**Status:** Approved for implementation planning

## Problem

`AcquisitionLive` (mounted at `/download`) holds the entire search workflow in socket assigns: `query`, `expansion_preview`, `searching?`, `groups`, `selections`, `grabbing?`, `grab_message`. Per-query Tasks for brace-expanded queries `send(parent, ...)` to the LiveView PID. When the user navigates away from `/download`, the LiveView terminates, the assigns vanish, the in-flight Tasks send to a dead PID, and the entire session is lost.

The activity log and the active download queue are already durable — they are backed by `acquisition_grabs` rows and the `QueueMonitor` GenServer respectively. Only the search session is ephemeral.

The goal: a user starts a search, navigates to a different LiveView, then returns to `/download` and finds the page exactly as they left it — same query in the input, same group results visible, same selections checked, same grab feedback message displayed.

## Scope

Durability target: **survives LiveView navigation, browser refresh, and LiveView reconnect. Lost on BEAM restart.** This matches the single-user LAN-only nature of the application — process-resident state with PubSub fan-out is sufficient; a database-backed search session would be over-engineering.

Session model: **one global slot.** At most one active search session exists at any time. Submitting a new query replaces the previous one wholesale. There is no search history.

In-flight task model: **searches effectively cancel on LiveView exit.** Per-query Tasks remain spawned through `Task.Supervisor.start_child/2` (unlinked, as today). When the LiveView dies, the GenServer's monitor fires `:DOWN`, and any group still in `:loading` is swept to a new `:abandoned` status so a subsequent mount renders a Retry button instead of a stuck spinner. The orphaned Tasks may continue running until Prowlarr replies; their results call `record_search_result/2` and are silently dropped because the target groups are no longer in `:loading`. From the user's standpoint the search is cancelled — the loading state is gone, retry is required to see fresh results. The minor inefficiency (Prowlarr quota for results that won't be displayed) is acceptable for a self-hosted indexer; linking Tasks to the LV would save quota at the cost of supervision-tree complexity that is not worth it here.

Out of scope:
- Multiple concurrent search sessions or per-tab independence.
- Search history (revisiting prior searches).
- Surviving BEAM restart.
- Auto-retry of abandoned groups on remount; the user explicitly clicks Retry.

## Design

### 1. Session struct and group statuses

A new module `MediaCentarr.Acquisition.SearchSession` defines both the data shape and the GenServer that owns it. The data structure:

```elixir
defmodule MediaCentarr.Acquisition.SearchSession do
  alias MediaCentarr.Acquisition.SearchResult

  @type group_status :: :loading | :ready | {:failed, term()} | :abandoned

  @type group :: %{
          term: String.t(),
          status: group_status(),
          results: [SearchResult.t()],
          expanded?: boolean()
        }

  @type t :: %__MODULE__{
          query: String.t(),
          expansion_preview: :idle | {:ok, pos_integer()} | {:error, atom()},
          groups: [group()],
          selections: %{String.t() => String.t()},
          grab_message: nil | {:ok | :partial | :error, String.t()},
          grabbing?: boolean(),
          searching_pid: nil | pid()
        }

  defstruct query: "",
            expansion_preview: :idle,
            groups: [],
            selections: %{},
            grab_message: nil,
            grabbing?: false,
            searching_pid: nil
end
```

**Empty session = struct with default fields.** There is always a session; it just may be empty. No nil-versus-some discrimination needed.

**One new group status, `:abandoned`,** distinct from `{:failed, reason}`:
- `:loading` — a Task is genuinely in flight.
- `:ready` — Task completed with results (possibly empty).
- `{:failed, reason}` — Task completed with an error from Prowlarr (timeout, HTTP error, etc.).
- `:abandoned` — the LiveView that owned this group's Task died before the Task completed. The group renders the same Retry affordance as `{:failed, _}` but logs differently (`"search abandoned"` vs `"search failed"`). Note: the Task itself may still complete in the background; the late-arriving result is silently dropped by `record_search_result/2`'s idempotency clause.

`grabbing?` is hoisted into the session so the bulk-grab feedback also persists across navigation. A user who clicks "Grab 3 selected" and immediately navigates away returns to the spinner state until the grab completes.

### 2. GenServer: `MediaCentarr.Acquisition.SearchSession`

A standalone, named GenServer started under `MediaCentarr.Application`'s supervision tree, distinct from the existing `MediaCentarr.Acquisition` GenServer. Separation of concerns: the existing `Acquisition` GenServer is event-driven (handles `:release_ready` and `:item_removed` PubSub messages from release-tracking); the search session is request-driven (handles `call`s from `AcquisitionLive`). Folding both into one module would blur the responsibilities and grow the file.

GenServer state holds a single `%SearchSession{}` struct. All public access goes through the `Acquisition` facade — no module outside the Acquisition context calls `GenServer.call(SearchSession, ...)` directly.

### 3. Facade API on `Acquisition`

Names match the codebase's existing naming conventions (`subscribe/0`, `subscribe_queue/0`).

```elixir
# Read — synchronous, called by LiveView mount.
@spec current_search_session() :: SearchSession.t()
def current_search_session

# Subscribe — receivers get {:search_session, %SearchSession{}} on every change.
@spec subscribe_search() :: :ok
def subscribe_search

# Write — start a new search. Captures the calling pid, monitors it,
# returns expanded queries so the LiveView can spawn the per-query Tasks.
@spec start_search(String.t()) ::
        {:ok, %{session: SearchSession.t(), queries: [String.t()]}}
        | {:error, :invalid_syntax}
def start_search(query)

# Write — live preview of the brace-expanded query count as the user types.
@spec set_query_preview(String.t()) :: :ok
def set_query_preview(query)

# Write — a per-query Task completed.
@spec record_search_result(String.t(), {:ok, [SearchResult.t()]} | {:error, term()}) :: :ok
def record_search_result(term, outcome)

# Write — selection toggle and group expand/collapse.
@spec set_selection(term :: String.t(), guid :: String.t()) :: :ok
def set_selection(term, guid)
@spec clear_selection(term :: String.t()) :: :ok
def clear_selection(term)
@spec clear_selections() :: :ok
def clear_selections
@spec toggle_group(String.t()) :: :ok
def toggle_group(term)

# Write — grab lifecycle. set_grabbing/1 flips the spinner state on/off
# without clearing selections; set_grab_message/1 records the final outcome.
@spec set_grabbing(boolean()) :: :ok
def set_grabbing(value)
@spec set_grab_message({:ok | :partial | :error, String.t()}) :: :ok
def set_grab_message(message)

# Write — explicit reset.
@spec clear_search_session() :: :ok
def clear_search_session

# Write — re-fire abandoned/failed groups. The new caller becomes searching_pid.
@spec retry_search_terms([String.t()]) :: :ok
def retry_search_terms(terms)
```

A new PubSub topic `acquisition:search` is added to `MediaCentarr.Topics`. Distinct from the existing `acquisition:updates`, because that topic is broadcast app-wide for grab lifecycle events (every LiveView showing grab status subscribes); the search session is purely a `/download` page concern and should not be force-fanned to unrelated subscribers.

`start_search/1` and `retry_search_terms/1` swap the `searching_pid` monitor to the new caller — if the LiveView restarts (navigate away, come back, hit Retry), the monitor follows the live process, not the dead one.

### 4. LiveView refactor

`AcquisitionLive` becomes a thin viewer. The cluster of search-related socket assigns collapses into one: `search_session`. Other assigns unchanged: `active_queue`, `queue_loaded?`, `cancel_confirm`, `download_client_ready`, `activity_filter`, `activity_search`, `reload_timer`, `activity_grabs`.

**`mount/3`** reads the session and subscribes:

```elixir
if connected?(socket) do
  Acquisition.subscribe()
  Acquisition.subscribe_search()
  Capabilities.subscribe()
  Process.send_after(self(), :poll_queue, 0)
end

assign(socket, search_session: Acquisition.current_search_session(), ...)
```

**`handle_params/3`** — for the `?prowlarr_search=…` deep link: instead of building placeholder groups inline, it calls `Acquisition.start_search(query)` and spawns Tasks for the returned queries. Same code path as the form submission.

**`handle_event` rewrites** — every search-related event becomes a one-line facade call, no socket-assign mutation:

| Event | Replacement |
|---|---|
| `query_change` | `Acquisition.set_query_preview(query)` |
| `submit_search` | `Acquisition.start_search(query)` → spawn Tasks for returned queries |
| `select_result` | `Acquisition.set_selection/2` or `clear_selection/1` |
| `toggle_group` | `Acquisition.toggle_group(term)` |
| `retry_search` / `retry_all_timeouts` | `Acquisition.retry_search_terms([...])` → spawn Tasks |
| `grab_selected` | `Acquisition.set_grabbing(true)`; spawn `:run_grabs`; the grab handler later calls `set_grabbing(false)`, `set_grab_message/1`, `clear_selections/0` |

Activity-zone events (`set_activity_filter`, `set_activity_search`, `cancel_activity_grab`, `rearm_activity_grab`) and the download-cancel modal events are unchanged — those operate on already-durable state.

**`handle_info`:**
- `{:search_session, session}` — the new PubSub message. `assign(socket, search_session: session)`. The single update path that makes "ui is where I left it" work.
- `{:run_search_one, query}` — spawns an unlinked `Task.Supervisor.start_child/2` as today, but the Task calls `Acquisition.record_search_result/2` on completion instead of sending to the LV PID. The session-changed broadcast fans out to this LV (and any other listener).
- `{:search_result, …}` — **deleted.** Replaced by the session-changed broadcast.
- `{:run_grabs, …}` — unchanged in shape; on completion calls the facade rather than mutating assigns.
- `:poll_queue`, `:capabilities_changed`, `:reload_activity`, the activity-zone `:grab_*` events, debounce — all unchanged.

**Render** — every reference to a former assign becomes `@search_session.<field>`. `@searching?` is derived: `Logic.any_loading?(@search_session.groups)`.

**Logic relocation** — most of `MediaCentarrWeb.AcquisitionLive.Logic` (placeholder_groups, apply_search_result, add_default_selection, toggle_group, mark_group_loading, all_loaded?, find_result, build_grab_message) moves into `MediaCentarr.Acquisition.SearchSession` as private functions or stays in `Logic` and is called by the GenServer. The LiveView no longer needs them. `Logic` retains only template-only helpers (formatting, color classes, expansion preview text, timeout_terms list extraction). This is a small ADR-029-style boundary win: search-state logic now lives inside the Acquisition context, not the web layer.

### 5. Lifecycle: monitor, abandonment, retry

**`start_search/1`:**
1. Expand the query via `QueryExpander.expand/1`. Failure → `{:error, :invalid_syntax}`, no state change.
2. Replace the session: new `query`, fresh placeholder `groups` (all `:loading`), `selections: %{}`, `grab_message: nil`, `grabbing?: false`, `searching_pid: caller_pid`.
3. Demonitor any previous `searching_pid`, monitor the caller.
4. Broadcast `{:search_session, session}`.
5. Return `{:ok, %{session: session, queries: queries}}`.

**`record_search_result/2`:**
1. Find the matching group by term. Transition `:loading → :ready` or `:loading → {:failed, reason}`.
2. If `:ready`, add the default top-seeder selection (existing `Logic.add_default_selection` rule).
3. Broadcast `{:search_session, session}`.
4. **Idempotent:** a result for a term already in a terminal status (`:abandoned`, `{:failed, _}`, `:ready`) is dropped silently. This handles the late-arriving Task case where the LV crashed, the group was swept to `:abandoned`, and the orphaned Task somehow sneaks in a final write.

**LiveView crash (`:DOWN` from monitored `searching_pid`):**
1. Sweep every `:loading` group → `:abandoned`.
2. Clear `searching_pid`.
3. Broadcast `{:search_session, session}` (keeps the topic-as-source-of-truth invariant even when no subscriber is alive).
4. Log `Log.info(:acquisition, "search abandoned — N groups, query=…")`.

**`retry_search_terms/1`:**
1. Transition each named term `:abandoned | {:failed, _}` → `:loading`. Terms in other states (`:ready`, `:loading`) are no-ops for that term.
2. Demonitor previous `searching_pid`, monitor the new caller.
3. Broadcast.
4. The LiveView, having just called the facade, immediately spawns Tasks for those terms.

**Grab success — explicit reset, not implicit:**
The current LiveView clears `selections` after a grab batch and shows `grab_message`. Preserved: `set_grab_message/1` and `clear_selections/0` are two distinct calls. Groups stay (the user may want to grab again from the same results); checkboxes clear; the result message flashes.

**No per-search timeout.** A search either finishes, fails, or gets abandoned. Loading groups never auto-flip to abandoned without an LV crash. The Prowlarr client already enforces its own request timeout that yields `{:failed, :timeout}`.

## Testing

Test-first per the `automated-testing` skill: SearchSession tests are written before the SearchSession module; LiveView tests are extended before the LiveView refactor.

### `test/media_centarr/acquisition/search_session_test.exs` — async pure GenServer tests

- Each test starts a fresh GenServer with `start_supervised!({SearchSession, name: :"sess_#{System.unique_integer()}"})` so they run async.
- Public-API only — never `:sys.get_state` (ADR-026, enforced by the `NoSysIntrospection` Credo check).
- Coverage:
  - `start_search/1` returns expanded queries, populates placeholder groups (all `:loading`), replaces a previous session's selections.
  - `start_search/1` with invalid brace syntax returns `{:error, :invalid_syntax}` and does not mutate state.
  - `record_search_result/2` transitions `:loading → :ready` and adds the default top-seeder selection.
  - `record_search_result/2` for an unknown term is a silent no-op.
  - `record_search_result/2` for a term already swept to `:abandoned` is a silent no-op (idempotency under crash + late-arriving Task).
  - `:DOWN` from the monitored pid sweeps every `:loading` group to `:abandoned` and clears `searching_pid`. Test by spawning a process, calling `start_search` from inside it, killing it, then asserting via `current_search_session/0`.
  - `retry_search_terms/1` transitions named `:abandoned`/`{:failed, _}` groups to `:loading` and re-monitors the caller.
  - `set_selection`/`clear_selection`/`clear_selections`/`toggle_group`/`set_grabbing`/`set_grab_message`/`clear_search_session` round-trip correctly.
- Subscribers receive `{:search_session, session}` on every write — verified via `Phoenix.PubSub.subscribe` then `assert_receive`.

### `test/media_centarr_web/live/acquisition_live_test.exs` — extend the existing LiveView test

- Mount, submit search, navigate away (`live_redirect` to `/`), navigate back to `/download`. Assert the new mount shows the same query, same groups, same selections.
- Mount, submit search with one query still `:loading`, kill the LiveView process, mount again. Assert the loading group renders as `:abandoned` with a Retry affordance.
- Hit Retry. Assert the group goes back to `:loading` and a Task is spawned. Prowlarr is stubbed via `Req.Test`, extending the project's existing TMDB-stub pattern in `test/support/` if no Prowlarr stub already exists.
- Selection persists across navigation.
- Grab message persists across navigation until the next search.

### `MediaCentarrWeb.AcquisitionLive.Logic` tests

Most existing assertions move to `SearchSession` tests since the logic moved. `Logic` retains only template helpers (color classes, expansion preview text, timeout-term extraction); those stay as small async unit tests.

## Migration

This is a non-data-migrating refactor:
- No new database tables, no migrations, no Ecto schema changes.
- One new module (`MediaCentarr.Acquisition.SearchSession`).
- One new entry in `MediaCentarr.Application`'s child spec list.
- One new function in `MediaCentarr.Topics`.
- New exports in the `Acquisition` `use Boundary` declaration: `SearchSession` is internal but the new public functions live on the `Acquisition` facade and need no boundary changes for callers.
- `MediaCentarrWeb.AcquisitionLive` and `MediaCentarrWeb.AcquisitionLive.Logic` are rewritten in place; no other web modules touched.

The change can ship in a single commit since the LiveView and the GenServer must be consistent. Pre-existing search behavior is preserved — every visible feature today (brace expansion, grouped results, top-seeder default selection, retry timeouts, grab batch with feedback message, deep-link `?prowlarr_search=…`) continues to work identically. The only user-visible difference is that the search now persists across navigation.

## Non-goals revisited

- **No DB-backed sessions.** Adding an `acquisition_search_sessions` table to survive BEAM restart was considered and rejected: the search session is conceptually a UI working set, not a durable record, and a BEAM restart on a self-hosted LAN tool is rare and re-running the search is a one-click operation.
- **No per-tab independence.** Single-user LAN; if the user opens `/download` in two tabs, both will reflect the same global session — this matches the actual use case and avoids tab-affinity bookkeeping.
- **No automatic abandonment-on-timeout for `:loading` groups in an alive LV.** If the LV is alive, `:loading` is honest until either Prowlarr replies or the Prowlarr client times out and yields `{:failed, :timeout}`.
