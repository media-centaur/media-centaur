# Durable Acquisition Search Session — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the manual-search slot at `/download` durable across LiveView navigation, browser refresh, and reconnect by extracting search state from `AcquisitionLive` socket assigns into a process-resident `SearchSession` GenServer.

**Architecture:** A new singleton GenServer `MediaCentarr.Acquisition.SearchSession` owns a `%SearchSession{}` struct (query, expansion preview, groups with `:loading | :ready | {:failed, _} | :abandoned` status, selections, grab message, grabbing flag, monitored searching pid). The `MediaCentarr.Acquisition` facade exposes `current_search_session/0`, `subscribe_search/0`, `start_search/1`, `record_search_result/2`, selection/toggle/grab mutators, and `retry_search_terms/1`. `AcquisitionLive` becomes a thin viewer: it reads on mount, subscribes to a new `acquisition:search` PubSub topic, and every event delegates to the facade. When the LiveView dies mid-search, the GenServer's monitor sweeps `:loading` groups to `:abandoned` so the next mount renders Retry buttons. Tasks remain unlinked; late-arriving results are silently dropped by an idempotency check.

**Tech Stack:** Elixir / OTP (`GenServer`, `Process.monitor`, `Phoenix.PubSub`), Phoenix LiveView, ExUnit, `MediaCentarr.Topics`, existing `Req.Test`-backed Prowlarr stub.

**Spec:** `docs/superpowers/specs/2026-04-30-acquisition-search-session-design.md`

**Repo:** `/home/shawn/src/media-centarr/media-centarr-app/` (Jujutsu — use `jj desc -m` and `jj new` per the jujutsu skill, not raw `git commit`).

---

## Task 1: Foundation — Topics, struct, skeleton GenServer, supervision

Adds the `acquisition:search` topic, the `SearchSession` struct, an empty GenServer, and wires it into the application supervision tree. No behavior yet — just enough to start the process and read its empty state.

**Files:**
- Modify: `lib/media_centarr/topics.ex` (add `acquisition_search/0`)
- Create: `lib/media_centarr/acquisition/search_session.ex`
- Create: `test/media_centarr/acquisition/search_session_test.exs`
- Modify: `lib/media_centarr/application.ex` (children list — add `MediaCentarr.Acquisition.SearchSession`)

- [ ] **Step 1: Write the failing skeleton test**

Create `test/media_centarr/acquisition/search_session_test.exs`:

```elixir
defmodule MediaCentarr.Acquisition.SearchSessionTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.SearchSession

  describe "default state" do
    test "fresh GenServer returns empty session" do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})

      session = SearchSession.current(name)

      assert %SearchSession{
               query: "",
               expansion_preview: :idle,
               groups: [],
               selections: %{},
               grab_message: nil,
               grabbing?: false,
               searching_pid: nil
             } = session
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/acquisition/search_session_test.exs
```

Expected: compile error — `MediaCentarr.Acquisition.SearchSession` is undefined.

- [ ] **Step 3: Add the topic**

Edit `lib/media_centarr/topics.ex`. Add a new function after `acquisition_queue/0`:

```elixir
  def acquisition_search, do: "acquisition:search"
```

- [ ] **Step 4: Create the SearchSession module (struct + skeleton GenServer)**

Create `lib/media_centarr/acquisition/search_session.ex`:

```elixir
defmodule MediaCentarr.Acquisition.SearchSession do
  @moduledoc """
  Singleton GenServer holding the user's current acquisition search session.

  Decouples the search workflow from `MediaCentarrWeb.AcquisitionLive`'s
  process lifetime so search state — query, brace-expanded groups, results,
  user selections, grab feedback — survives navigation, reconnect, and
  browser refresh. Lost on BEAM restart.

  All public access goes through the `MediaCentarr.Acquisition` facade —
  no module outside the Acquisition context calls this GenServer directly.

  See `docs/superpowers/specs/2026-04-30-acquisition-search-session-design.md`.
  """

  use GenServer

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

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns the current session struct."
  @spec current(GenServer.server()) :: t()
  def current(server \\ __MODULE__) do
    GenServer.call(server, :current)
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call(:current, _from, state) do
    {:reply, state, state}
  end
end
```

- [ ] **Step 5: Wire SearchSession into the supervision tree**

Edit `lib/media_centarr/application.ex`. Find the children list and add `MediaCentarr.Acquisition.SearchSession` adjacent to the existing `MediaCentarr.Acquisition` and `MediaCentarr.Acquisition.QueueMonitor` children. The exact location is the same children block where `MediaCentarr.Acquisition` is started (line 17 in current source). Add:

```elixir
      MediaCentarr.Acquisition.SearchSession,
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/acquisition/search_session_test.exs
```

Expected: `1 test, 0 failures`.

- [ ] **Step 7: Verify nothing else broke**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors
```

Expected: clean compile, no warnings (Boundary checks pass since `SearchSession` is internal to the Acquisition context).

- [ ] **Step 8: Commit**

```bash
jj desc -m "feat(acquisition): scaffold SearchSession GenServer + topic"
jj new
```

---

## Task 2: `start_search/1` — replace session, monitor caller, return queries

Implements the entry point. `start_search/1` expands the query via `QueryExpander.expand/1`, replaces the entire session with a fresh one (placeholder `:loading` groups, empty selections, no grab message), monitors the caller, and broadcasts the new session.

**Files:**
- Modify: `lib/media_centarr/acquisition/search_session.ex`
- Modify: `test/media_centarr/acquisition/search_session_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to the test file:

```elixir
  describe "start_search/1" do
    setup do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_search())
      {:ok, name: name}
    end

    test "places one :loading group per expanded query and broadcasts", %{name: name} do
      assert {:ok, %{session: session, queries: queries}} =
               SearchSession.start_search(name, "Show S01E{01-03}")

      assert queries == ["Show S01E01", "Show S01E02", "Show S01E03"]
      assert session.query == "Show S01E{01-03}"
      assert length(session.groups) == 3
      assert Enum.all?(session.groups, fn group -> group.status == :loading end)
      assert Enum.map(session.groups, & &1.term) == queries
      assert session.selections == %{}
      assert session.grab_message == nil
      assert session.grabbing? == false
      assert session.searching_pid == self()

      assert_receive {:search_session, ^session}
    end

    test "wholesale replaces an existing session", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "First")
      {:ok, %{session: session}} = SearchSession.start_search(name, "Second")

      assert session.query == "Second"
      assert Enum.map(session.groups, & &1.term) == ["Second"]
      assert session.selections == %{}
    end

    test "rejects invalid brace syntax without mutating state", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "ok")
      before = SearchSession.current(name)

      assert {:error, :invalid_syntax} = SearchSession.start_search(name, "Bad {syntax")
      assert SearchSession.current(name) == before
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/acquisition/search_session_test.exs
```

Expected: 3 failures — `start_search/2` is undefined.

- [ ] **Step 3: Extend the struct with `monitor_ref`**

Edit `lib/media_centarr/acquisition/search_session.ex`. Update the type and `defstruct` to add a `monitor_ref` field — needed in the next step so we can demonitor cleanly when a new search replaces the old one:

```elixir
  @type t :: %__MODULE__{
          query: String.t(),
          expansion_preview: :idle | {:ok, pos_integer()} | {:error, atom()},
          groups: [group()],
          selections: %{String.t() => String.t()},
          grab_message: nil | {:ok | :partial | :error, String.t()},
          grabbing?: boolean(),
          searching_pid: nil | pid(),
          monitor_ref: nil | reference()
        }

  defstruct query: "",
            expansion_preview: :idle,
            groups: [],
            selections: %{},
            grab_message: nil,
            grabbing?: false,
            searching_pid: nil,
            monitor_ref: nil
```

The Task 1 empty-session test already uses `assert %SearchSession{...} = session` with explicit fields — `monitor_ref` defaults to `nil` and isn't asserted, so the existing test still passes.

- [ ] **Step 4: Implement `start_search/2`**

Add aliases and `require Log` at the top of the module (above `defstruct`):

```elixir
  alias MediaCentarr.Acquisition.QueryExpander
  alias MediaCentarr.Topics

  require MediaCentarr.Log, as: Log
```

Add the public function after `current/1`:

```elixir
  @doc """
  Starts a new search session, replacing any existing one.

  Returns `{:ok, %{session: session, queries: queries}}` on success — the
  caller spawns Tasks for each `query` and sends results back via
  `record_search_result/3`.

  Returns `{:error, :invalid_syntax}` for malformed brace expansion. The
  existing session is unchanged in that case.

  The caller's pid becomes the monitored `searching_pid`. If the caller
  dies, any group still in `:loading` is swept to `:abandoned`.
  """
  @spec start_search(GenServer.server(), String.t()) ::
          {:ok, %{session: t(), queries: [String.t()]}}
          | {:error, :invalid_syntax}
  def start_search(server \\ __MODULE__, query) when is_binary(query) do
    GenServer.call(server, {:start_search, query, self()})
  end
```

Add the handler:

```elixir
  @impl GenServer
  def handle_call({:start_search, query, caller_pid}, _from, state) do
    trimmed = String.trim(query)

    case QueryExpander.expand(trimmed) do
      {:ok, [_ | _] = queries} ->
        groups =
          Enum.map(queries, fn term ->
            %{term: term, status: :loading, results: [], expanded?: false}
          end)

        new_state =
          %__MODULE__{
            query: query,
            expansion_preview: {:ok, length(queries)},
            groups: groups,
            selections: %{},
            grab_message: nil,
            grabbing?: false,
            searching_pid: caller_pid
          }
          |> swap_monitor(state)

        broadcast(new_state)
        Log.info(:acquisition, "search started — #{length(queries)} queries")
        {:reply, {:ok, %{session: new_state, queries: queries}}, new_state}

      {:ok, []} ->
        {:reply, {:error, :invalid_syntax}, state}

      {:error, _reason} ->
        {:reply, {:error, :invalid_syntax}, state}
    end
  end
```

Add private helpers at the bottom of the module (above the closing `end`):

```elixir
  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp swap_monitor(%__MODULE__{searching_pid: new_pid} = new_state, %__MODULE__{
         monitor_ref: old_ref
       }) do
    if old_ref, do: Process.demonitor(old_ref, [:flush])
    new_ref = if new_pid, do: Process.monitor(new_pid), else: nil
    %{new_state | monitor_ref: new_ref}
  end

  defp broadcast(%__MODULE__{} = session) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.acquisition_search(),
      {:search_session, session}
    )
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/acquisition/search_session_test.exs
```

Expected: 4 tests, 0 failures (the 1 from Task 1 plus 3 new ones).

- [ ] **Step 6: Commit**

```bash
jj desc -m "feat(acquisition): SearchSession.start_search/2 with caller monitoring"
jj new
```

---

## Task 3: `record_search_result/3` — transition loading to ready/failed, idempotent on terminal groups

A per-query Task calls `record_search_result/3` when its Prowlarr request resolves. The function transitions the matching `:loading` group to `:ready` (with sorted results and an auto-added top-seeder default selection) or `{:failed, reason}`. Late-arriving results for groups already in a terminal status (`:abandoned`, `:ready`, `{:failed, _}`) or for unknown terms are silently dropped.

**Files:**
- Modify: `lib/media_centarr/acquisition/search_session.ex`
- Modify: `test/media_centarr/acquisition/search_session_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to the test file. Note these tests construct `%SearchResult{}` literals — check `lib/media_centarr/acquisition/search_result.ex` for the exact field names; the struct already has `guid`, `title`, `quality`, `seeders`, `size_bytes`, `indexer_name`. Adjust the struct literal if any field name differs.

```elixir
  describe "record_search_result/3" do
    alias MediaCentarr.Acquisition.SearchResult

    setup do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_search())
      {:ok, _} = SearchSession.start_search(name, "Show S01E{01-02}")
      assert_receive {:search_session, _}
      {:ok, name: name}
    end

    test "transitions :loading -> :ready and adds top-seeder default selection", %{name: name} do
      result = %SearchResult{
        guid: "guid-1",
        title: "Show S01E01 1080p",
        quality: :hd_1080p,
        seeders: 42,
        size_bytes: 1_000_000,
        indexer_name: "Test"
      }

      :ok = SearchSession.record_search_result(name, "Show S01E01", {:ok, [result]})

      assert_receive {:search_session, session}
      [first_group, second_group] = session.groups
      assert first_group.term == "Show S01E01"
      assert first_group.status == :ready
      assert first_group.results == [result]
      assert second_group.status == :loading
      assert session.selections == %{"Show S01E01" => "guid-1"}
    end

    test "transitions :loading -> {:failed, reason} on error", %{name: name} do
      :ok = SearchSession.record_search_result(name, "Show S01E01", {:error, :timeout})

      assert_receive {:search_session, session}
      group = Enum.find(session.groups, &(&1.term == "Show S01E01"))
      assert group.status == {:failed, :timeout}
      assert group.results == []
    end

    test "is a silent no-op for an unknown term", %{name: name} do
      before = SearchSession.current(name)

      :ok = SearchSession.record_search_result(name, "Different Show", {:ok, []})

      refute_receive {:search_session, _}, 50
      assert SearchSession.current(name) == before
    end

    test "is a silent no-op for a terminal group (e.g. abandoned)", %{name: name} do
      # Force the group into :abandoned by abandoning the whole session.
      # We achieve this in the simplest way available: kill the searching
      # pid (the test process, captured during start_search). But since the
      # test process IS self(), use a child process instead.
      parent = self()

      child =
        spawn(fn ->
          {:ok, _} = SearchSession.start_search(name, "Solo Show")
          send(parent, :ready_to_die)
          receive do
            :die -> :ok
          end
        end)

      assert_receive :ready_to_die
      assert_receive {:search_session, _}
      Process.exit(child, :kill)
      assert_receive {:search_session, swept_session}
      assert Enum.all?(swept_session.groups, fn group -> group.status == :abandoned end)

      # Now send a late-arriving result for the abandoned term.
      :ok =
        SearchSession.record_search_result(
          name,
          "Solo Show",
          {:ok, [%SearchResult{guid: "late", title: "Late", quality: :hd_1080p, seeders: 1}]}
        )

      refute_receive {:search_session, _}, 50
      assert SearchSession.current(name).groups == swept_session.groups
    end
  end
```

The fourth test depends on `:DOWN`-driven sweep behavior implemented in Task 5. **Mark it skipped for this task** with `@tag :skip` above `test "is a silent no-op for a terminal group..."` and remove the skip in Task 5 once the sweep is implemented.

- [ ] **Step 2: Run tests to verify the first three fail**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/acquisition/search_session_test.exs
```

Expected: 3 failures, 1 skipped — `record_search_result/3` is undefined.

- [ ] **Step 3: Implement `record_search_result/3`**

Edit `lib/media_centarr/acquisition/search_session.ex`. Alias `Quality`:

```elixir
  alias MediaCentarr.Acquisition.{QueryExpander, Quality, SearchResult}
```

Add public function:

```elixir
  @doc """
  Records the outcome of a per-query Prowlarr search.

  Idempotent: a result for a term whose group is already in a terminal
  state (`:ready`, `{:failed, _}`, `:abandoned`) is silently dropped, as
  is a result for a term not in the current session. This handles the
  late-arriving Task case where the LiveView crashed and the group was
  swept to `:abandoned` before the Task's HTTP request returned.
  """
  @spec record_search_result(
          GenServer.server(),
          String.t(),
          {:ok, [SearchResult.t()]} | {:error, term()}
        ) :: :ok
  def record_search_result(server \\ __MODULE__, term, outcome) when is_binary(term) do
    GenServer.call(server, {:record_search_result, term, outcome})
  end
```

Add handler:

```elixir
  def handle_call({:record_search_result, term, outcome}, _from, state) do
    case Enum.find_index(state.groups, &(&1.term == term and &1.status == :loading)) do
      nil ->
        {:reply, :ok, state}

      index ->
        new_state = apply_search_result(state, index, outcome)
        broadcast(new_state)
        {:reply, :ok, new_state}
    end
  end
```

Add private helpers (above the `swap_monitor/2` helper):

```elixir
  defp apply_search_result(state, index, {:ok, results}) do
    sorted = sort_results(results)
    group = Enum.at(state.groups, index)
    updated_group = %{group | status: :ready, results: sorted}
    groups = List.replace_at(state.groups, index, updated_group)

    selections =
      case sorted do
        [first | _] -> Map.put_new(state.selections, group.term, first.guid)
        [] -> state.selections
      end

    %{state | groups: groups, selections: selections}
  end

  defp apply_search_result(state, index, {:error, reason}) do
    group = Enum.at(state.groups, index)
    updated_group = %{group | status: {:failed, reason}, results: []}
    groups = List.replace_at(state.groups, index, updated_group)
    %{state | groups: groups}
  end

  defp sort_results(results) do
    Enum.sort_by(results, fn r -> {Quality.rank(r.quality), r.seeders || 0} end, :desc)
  end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/acquisition/search_session_test.exs
```

Expected: 6 tests pass, 1 skipped (the abandonment idempotency test, unblocked in Task 5).

- [ ] **Step 5: Commit**

```bash
jj desc -m "feat(acquisition): SearchSession.record_search_result/3 with idempotency"
jj new
```

---

## Task 4: Simple state mutators — selections, group toggle, query preview, grab feedback, clear

Adds the small write API used by every `handle_event` in the LiveView. None of these touch monitoring; they all just edit fields and broadcast.

**Files:**
- Modify: `lib/media_centarr/acquisition/search_session.ex`
- Modify: `test/media_centarr/acquisition/search_session_test.exs`

- [ ] **Step 1: Write the failing tests**

Append:

```elixir
  describe "simple mutators" do
    setup do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_search())
      {:ok, name: name}
    end

    test "set_selection/3 puts and replaces; clear_selection/2 removes", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}

      :ok = SearchSession.set_selection(name, "Show", "guid-1")
      assert_receive {:search_session, %{selections: %{"Show" => "guid-1"}}}

      :ok = SearchSession.set_selection(name, "Show", "guid-2")
      assert_receive {:search_session, %{selections: %{"Show" => "guid-2"}}}

      :ok = SearchSession.clear_selection(name, "Show")
      assert_receive {:search_session, %{selections: selections}}
      assert selections == %{}
    end

    test "clear_selections/1 wipes the map", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}
      :ok = SearchSession.set_selection(name, "Show", "guid-1")
      assert_receive {:search_session, _}

      :ok = SearchSession.clear_selections(name)

      assert_receive {:search_session, %{selections: %{}}}
    end

    test "toggle_group/2 flips expanded? on the matching group only", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}

      :ok = SearchSession.toggle_group(name, "Show")
      assert_receive {:search_session, session}
      assert hd(session.groups).expanded? == true

      :ok = SearchSession.toggle_group(name, "Show")
      assert_receive {:search_session, session}
      assert hd(session.groups).expanded? == false
    end

    test "set_query_preview/2 updates query and expansion_preview without touching groups", %{name: name} do
      :ok = SearchSession.set_query_preview(name, "Show {01-03}")

      assert_receive {:search_session, session}
      assert session.query == "Show {01-03}"
      assert session.expansion_preview == {:ok, 3}
      assert session.groups == []
    end

    test "set_query_preview/2 reports invalid syntax", %{name: name} do
      :ok = SearchSession.set_query_preview(name, "Show {")
      assert_receive {:search_session, %{expansion_preview: {:error, :invalid_syntax}}}
    end

    test "set_query_preview/2 with blank input -> :idle", %{name: name} do
      :ok = SearchSession.set_query_preview(name, "")
      assert_receive {:search_session, %{expansion_preview: :idle, query: ""}}
    end

    test "set_grabbing/2 + set_grab_message/2 round-trip", %{name: name} do
      :ok = SearchSession.set_grabbing(name, true)
      assert_receive {:search_session, %{grabbing?: true}}

      :ok = SearchSession.set_grab_message(name, {:ok, "1 grab(s) submitted"})
      assert_receive {:search_session, %{grab_message: {:ok, "1 grab(s) submitted"}}}

      :ok = SearchSession.set_grabbing(name, false)
      assert_receive {:search_session, %{grabbing?: false, grab_message: {:ok, _}}}
    end

    test "clear/1 resets to default state", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "Show")
      assert_receive {:search_session, _}

      :ok = SearchSession.clear(name)
      assert_receive {:search_session, session}
      assert session == %SearchSession{}
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/acquisition/search_session_test.exs
```

Expected: 8 new failures — the new functions are undefined.

- [ ] **Step 3: Implement the mutators**

Edit `lib/media_centarr/acquisition/search_session.ex`. Add these public functions after `record_search_result/3`:

```elixir
  @doc "Sets `term => guid` in the selections map."
  @spec set_selection(GenServer.server(), String.t(), String.t()) :: :ok
  def set_selection(server \\ __MODULE__, term, guid)
      when is_binary(term) and is_binary(guid) do
    GenServer.call(server, {:set_selection, term, guid})
  end

  @doc "Removes `term` from the selections map."
  @spec clear_selection(GenServer.server(), String.t()) :: :ok
  def clear_selection(server \\ __MODULE__, term) when is_binary(term) do
    GenServer.call(server, {:clear_selection, term})
  end

  @doc "Empties the selections map."
  @spec clear_selections(GenServer.server()) :: :ok
  def clear_selections(server \\ __MODULE__) do
    GenServer.call(server, :clear_selections)
  end

  @doc "Flips `expanded?` on the group whose term matches; no-op for unknown terms."
  @spec toggle_group(GenServer.server(), String.t()) :: :ok
  def toggle_group(server \\ __MODULE__, term) when is_binary(term) do
    GenServer.call(server, {:toggle_group, term})
  end

  @doc """
  Updates `query` and `expansion_preview` from a live input value, without
  touching any other field. Used by the LiveView's `phx-change` handler so
  the user sees the brace-expanded count update as they type.
  """
  @spec set_query_preview(GenServer.server(), String.t()) :: :ok
  def set_query_preview(server \\ __MODULE__, query) when is_binary(query) do
    GenServer.call(server, {:set_query_preview, query})
  end

  @doc "Sets the boolean `grabbing?` flag."
  @spec set_grabbing(GenServer.server(), boolean()) :: :ok
  def set_grabbing(server \\ __MODULE__, value) when is_boolean(value) do
    GenServer.call(server, {:set_grabbing, value})
  end

  @doc "Sets the last-grab outcome message."
  @spec set_grab_message(
          GenServer.server(),
          {:ok | :partial | :error, String.t()}
        ) :: :ok
  def set_grab_message(server \\ __MODULE__, message) do
    GenServer.call(server, {:set_grab_message, message})
  end

  @doc "Resets the entire session to the default empty state."
  @spec clear(GenServer.server()) :: :ok
  def clear(server \\ __MODULE__) do
    GenServer.call(server, :clear)
  end
```

Add the handlers (alongside the existing `handle_call` clauses):

```elixir
  def handle_call({:set_selection, term, guid}, _from, state) do
    new_state = %{state | selections: Map.put(state.selections, term, guid)}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:clear_selection, term}, _from, state) do
    new_state = %{state | selections: Map.delete(state.selections, term)}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:clear_selections, _from, state) do
    new_state = %{state | selections: %{}}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:toggle_group, term}, _from, state) do
    groups =
      Enum.map(state.groups, fn
        %{term: ^term} = group -> %{group | expanded?: not group.expanded?}
        group -> group
      end)

    new_state = %{state | groups: groups}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:set_query_preview, query}, _from, state) do
    preview =
      case String.trim(query) do
        "" ->
          :idle

        trimmed ->
          case QueryExpander.expand(trimmed) do
            {:ok, queries} -> {:ok, length(queries)}
            {:error, _reason} -> {:error, :invalid_syntax}
          end
      end

    new_state = %{state | query: query, expansion_preview: preview}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:set_grabbing, value}, _from, state) do
    new_state = %{state | grabbing?: value}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:set_grab_message, message}, _from, state) do
    new_state = %{state | grab_message: message}
    broadcast(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:clear, _from, state) do
    # Demonitor any active searching pid.
    new_state = swap_monitor(%__MODULE__{}, state)
    broadcast(new_state)
    {:reply, :ok, new_state}
  end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/acquisition/search_session_test.exs
```

Expected: 14 tests, 0 failures, 1 skipped.

- [ ] **Step 5: Commit**

```bash
jj desc -m "feat(acquisition): SearchSession state mutators"
jj new
```

---

## Task 5: Monitor → abandonment + retry — `:DOWN` sweep + `retry_search_terms/2`

The GenServer monitors the LiveView pid that called `start_search/2`. On `:DOWN`, it sweeps every `:loading` group to `:abandoned`, clears the searching pid + monitor ref, and broadcasts. `retry_search_terms/2` transitions named `:abandoned`/`{:failed, _}` groups back to `:loading` and re-monitors the new caller.

**Files:**
- Modify: `lib/media_centarr/acquisition/search_session.ex`
- Modify: `test/media_centarr/acquisition/search_session_test.exs`

- [ ] **Step 1: Write the failing tests**

Append:

```elixir
  describe "monitor + abandonment" do
    setup do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_search())
      {:ok, name: name}
    end

    test "kills sweep :loading -> :abandoned and clear searching_pid", %{name: name} do
      parent = self()

      child =
        spawn(fn ->
          {:ok, _} = SearchSession.start_search(name, "Show {01-03}")
          send(parent, :ready)
          receive do
            :die -> :ok
          end
        end)

      assert_receive :ready
      assert_receive {:search_session, before_session}
      assert before_session.searching_pid == child
      assert Enum.all?(before_session.groups, fn group -> group.status == :loading end)

      Process.exit(child, :kill)

      assert_receive {:search_session, after_session}, 500
      assert Enum.all?(after_session.groups, fn group -> group.status == :abandoned end)
      assert after_session.searching_pid == nil
      assert after_session.monitor_ref == nil
    end

    test ":ready groups are not swept on :DOWN", %{name: name} do
      alias MediaCentarr.Acquisition.SearchResult
      parent = self()

      child =
        spawn(fn ->
          {:ok, _} = SearchSession.start_search(name, "A,B")
          send(parent, :started)
          receive do
            :die -> :ok
          end
        end)

      assert_receive :started
      assert_receive {:search_session, _}

      :ok =
        SearchSession.record_search_result(name, "A", {:ok, [
          %SearchResult{guid: "g", title: "T", quality: :hd_1080p, seeders: 1}
        ]})

      assert_receive {:search_session, _}

      Process.exit(child, :kill)

      assert_receive {:search_session, swept}, 500
      assert Enum.find(swept.groups, &(&1.term == "A")).status == :ready
      assert Enum.find(swept.groups, &(&1.term == "B")).status == :abandoned
    end
  end

  describe "retry_search_terms/2" do
    setup do
      name = :"sess_#{System.unique_integer([:positive])}"
      start_supervised!({SearchSession, name: name})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_search())
      {:ok, name: name}
    end

    test "transitions named :abandoned and {:failed, _} groups to :loading and re-monitors", %{
      name: name
    } do
      parent = self()

      child =
        spawn(fn ->
          {:ok, _} = SearchSession.start_search(name, "A,B,C")
          send(parent, :started)
          receive do
            :die -> :ok
          end
        end)

      assert_receive :started
      assert_receive {:search_session, _}

      :ok = SearchSession.record_search_result(name, "B", {:error, :timeout})
      assert_receive {:search_session, _}

      Process.exit(child, :kill)
      assert_receive {:search_session, swept}, 500
      # A, C are :abandoned; B is {:failed, :timeout}.
      assert Enum.find(swept.groups, &(&1.term == "A")).status == :abandoned
      assert Enum.find(swept.groups, &(&1.term == "B")).status == {:failed, :timeout}
      assert Enum.find(swept.groups, &(&1.term == "C")).status == :abandoned

      :ok = SearchSession.retry_search_terms(name, ["A", "B"])
      assert_receive {:search_session, after_retry}, 500

      assert Enum.find(after_retry.groups, &(&1.term == "A")).status == :loading
      assert Enum.find(after_retry.groups, &(&1.term == "B")).status == :loading
      assert Enum.find(after_retry.groups, &(&1.term == "C")).status == :abandoned
      assert after_retry.searching_pid == self()
      assert after_retry.monitor_ref != nil
    end

    test "no-op for terms that aren't :abandoned or {:failed, _}", %{name: name} do
      {:ok, _} = SearchSession.start_search(name, "X")
      assert_receive {:search_session, _}

      :ok = SearchSession.retry_search_terms(name, ["X"])

      assert_receive {:search_session, session}
      assert hd(session.groups).status == :loading
    end
  end
```

Also remove the `@tag :skip` from the abandonment idempotency test in Task 3.

- [ ] **Step 2: Run tests to verify they fail**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/acquisition/search_session_test.exs
```

Expected: 4 failures (the 3 new tests plus the unskipped Task 3 test) — `:DOWN` is unhandled and `retry_search_terms/2` is undefined.

- [ ] **Step 3: Implement the `:DOWN` handler**

Edit `lib/media_centarr/acquisition/search_session.ex`. Add a `handle_info` for `:DOWN`:

```elixir
  @impl GenServer
  def handle_info(
        {:DOWN, ref, :process, pid, _reason},
        %__MODULE__{monitor_ref: ref, searching_pid: pid} = state
      ) do
    {abandoned_count, groups} =
      Enum.map_reduce(state.groups, 0, fn
        %{status: :loading} = group, acc -> {%{group | status: :abandoned}, acc + 1}
        group, acc -> {group, acc}
      end)
      |> reverse_count()

    new_state = %{state | groups: groups, searching_pid: nil, monitor_ref: nil}

    if abandoned_count > 0 do
      Log.info(
        :acquisition,
        "search abandoned — #{abandoned_count} group(s), query=#{inspect(state.query)}"
      )
    end

    broadcast(new_state)
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  defp reverse_count({groups, count}), do: {count, groups}
```

Wait — `Enum.map_reduce/3` returns `{mapped_list, acc}`, not `{acc, mapped_list}`. Drop the `reverse_count/1` helper and unpack directly:

```elixir
  def handle_info(
        {:DOWN, ref, :process, pid, _reason},
        %__MODULE__{monitor_ref: ref, searching_pid: pid} = state
      ) do
    {groups, abandoned_count} =
      Enum.map_reduce(state.groups, 0, fn
        %{status: :loading} = group, acc -> {%{group | status: :abandoned}, acc + 1}
        group, acc -> {group, acc}
      end)

    new_state = %{state | groups: groups, searching_pid: nil, monitor_ref: nil}

    if abandoned_count > 0 do
      Log.info(
        :acquisition,
        "search abandoned — #{abandoned_count} group(s), query=#{inspect(state.query)}"
      )
    end

    broadcast(new_state)
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end
```

- [ ] **Step 4: Implement `retry_search_terms/2`**

Add the public function:

```elixir
  @doc """
  Re-arms named groups: any term currently in `:abandoned` or `{:failed, _}`
  flips back to `:loading`. Other states are no-ops for that term. The
  caller's pid becomes the new monitored `searching_pid`.

  The caller is responsible for spawning Tasks for these terms after the
  call returns.
  """
  @spec retry_search_terms(GenServer.server(), [String.t()]) :: :ok
  def retry_search_terms(server \\ __MODULE__, terms) when is_list(terms) do
    GenServer.call(server, {:retry_search_terms, terms, self()})
  end
```

Add the handler:

```elixir
  def handle_call({:retry_search_terms, terms, caller_pid}, _from, state) do
    terms_set = MapSet.new(terms)

    groups =
      Enum.map(state.groups, fn
        %{term: term, status: :abandoned} = group ->
          if MapSet.member?(terms_set, term),
            do: %{group | status: :loading, results: []},
            else: group

        %{term: term, status: {:failed, _}} = group ->
          if MapSet.member?(terms_set, term),
            do: %{group | status: :loading, results: []},
            else: group

        group ->
          group
      end)

    new_state =
      %{state | groups: groups, searching_pid: caller_pid}
      |> swap_monitor(state)

    broadcast(new_state)
    {:reply, :ok, new_state}
  end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/acquisition/search_session_test.exs
```

Expected: all SearchSession tests pass (16 or so, no skips).

- [ ] **Step 6: Commit**

```bash
jj desc -m "feat(acquisition): SearchSession :DOWN sweep + retry_search_terms"
jj new
```

---

## Task 6: Acquisition facade — public functions delegating to SearchSession

Adds the public API on `MediaCentarr.Acquisition` that the LiveView calls. These are thin wrappers; nothing else changes about the existing facade.

**Files:**
- Modify: `lib/media_centarr/acquisition/acquisition.ex`

- [ ] **Step 1: Add the facade functions**

Edit `lib/media_centarr/acquisition/acquisition.ex`. Find the existing `subscribe_queue/0` function (line ~101) and add directly below it:

```elixir
  @doc """
  Subscribes the calling process to search session updates. Receivers get
  `{:search_session, %SearchSession{}}` on every state change.
  """
  @spec subscribe_search() :: :ok
  def subscribe_search do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_search())
  end

  @doc "Returns the current search session struct (always present; may be empty)."
  @spec current_search_session() :: MediaCentarr.Acquisition.SearchSession.t()
  defdelegate current_search_session,
    to: MediaCentarr.Acquisition.SearchSession,
    as: :current

  @doc """
  Starts a new search session, replacing any existing one. Returns
  `{:ok, %{session: ..., queries: [...]}}` so the caller (the LiveView)
  can spawn Tasks for each expanded query.
  """
  @spec start_search(String.t()) ::
          {:ok, %{session: MediaCentarr.Acquisition.SearchSession.t(), queries: [String.t()]}}
          | {:error, :invalid_syntax}
  defdelegate start_search(query), to: MediaCentarr.Acquisition.SearchSession

  @doc "Records a per-query Prowlarr result against the current session."
  @spec record_search_result(
          String.t(),
          {:ok, [SearchResult.t()]} | {:error, term()}
        ) :: :ok
  defdelegate record_search_result(term, outcome),
    to: MediaCentarr.Acquisition.SearchSession

  @doc "Updates the query input box value and recomputes the expansion preview."
  @spec set_query_preview(String.t()) :: :ok
  defdelegate set_query_preview(query), to: MediaCentarr.Acquisition.SearchSession

  @doc "Sets `term => guid` in the session selections map."
  @spec set_selection(String.t(), String.t()) :: :ok
  defdelegate set_selection(term, guid), to: MediaCentarr.Acquisition.SearchSession

  @doc "Removes `term` from the session selections map."
  @spec clear_selection(String.t()) :: :ok
  defdelegate clear_selection(term), to: MediaCentarr.Acquisition.SearchSession

  @doc "Empties the session selections map."
  @spec clear_selections() :: :ok
  defdelegate clear_selections(), to: MediaCentarr.Acquisition.SearchSession

  @doc "Toggles `expanded?` on the named group."
  @spec toggle_group(String.t()) :: :ok
  defdelegate toggle_group(term), to: MediaCentarr.Acquisition.SearchSession

  @doc "Sets the boolean `grabbing?` flag on the session."
  @spec set_grabbing(boolean()) :: :ok
  defdelegate set_grabbing(value), to: MediaCentarr.Acquisition.SearchSession

  @doc "Sets the last-grab outcome message on the session."
  @spec set_grab_message({:ok | :partial | :error, String.t()}) :: :ok
  defdelegate set_grab_message(message), to: MediaCentarr.Acquisition.SearchSession

  @doc "Resets the entire search session to the default empty state."
  @spec clear_search_session() :: :ok
  defdelegate clear_search_session(), to: MediaCentarr.Acquisition.SearchSession, as: :clear

  @doc """
  Re-arms named groups (`:abandoned` / `{:failed, _}` -> `:loading`). The
  caller's pid becomes the monitored `searching_pid`. The caller is
  responsible for spawning Tasks for these terms.
  """
  @spec retry_search_terms([String.t()]) :: :ok
  defdelegate retry_search_terms(terms), to: MediaCentarr.Acquisition.SearchSession
```

- [ ] **Step 2: Verify the compile is clean**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix compile --warnings-as-errors
```

Expected: clean compile. Boundary check passes — `SearchSession` is referenced from within the same context.

- [ ] **Step 3: Run the existing acquisition + search_session tests**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr/acquisition/
```

Expected: all green.

- [ ] **Step 4: Commit**

```bash
jj desc -m "feat(acquisition): expose SearchSession through Acquisition facade"
jj new
```

---

## Task 7: AcquisitionLive tests — extend with cross-navigation persistence assertions (test-first)

Before refactoring the LiveView, write the tests that prove the new behavior. They should fail against the current implementation (search state lost on navigation), pass after Task 8.

**Files:**
- Modify: `test/media_centarr_web/live/acquisition_live_test.exs`

- [ ] **Step 1: Stub Prowlarr search responses**

Add helpers at the top of the test module (after `alias` lines). The fixture matches `MediaCentarr.Acquisition.SearchResult.from_prowlarr/1` (in `lib/media_centarr/acquisition/search_result.ex`) — keys: `"title"`, `"guid"`, `"indexerId"`, `"size"`, `"seeders"`, `"leechers"`, `"indexer"`, `"publishDate"`:

```elixir
  defp stub_prowlarr_with(results) do
    Req.Test.stub(:prowlarr, fn conn ->
      Req.Test.json(conn, results)
    end)
  end

  defp sample_release(opts \\ []) do
    %{
      "guid" => Keyword.get(opts, :guid, "guid-1"),
      "title" => Keyword.get(opts, :title, "Sample.Show.S01E01.1080p.WEB-DL.mkv"),
      "indexerId" => 1,
      "size" => 1_073_741_824,
      "seeders" => 42,
      "leechers" => 0,
      "indexer" => "Test Indexer",
      "publishDate" => "2026-04-01T00:00:00Z"
    }
  end
```

- [ ] **Step 2: Add the persistence tests**

Append to `test/media_centarr_web/live/acquisition_live_test.exs`. Place the new `describe` block after the existing ones:

```elixir
  describe "search session persistence" do
    setup do
      # Reset the singleton SearchSession between tests so the slot is empty
      # at start. Each test starts the BEAM-wide singleton GenServer.
      MediaCentarr.Acquisition.clear_search_session()
      :ok
    end

    test "search query and results persist across navigation", %{conn: conn} do
      stub_prowlarr_with([sample_release()])

      {:ok, view, _html} = live(conn, "/download")

      view
      |> form("form", %{"query" => "Sample Show"})
      |> render_submit()

      # Wait for the async task to complete and the session to broadcast.
      _ = render(view)
      :timer.sleep(100)
      html = render(view)
      assert html =~ "Sample Show"
      assert html =~ "Sample.Show.S01E01"

      # Navigate away.
      {:ok, _other_view, _other_html} = live(conn, "/")

      # Navigate back.
      {:ok, _view2, html2} = live(conn, "/download")

      assert html2 =~ "Sample Show"
      assert html2 =~ "Sample.Show.S01E01"
    end

    test "selection persists across navigation", %{conn: conn} do
      stub_prowlarr_with([sample_release()])

      {:ok, view, _html} = live(conn, "/download")

      view
      |> form("form", %{"query" => "Sample Show"})
      |> render_submit()

      :timer.sleep(100)

      view
      |> element("button[phx-click='select_result'][phx-value-guid='guid-1']")
      |> render_click()

      session_before = MediaCentarr.Acquisition.current_search_session()
      assert session_before.selections == %{"Sample Show" => "guid-1"}

      # Navigate away and back.
      {:ok, _other_view, _other_html} = live(conn, "/")
      {:ok, _view2, _html2} = live(conn, "/download")

      session_after = MediaCentarr.Acquisition.current_search_session()
      assert session_after.selections == %{"Sample Show" => "guid-1"}
    end

    test "groups in :loading become :abandoned with retry affordance after LV crash", %{conn: conn} do
      # Stub Prowlarr to never reply within the test window.
      Req.Test.stub(:prowlarr, fn _conn ->
        :timer.sleep(:infinity)
      end)

      {:ok, view, _html} = live(conn, "/download")

      view
      |> form("form", %{"query" => "Pending Show"})
      |> render_submit()

      :timer.sleep(50)
      session_before = MediaCentarr.Acquisition.current_search_session()
      assert Enum.all?(session_before.groups, fn group -> group.status == :loading end)

      # Simulate LV death by stopping the LV process.
      GenServer.stop(view.pid, :normal)

      # Allow :DOWN message processing.
      :timer.sleep(100)

      session_after = MediaCentarr.Acquisition.current_search_session()
      assert Enum.all?(session_after.groups, fn group -> group.status == :abandoned end)

      # Mount fresh, render, expect a Retry control to be visible.
      {:ok, _view2, html2} = live(conn, "/download")
      assert html2 =~ "Retry"
    end
  end
```

The third test stubs Prowlarr to hang, then kills the LV — the Task that was started lives under `MediaCentarr.TaskSupervisor` and is unlinked from the LV, so it'll keep running until the test process exits. That's fine since `record_search_result/3` is idempotent.

- [ ] **Step 3: Run the new tests to verify they fail**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr_web/live/acquisition_live_test.exs --only describe:"search session persistence"
```

(If `--only describe:` doesn't filter as expected for ExUnit, just run the whole file; the new tests should be the failing ones.)

Expected: 3 failures — the LiveView still uses local assigns, so navigating away wipes everything.

- [ ] **Step 4: Commit failing tests**

```bash
jj desc -m "test(acquisition): expect search state to survive LV navigation"
jj new
```

---

## Task 8: AcquisitionLive — refactor to read from / write through the facade

This is the largest task. Rewrite `mount/3`, `handle_params/3`, every search-related `handle_event/3`, the search-related `handle_info/2`, and update the render template to read from `@search_session.<field>` instead of individual assigns.

**Files:**
- Modify: `lib/media_centarr_web/live/acquisition_live.ex`
- Modify: `lib/media_centarr_web/live/acquisition_live/logic.ex` (slim down)

- [ ] **Step 1: Rewrite `mount/3`**

In `lib/media_centarr_web/live/acquisition_live.ex`, replace the existing `mount/3` body. The new mount subscribes to both topics, reads the current session, and assigns it whole:

```elixir
  @impl true
  def mount(_params, _session, socket) do
    if Capabilities.prowlarr_ready?() do
      if connected?(socket) do
        Acquisition.subscribe()
        Acquisition.subscribe_search()
        Capabilities.subscribe()
        Process.send_after(self(), :poll_queue, 0)
      end

      {:ok,
       assign(socket,
         search_session: Acquisition.current_search_session(),
         active_queue: [],
         queue_loaded?: false,
         cancel_confirm: nil,
         download_client_ready: Capabilities.download_client_ready?(),
         activity_filter: :active,
         activity_search: "",
         reload_timer: nil
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end
```

Note the removed assigns: `query`, `expansion_preview`, `searching?`, `groups`, `selections`, `grabbing?`, `grab_message`. They now live on `@search_session`.

- [ ] **Step 2: Rewrite `handle_params/3`**

Replace `maybe_trigger_prowlarr_search/2` with a version that calls the facade:

```elixir
  defp maybe_trigger_prowlarr_search(socket, query) when is_binary(query) do
    case String.trim(query) do
      "" ->
        socket

      trimmed ->
        case Acquisition.start_search(trimmed) do
          {:ok, %{queries: queries}} ->
            Enum.each(queries, fn q -> send(self(), {:run_search_one, q}) end)
            socket

          {:error, _} ->
            socket
        end
    end
  end

  defp maybe_trigger_prowlarr_search(socket, _), do: socket
```

The `handle_params/3` body itself drops the `activity_search`/`activity_filter` parsing only if you collapse them — keep them as is. The new version:

```elixir
  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(
        activity_search: Map.get(params, "search", ""),
        activity_filter: parse_activity_filter(params)
      )
      |> load_activity()
      |> maybe_trigger_prowlarr_search(Map.get(params, "prowlarr_search"))

    {:noreply, socket}
  end
```

(unchanged from current shape).

- [ ] **Step 3: Rewrite the search `handle_event/3` clauses**

Replace:

```elixir
  @impl true
  def handle_event("query_change", %{"query" => query}, socket) do
    Acquisition.set_query_preview(query)
    {:noreply, socket}
  end

  def handle_event("submit_search", _params, socket) do
    if socket.assigns.search_session.grabbing? do
      {:noreply, socket}
    else
      do_submit_search(socket)
    end
  end

  defp do_submit_search(socket) do
    query = socket.assigns.search_session.query

    case Acquisition.start_search(query) do
      {:ok, %{queries: queries}} ->
        Enum.each(queries, fn q -> send(self(), {:run_search_one, q}) end)
        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("retry_search", %{"term" => term}, socket) do
    retry_terms(socket, [term])
    {:noreply, socket}
  end

  def handle_event("retry_all_timeouts", _params, socket) do
    retry_terms(socket, Logic.timeout_terms(socket.assigns.search_session.groups))
    {:noreply, socket}
  end

  def handle_event("toggle_group", %{"term" => term}, socket) do
    Acquisition.toggle_group(term)
    {:noreply, socket}
  end

  def handle_event("select_result", %{"term" => term, "guid" => guid}, socket) do
    case Map.get(socket.assigns.search_session.selections, term) do
      ^guid -> Acquisition.clear_selection(term)
      _ -> Acquisition.set_selection(term, guid)
    end

    {:noreply, socket}
  end
```

(Old `submit_search` accepted the form's `%{"query" => query}` param. The new flow stores the query in the session via the `phx-change` handler, so `submit_search` reads from the session. If `phx-debounce="200"` is in place, there can be a small race — verify the form-submit path still works in the test by checking that the query field on the session matches what the user typed.)

If keeping form-submit as the source of truth is preferred (avoiding the race), accept both:

```elixir
  def handle_event("submit_search", %{"query" => query}, socket) do
    if socket.assigns.search_session.grabbing? do
      {:noreply, socket}
    else
      Acquisition.set_query_preview(query)

      case Acquisition.start_search(query) do
        {:ok, %{queries: queries}} ->
          Enum.each(queries, fn q -> send(self(), {:run_search_one, q}) end)
          {:noreply, socket}

        {:error, _} ->
          {:noreply, socket}
      end
    end
  end
```

The `set_query_preview` ensures the session's `query` field matches the submitted query before `start_search` (which also sets it).

Replace `retry_terms/2` with a thin wrapper:

```elixir
  defp retry_terms(_socket, []), do: :ok

  defp retry_terms(_socket, terms) do
    Acquisition.retry_search_terms(terms)
    Enum.each(terms, fn term -> send(self(), {:run_search_one, term}) end)
    :ok
  end
```

Replace `grab_selected`:

```elixir
  def handle_event("grab_selected", _params, socket) do
    selections = socket.assigns.search_session.selections

    if map_size(selections) == 0 do
      {:noreply, socket}
    else
      results =
        selections
        |> Map.values()
        |> Enum.map(&Logic.find_result(socket.assigns.search_session.groups, &1))
        |> Enum.reject(&is_nil/1)

      Acquisition.set_grabbing(true)
      send(self(), {:run_grabs, results})
      {:noreply, socket}
    end
  end
```

The activity-zone events (`set_activity_filter`, `set_activity_search`, `cancel_activity_grab`, `rearm_activity_grab`) and the cancel-download events (`cancel_download_prompt`, etc.) are unchanged.

- [ ] **Step 4: Rewrite the search `handle_info/2` clauses**

Replace `{:run_search_one, query}`:

```elixir
  def handle_info({:run_search_one, query}, socket) do
    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      outcome =
        try do
          Acquisition.search(query)
        catch
          kind, reason -> {:error, {kind, reason}}
        end

      Acquisition.record_search_result(query, outcome)
    end)

    {:noreply, socket}
  end
```

**Delete** the entire `{:search_result, ...}` handler — its job is now done by the `{:search_session, _}` broadcast.

Add:

```elixir
  def handle_info({:search_session, session}, socket) do
    {:noreply, assign(socket, search_session: session)}
  end
```

Replace `{:run_grabs, results}`:

```elixir
  def handle_info({:run_grabs, results}, socket) do
    query = socket.assigns.search_session.query
    pairs = Enum.map(results, fn result -> {result, Acquisition.grab(result, query)} end)

    Enum.each(pairs, fn
      {result, {:error, reason}} ->
        Log.warning(:acquisition, "grab failed — #{result.title} — #{inspect(reason)}")

      _ ->
        :ok
    end)

    ok_count = Enum.count(pairs, fn {_, outcome} -> match?({:ok, _}, outcome) end)
    err_count = length(pairs) - ok_count
    Log.info(:acquisition, "grab batch complete — #{ok_count} ok, #{err_count} failed")

    Acquisition.set_grab_message(Logic.build_grab_message(pairs))
    Acquisition.clear_selections()
    Acquisition.set_grabbing(false)

    {:noreply, socket}
  end
```

(The session broadcasts triggered by these three facade calls drive the UI update — no `assign` needed here.)

The other `handle_info` clauses (`:capabilities_changed`, `:poll_queue`, `:reload_activity`, the activity-zone PubSub events, the catch-all) are unchanged.

- [ ] **Step 5: Update the render template**

Throughout the `~H""` block in `render/1`, replace every reference to a former assign with the corresponding session field. Specifically:

- `@query` → `@search_session.query`
- `@expansion_preview` → `@search_session.expansion_preview`
- `@searching?` → `Logic.any_loading?(@search_session.groups)` (new helper, see Step 6)
- `@groups` → `@search_session.groups`
- `@selections` → `@search_session.selections`
- `@grabbing?` → `@search_session.grabbing?`
- `@grab_message` → `@search_session.grab_message`

Use Edit's `replace_all: true` on the file for each rename if no other matches exist for those tokens. Otherwise do them one at a time in context.

- [ ] **Step 6: Add `Logic.any_loading?/1` and remove now-unused functions**

In `lib/media_centarr_web/live/acquisition_live/logic.ex`:

Add (the inverse of the existing `all_loaded?/1`):

```elixir
  @doc "True when any group is still in `:loading`."
  @spec any_loading?([group()]) :: boolean()
  def any_loading?(groups), do: not all_loaded?(groups)
```

Remove (these moved to `SearchSession`):
- `expansion_preview/1`
- `build_groups/1`
- `placeholder_groups/1`
- `apply_search_result/3`
- `mark_group_loading/2`
- `add_default_selection/2`
- `default_selections/1`
- `toggle_group/2`

Keep (still used by the LV template):
- `all_loaded?/1` — used by `any_loading?/1`
- `timeout_terms/1`
- `find_result/2`
- `featured_result/2`
- `format_grab_reason/1`
- `format_search_error/1`
- `build_grab_message/1`
- `state_label/1`, `state_badge_class/1`, `group_downloads_by_state/1`

Update the type alias since `:abandoned` is now valid:

```elixir
  @type status :: :loading | :ready | {:failed, term()} | :abandoned
```

- [ ] **Step 7: Run the LiveView tests**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test test/media_centarr_web/live/acquisition_live_test.exs
```

Expected: all green, including the persistence tests added in Task 7.

- [ ] **Step 8: Run the full test suite**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix test
```

Expected: all green.

- [ ] **Step 9: Commit**

```bash
jj desc -m "refactor(acquisition_live): read/write search state through facade"
jj new
```

---

## Task 9: Update `Logic` tests + run `mix precommit`

Drop tests for the functions removed in Task 8 Step 6, and run the project's full precommit gate.

**Files:**
- Modify: `test/media_centarr_web/live/acquisition_live/logic_test.exs` (if it exists — verify)

- [ ] **Step 1: Find and delete tests for removed functions**

```bash
grep -rn -E "expansion_preview|build_groups|placeholder_groups|apply_search_result|mark_group_loading|add_default_selection|default_selections|toggle_group" test/media_centarr_web/live/acquisition_live/
```

Open each match and delete tests targeting the removed functions. Functions still exported from `Logic` (per Task 8 Step 6's "Keep" list) keep their tests.

If equivalent coverage exists in `test/media_centarr/acquisition/search_session_test.exs` (which it does, given Tasks 2–5), no test loss is regressive — we moved the logic and the tests. If a deleted test had assertions not covered in the SearchSession suite, port them over.

- [ ] **Step 2: Run `mix precommit`**

```bash
MIX_OS_DEPS_COMPILE_PARTITION_COUNT=8 mix precommit
```

This runs `compile --warnings-as-errors`, `format` (with Quokka), `credo --strict`, the JS boundaries check, `deps.audit`, `sobelow`, and the test suite.

Expected: all green. If `credo --strict` flags anything in the new code, fix it (the project's house Credo rules are listed in `CLAUDE.md` — most relevant here: `PredicateNaming` for boolean function names ending in `?`, `NoAbbreviatedNames` for parameter names).

- [ ] **Step 3: Commit**

```bash
jj desc -m "test(acquisition_live): drop tests for logic moved into SearchSession"
jj new
```

If Step 1 found nothing to delete (no `Logic` test file or no relevant tests), skip the commit and proceed.

---

## Task 10: Manual verification in dev

Confirm the user-visible behavior matches the spec.

- [ ] **Step 1: Start dev IEx if not running**

If a dev session is already running under `iex --name repl@127.0.0.1 --remsh media_centarr_dev@127.0.0.1`, attach. Otherwise start fresh: `iex -S mix phx.server`. (Note: per project convention, the dev server is run as a manual IEx session, not the systemd dev unit; recompile via `recompile` inside IEx after the changes land.)

- [ ] **Step 2: Open the dev browser**

```bash
scripts/media-dev
```

Or navigate Chrome to `http://127.0.0.1:1080/download`.

- [ ] **Step 3: Walk the durability paths**

1. Configure Prowlarr if not already done, navigate to `/download`.
2. Type a query with brace expansion (e.g. `Sample Show S01E{01-03}`). Submit. Verify three groups appear, results stream in.
3. Click into a result to select it. Verify it highlights.
4. Navigate to `/` (library). Wait a moment.
5. Navigate back to `/download`. Verify the query is still in the input, results are still visible, the selection is still highlighted.
6. Refresh the browser. Verify all of the above survives the refresh.
7. Submit a new query that takes a moment (e.g. an obscure title). Immediately navigate to `/`. Wait until the search would have completed. Navigate back. Verify the prior query state is gone (replaced) and the new query shows results — or shows `:abandoned` groups with Retry buttons if the LV outlived the search.

- [ ] **Step 4: If anything diverges from the spec, file a follow-up task**

Don't fix verification gaps in this PR — note them so they can be addressed cleanly. Then proceed to ship.

---

## Self-Review Notes

Spec coverage check:
- §1 Session struct → Task 1 (skeleton), refined in Task 2 (adds `monitor_ref`).
- §2 GenServer → Tasks 1, 2, 3, 4, 5.
- §3 Facade API → Task 6.
- §4 LiveView refactor → Tasks 7 (tests), 8 (impl).
- §5 Lifecycle (monitor + abandonment + retry) → Task 5.
- Testing requirements → Tasks 1–5 (SearchSession tests), Tasks 7, 9 (LiveView tests).
- Migration / no-DB / new module / supervision wiring → Task 1.

No placeholders. No "TBD" or "implement later". Every code step shows actual code.

Type consistency:
- `SearchSession.t()` shape consistent across Tasks 1, 2, 3, 4, 5.
- `monitor_ref` introduced in Task 2 Step 3 and consistently used in Tasks 4, 5.
- `record_search_result/3` arity matches across Tasks 3 and 6.
- `start_search/1` (facade) → `start_search/2` (SearchSession) — consistent.
- Group statuses `:loading | :ready | {:failed, _} | :abandoned` consistent everywhere.
