# Strip Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-upstream request strip charts on the Status Connections drill-in, fed by a bounded multi-resolution time-series store with a snapshot file, built as a reusable component.

**Architecture:** `MediaCentaur.TimeSeries` (new context) owns an ETS round-robin store, its snapshot file and the fold from rows to window columns. `MediaCentaur.HttpClient.Traffic` replaces `HttpClient.Stats`: it counts the HTTP telemetry event into the store and keeps the recent-requests ring. On the web side `MediaCentaurWeb.Components.StripChart` renders the shell, `StripChart.Feed` drives frames from a LiveView, the `StripChart` JS hook draws uPlot strips, and `StatusLive.TrafficFrame` turns Traffic series into frames.

**Tech Stack:** Elixir/Phoenix LiveView, ETS, `:telemetry`, uPlot 1.6.32 (vendored ESM), Tailwind v4, bun tests, ExUnit.

**Spec:** `docs/superpowers/specs/2026-09-19-strip-chart-design.md`. Read it first.

**House rules that apply to every task:**
- Never run `mix` directly; run `~/scripts/agents/agent-mix <args>` (isolated build root).
- Test first. Run the failing test before the implementation.
- No `Co-Authored-By`. Every commit message ends with a blank line and
  `Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF`.
- Commit on `main`; do not push.
- Zero warnings. `agent-mix compile --warnings-as-errors` must pass after every task.
- Placeholder titles only in tests and stories (`Sample Show`), never real titles.
- UI tasks (12, 14, 16) are dispatched to a subagent with `model: "fable"`.

**Amendment to the spec (record in Task 19):** the app has no time-zone database; `DateTime.shift_zone(_, "localtime")` always falls back to UTC. Wide bars align to local midnight using the OS offset from `:calendar.local_time/0` minus `:calendar.universal_time/0`, computed at fold time. Across a DST change the alignment shifts by an hour for buckets before the change; stated in the `Fold` moduledoc.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/media_centaur/time_series.ex` | Boundary + context moduledoc |
| `lib/media_centaur/time_series/resolution.ex` | The four stored bucket widths and retentions |
| `lib/media_centaur/time_series/window.ex` | The six windows, bar width, bar count, source resolution |
| `lib/media_centaur/time_series/schema.ex` | A store's counter fields (sum or max) and their tuple positions |
| `lib/media_centaur/time_series/store.ex` | GenServer owning the ETS table; `add/5`, `rows/5`, sweep, snapshot timers |
| `lib/media_centaur/time_series/snapshot.ex` | Versioned file write/read |
| `lib/media_centaur/time_series/local_day.ex` | Local-midnight alignment from the OS offset |
| `lib/media_centaur/time_series/fold.ex` | Rows → zero-filled window columns and totals |
| `lib/media_centaur/http_client/traffic.ex` | HTTP tenant: telemetry → store, recent ring, last outcome, `series/3`, `totals/3`, `recent/1` |
| `lib/media_centaur/http_client/retention_policies.ex` | The `:request_history` policy |
| `lib/media_centaur_web/components/strip_chart.ex` | `strip_chart/1` shell component |
| `lib/media_centaur_web/components/strip_chart/feed.ex` | LiveView lifecycle: window param, tick, visibility |
| `lib/media_centaur_web/live/status_live/traffic_frame.ex` | Traffic series → frame |
| `assets/vendor/uplot.js` | uPlot 1.6.32 ESM |
| `assets/js/hooks/strip_chart.js` (+ `.test.js`) | The hook and its pure helpers |
| `storybook/composites/strip_chart.story.exs` | Shell story |

---

### Task 1: Resolution and Window

**Files:**
- Create: `lib/media_centaur/time_series/resolution.ex`
- Create: `lib/media_centaur/time_series/window.ex`
- Create: `lib/media_centaur/time_series.ex`
- Test: `test/media_centaur/time_series/resolution_test.exs`
- Test: `test/media_centaur/time_series/window_test.exs`

- [ ] **Step 1: Write the failing tests**

`test/media_centaur/time_series/resolution_test.exs`:

```elixir
defmodule MediaCentaur.TimeSeries.ResolutionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TimeSeries.Resolution

  test "four resolutions in ascending width" do
    assert Resolution.all() == [:"10s", :"1m", :"10m", :"1h"]
    assert Enum.map(Resolution.all(), &Resolution.width/1) == [10, 60, 600, 3_600]
  end

  test "retention per resolution" do
    assert Resolution.retention(:"10s") == 3_600
    assert Resolution.retention(:"1m") == 6 * 3_600
    assert Resolution.retention(:"10m") == 2 * 86_400
    assert Resolution.retention(:"1h") == 31 * 86_400
  end

  test "bucket_start aligns down to the width" do
    assert Resolution.bucket_start(:"10s", 1_789_800_017) == 1_789_800_010
    assert Resolution.bucket_start(:"1m", 1_789_800_059) == 1_789_800_000
    assert Resolution.bucket_start(:"1h", 1_789_803_599) == 1_789_800_000
  end
end
```

`test/media_centaur/time_series/window_test.exs`:

```elixir
defmodule MediaCentaur.TimeSeries.WindowTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TimeSeries.Window

  test "six windows in order" do
    assert Window.all() == [:"5m", :"1h", :"5h", :"1d", :"1w", :"1mo"]
  end

  test "bar width, bar count and source resolution per window" do
    assert {10, 30, :"10s"} == shape(:"5m")
    assert {60, 60, :"1m"} == shape(:"1h")
    assert {300, 60, :"1m"} == shape(:"5h")
    assert {1_200, 72, :"10m"} == shape(:"1d")
    assert {7_200, 84, :"1h"} == shape(:"1w")
    assert {43_200, 60, :"1h"} == shape(:"1mo")
  end

  test "every bar is a whole multiple of its source resolution" do
    for window <- Window.all() do
      width = MediaCentaur.TimeSeries.Resolution.width(Window.resolution(window))
      assert rem(Window.bar_seconds(window), width) == 0
    end
  end

  test "span never exceeds the source resolution's retention" do
    for window <- Window.all() do
      retention = MediaCentaur.TimeSeries.Resolution.retention(Window.resolution(window))
      assert Window.span_seconds(window) <= retention
    end
  end

  test "parse accepts the six labels and rejects the rest" do
    assert Window.parse("5h") == {:ok, :"5h"}
    assert Window.parse("1mo") == {:ok, :"1mo"}
    assert Window.parse("2h") == :error
    assert Window.parse(nil) == :error
  end

  test "wide bars align to the local day" do
    refute Window.local_aligned?(:"5h")
    assert Window.local_aligned?(:"1d")
    assert Window.local_aligned?(:"1mo")
  end

  defp shape(window),
    do: {Window.bar_seconds(window), Window.bars(window), Window.resolution(window)}
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/time_series/`
Expected: compilation error, `MediaCentaur.TimeSeries.Resolution` undefined.

- [ ] **Step 3: Write the modules**

`lib/media_centaur/time_series.ex`:

```elixir
defmodule MediaCentaur.TimeSeries do
  @moduledoc """
  Bounded, multi-resolution counts of an event along time — a round-robin
  store in ETS with a snapshot file, and the fold that turns its rows into
  the columns a strip chart draws.

  A tenant declares a `Schema` (its counter fields, each summed or kept as
  a maximum), starts one `Store` per series family, calls `Store.add/5`
  from wherever the event happens, and reads with `Fold.series/6`. The
  first tenant is `MediaCentaur.HttpClient.Traffic`.

  Vocabulary (see `docs/GLOSSARY.md` § Time series): a **time bucket** is
  the span one bar covers; a **resolution** is one of the four stored
  bucket widths (`Resolution`); a **window** is the span a viewer selects
  (`Window`); a **snapshot** is the store's on-disk copy (`Snapshot`).
  """
  use Boundary, top_level?: true, deps: [MediaCentaur.Retention], exports: [Fold, Resolution, Schema, Snapshot, Store, Window]
end
```

`lib/media_centaur/time_series/resolution.ex`:

```elixir
defmodule MediaCentaur.TimeSeries.Resolution do
  @moduledoc """
  The four stored bucket widths and how long each is kept. Every event is
  counted into all four at once, so there is no roll-up pass; the sweep
  removes rows past their retention.

  | Resolution | Width | Kept |
  |---|---|---|
  | `:"10s"` | 10 s | 1 h |
  | `:"1m"` | 60 s | 6 h |
  | `:"10m"` | 600 s | 2 d |
  | `:"1h"` | 3600 s | 31 d |

  Bucket starts are epoch seconds aligned down to the width, in UTC.
  """

  @type t :: :"10s" | :"1m" | :"10m" | :"1h"

  @widths %{"10s": 10, "1m": 60, "10m": 600, "1h": 3_600}
  @retention %{"10s": 3_600, "1m": 6 * 3_600, "10m": 2 * 86_400, "1h": 31 * 86_400}

  @spec all() :: [t()]
  def all, do: [:"10s", :"1m", :"10m", :"1h"]

  @spec width(t()) :: pos_integer()
  def width(resolution), do: Map.fetch!(@widths, resolution)

  @spec retention(t()) :: pos_integer()
  def retention(resolution), do: Map.fetch!(@retention, resolution)

  @spec bucket_start(t(), integer()) :: integer()
  def bucket_start(resolution, unix_seconds) do
    width = width(resolution)
    unix_seconds - Integer.mod(unix_seconds, width)
  end
end
```

`lib/media_centaur/time_series/window.ex`:

```elixir
defmodule MediaCentaur.TimeSeries.Window do
  @moduledoc """
  The six spans a viewer can select and, for each, the bar width, the
  number of bars and the stored resolution the bars are summed from.

  | Window | Bar | Bars | From |
  |---|---|---|---|
  | `:"5m"` | 10 s | 30 | `:"10s"` |
  | `:"1h"` | 1 min | 60 | `:"1m"` |
  | `:"5h"` | 5 min | 60 | `:"1m"` × 5 |
  | `:"1d"` | 20 min | 72 | `:"10m"` × 2 |
  | `:"1w"` | 2 h | 84 | `:"1h"` × 2 |
  | `:"1mo"` | 12 h | 60 | `:"1h"` × 12 |

  Bars of 20 minutes and wider are *locally aligned*: they start on the
  machine's local midnight rather than on the UTC epoch (`Fold`).
  """

  alias MediaCentaur.TimeSeries.Resolution

  @type t :: :"5m" | :"1h" | :"5h" | :"1d" | :"1w" | :"1mo"

  @table %{
    "5m": %{bar: 10, bars: 30, resolution: :"10s"},
    "1h": %{bar: 60, bars: 60, resolution: :"1m"},
    "5h": %{bar: 300, bars: 60, resolution: :"1m"},
    "1d": %{bar: 1_200, bars: 72, resolution: :"10m"},
    "1w": %{bar: 7_200, bars: 84, resolution: :"1h"},
    "1mo": %{bar: 43_200, bars: 60, resolution: :"1h"}
  }

  @all [:"5m", :"1h", :"5h", :"1d", :"1w", :"1mo"]

  @spec all() :: [t()]
  def all, do: @all

  @spec parse(term()) :: {:ok, t()} | :error
  def parse(label) when is_binary(label) do
    case Enum.find(@all, &(Atom.to_string(&1) == label)) do
      nil -> :error
      window -> {:ok, window}
    end
  end

  def parse(_other), do: :error

  @spec bar_seconds(t()) :: pos_integer()
  def bar_seconds(window), do: Map.fetch!(@table, window).bar

  @spec bars(t()) :: pos_integer()
  def bars(window), do: Map.fetch!(@table, window).bars

  @spec resolution(t()) :: Resolution.t()
  def resolution(window), do: Map.fetch!(@table, window).resolution

  @spec span_seconds(t()) :: pos_integer()
  def span_seconds(window), do: bar_seconds(window) * bars(window)

  @doc "Bars of 20 minutes and wider start on the local midnight, not the epoch."
  @spec local_aligned?(t()) :: boolean()
  def local_aligned?(window), do: bar_seconds(window) >= 1_200
end
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/time_series/`
Expected: 9 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/time_series.ex lib/media_centaur/time_series/resolution.ex lib/media_centaur/time_series/window.ex test/media_centaur/time_series/
git commit -m "feat(time_series): resolutions and windows

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 2: Schema and Store (counting, reading, sweeping)

**Files:**
- Create: `lib/media_centaur/time_series/schema.ex`
- Create: `lib/media_centaur/time_series/store.ex`
- Test: `test/media_centaur/time_series/store_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.TimeSeries.StoreTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TimeSeries.{Resolution, Schema, Store}

  @schema Schema.new(requests: :sum, failed: :sum, latency_max_ms: :max)
  @now 1_789_800_017

  setup do
    suffix = System.unique_integer([:positive])
    name = :"time_series_store_test_#{suffix}"
    table = :"time_series_store_table_#{suffix}"
    start_supervised!({Store, name: name, table: table, schema: @schema})
    %{name: name, table: table}
  end

  test "add lands in all four resolutions at their bucket starts", %{table: table} do
    Store.add(table, @schema, :tmdb, @now, %{requests: 1, failed: 0, latency_max_ms: 180})

    for resolution <- Resolution.all() do
      start = Resolution.bucket_start(resolution, @now)

      assert [{^start, %{requests: 1, failed: 0, latency_max_ms: 180}}] =
               Store.rows(table, resolution, :tmdb, start, @now)
    end
  end

  test "sums accumulate and maxima keep the largest", %{table: table} do
    Store.add(table, @schema, :tmdb, @now, %{requests: 1, failed: 1, latency_max_ms: 500})
    Store.add(table, @schema, :tmdb, @now + 1, %{requests: 1, failed: 0, latency_max_ms: 120})

    assert [{_, %{requests: 2, failed: 1, latency_max_ms: 500}}] =
             Store.rows(table, :"10s", :tmdb, @now - 10, @now + 1)
  end

  test "rows are per key and sorted ascending within the asked span", %{table: table} do
    Store.add(table, @schema, :tmdb, @now, %{requests: 1, failed: 0, latency_max_ms: 1})
    Store.add(table, @schema, :tmdb, @now + 60, %{requests: 2, failed: 0, latency_max_ms: 1})
    Store.add(table, @schema, :github, @now, %{requests: 9, failed: 0, latency_max_ms: 1})

    assert [{first, %{requests: 1}}, {second, %{requests: 2}}] =
             Store.rows(table, :"1m", :tmdb, @now - 60, @now + 60)

    assert first < second
    assert Store.rows(table, :"1m", :tmdb, @now + 61, @now + 120) == []
  end

  test "rows of a store that is not running are empty" do
    assert Store.rows(:no_such_table, :"1m", :tmdb, 0, @now) == []
  end

  test "sweep removes rows past each resolution's retention and reports the count",
       %{name: name, table: table} do
    old = @now - Resolution.retention(:"10s") - 20
    Store.add(table, @schema, :tmdb, old, %{requests: 1, failed: 0, latency_max_ms: 1})
    Store.add(table, @schema, :tmdb, @now, %{requests: 1, failed: 0, latency_max_ms: 1})

    # `old` is past the 10 s retention (1 h) but inside the 1 min retention (6 h).
    assert Store.sweep_now(name, @now) == 1
    assert Store.rows(table, :"10s", :tmdb, 0, @now) |> length() == 1
    assert Store.rows(table, :"1m", :tmdb, 0, @now) |> length() == 2
  end

  test "writes are counted so a snapshot can be skipped when nothing changed", %{table: table} do
    assert Store.writes(table) == 0
    Store.add(table, @schema, :tmdb, @now, %{requests: 1, failed: 0, latency_max_ms: 1})
    assert Store.writes(table) == 1
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/time_series/store_test.exs`
Expected: compilation error, `Schema` / `Store` undefined.

- [ ] **Step 3: Write Schema**

`lib/media_centaur/time_series/schema.ex`:

```elixir
defmodule MediaCentaur.TimeSeries.Schema do
  @moduledoc """
  A store's counter fields, in tuple order. Each field is `:sum` (added on
  every event) or `:max` (kept as the largest seen). A row in the table is
  `{key, v1, v2, …}` with the key at position 1 and field `i` at position
  `i + 1`; the schema precomputes the positions so `Store.add/5` builds
  its ETS operations without walking a keyword list per event.

  Build one at compile time with a module attribute:

      @schema Schema.new(requests: :sum, failed: :sum, latency_max_ms: :max)
  """

  @type kind :: :sum | :max
  @type t :: %__MODULE__{
          fields: [{atom(), kind()}],
          names: [atom()],
          positions: %{atom() => pos_integer()},
          sums: [atom()],
          maxes: [atom()],
          zeros: [0]
        }

  @enforce_keys [:fields, :names, :positions, :sums, :maxes, :zeros]
  defstruct [:fields, :names, :positions, :sums, :maxes, :zeros]

  @spec new([{atom(), kind()}]) :: t()
  def new(fields) when is_list(fields) and fields != [] do
    names = Keyword.keys(fields)
    positions = names |> Enum.with_index(2) |> Map.new()

    %__MODULE__{
      fields: fields,
      names: names,
      positions: positions,
      sums: for({name, :sum} <- fields, do: name),
      maxes: for({name, :max} <- fields, do: name),
      zeros: List.duplicate(0, length(fields))
    }
  end

  @doc "Turns a row tuple's values back into a map keyed by field name."
  @spec values(t(), tuple()) :: %{atom() => integer()}
  def values(%__MODULE__{names: names}, row) when is_tuple(row) do
    names |> Enum.with_index(2) |> Map.new(fn {name, pos} -> {name, elem(row, pos - 1)} end)
  end

  @doc "A row tuple for `key` from a values map (missing fields are 0)."
  @spec row(t(), term(), %{atom() => integer()}) :: tuple()
  def row(%__MODULE__{names: names}, key, values) do
    List.to_tuple([key | Enum.map(names, &Map.get(values, &1, 0))])
  end
end
```

- [ ] **Step 4: Write Store**

`lib/media_centaur/time_series/store.ex`:

```elixir
defmodule MediaCentaur.TimeSeries.Store do
  @moduledoc """
  The round-robin store: one named, public ETS `:set` holding
  `{{resolution, key, bucket_start}, counters…}` rows for every
  `Resolution`, owned by this process.

  Counting happens in the caller (`add/5`): per resolution, one
  `:ets.update_counter/4` with a default row for the summed fields, then
  one `:ets.select_replace/2` with a bound key per max field — an atomic
  compare-and-set on that one object. About two ETS operations per
  resolution per event, no message to this process. Rows exist only for
  buckets that saw an event.

  This process only keeps the table bounded and durable: once a minute it
  sweeps rows older than their resolution's retention and, if the write
  counter moved, writes the whole table to the snapshot file
  (`Snapshot`). On boot it loads the file; on clean shutdown it writes
  once more. A store started without `:snapshot_path` is memory-only
  (tests).

  Reads (`rows/5`) bypass the process and return `[]` when the table does
  not exist, so a reader on a node where the tenant is not started (the
  test environment) sees an empty series rather than an error.

  Options: `:name`, `:table` (both required and unique per instance),
  `:schema` (`Schema.t/0`), `:snapshot_path`, `:retention_policy` (the
  `Retention` policy key to report sweep counts under), `:sweep_ms`,
  `:snapshot_ms` (both default one minute).
  """
  use GenServer

  alias MediaCentaur.TimeSeries.{Resolution, Schema, Snapshot}

  require MediaCentaur.Log

  @minute 60_000
  @writes_key :__writes__

  # --- Public API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @doc "Counts one event at `unix_seconds` into every resolution."
  @spec add(atom(), Schema.t(), term(), integer(), %{atom() => integer()}) :: :ok
  def add(table, %Schema{} = schema, key, unix_seconds, values) when is_map(values) do
    sum_ops = for name <- schema.sums, do: {schema.positions[name], Map.get(values, name, 0)}

    for resolution <- Resolution.all() do
      row_key = {resolution, key, Resolution.bucket_start(resolution, unix_seconds)}
      :ets.update_counter(table, row_key, sum_ops, Schema.row(schema, row_key, %{}))

      for name <- schema.maxes, value = Map.get(values, name, 0), value > 0 do
        :ets.select_replace(table, max_spec(schema, row_key, schema.positions[name], value))
      end
    end

    :ets.update_counter(table, @writes_key, {2, 1}, {@writes_key, 0})
    :ok
  end

  @doc "Rows of one resolution and key with bucket_start in `from..to`, ascending, as `{bucket_start, values}`."
  @spec rows(atom(), Resolution.t(), term(), integer(), integer()) :: [{integer(), map()}]
  def rows(table, resolution, key, from, to) do
    case :ets.whereis(table) do
      :undefined ->
        []

      _tid ->
        schema = schema(table)

        table
        |> :ets.select([{{{resolution, key, :"$1"}, :_}, [], [:"$_"]}])
        |> Enum.filter(fn row -> elem(row, 0) |> elem(2) |> in_span?(from, to) end)
        |> Enum.map(fn row -> {elem(elem(row, 0), 2), Schema.values(schema, row)} end)
        |> Enum.sort_by(&elem(&1, 0))
    end
  end

  @doc "How many `add/5` calls the table has seen since it was created or loaded."
  @spec writes(atom()) :: non_neg_integer()
  def writes(table) do
    case :ets.lookup(table, @writes_key) do
      [{@writes_key, count}] -> count
      [] -> 0
    end
  end

  @doc "Sweeps now, synchronously, as of `now`; returns the number of rows removed."
  @spec sweep_now(GenServer.server(), integer()) :: non_neg_integer()
  def sweep_now(server, now), do: GenServer.call(server, {:sweep, now})

  @doc "Writes the snapshot now, synchronously. `:ok` whether or not anything changed."
  @spec snapshot_now(GenServer.server()) :: :ok
  def snapshot_now(server), do: GenServer.call(server, :snapshot)

  # --- GenServer ---

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    table = Keyword.fetch!(opts, :table)
    schema = Keyword.fetch!(opts, :schema)

    ^table =
      :ets.new(table, [
        :set,
        :public,
        :named_table,
        write_concurrency: true,
        read_concurrency: true
      ])

    :ets.insert(table, {:__schema__, schema})

    state = %{
      table: table,
      schema: schema,
      snapshot_path: Keyword.get(opts, :snapshot_path),
      retention_policy: Keyword.get(opts, :retention_policy),
      sweep_ms: Keyword.get(opts, :sweep_ms, @minute),
      snapshot_ms: Keyword.get(opts, :snapshot_ms, @minute),
      snapshotted_writes: 0
    }

    state = load_snapshot(state)
    sweep(state, System.os_time(:second))
    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:sweep, now}, _from, state), do: {:reply, sweep(state, now), state}
  def handle_call(:snapshot, _from, state), do: {:reply, :ok, write_snapshot(state)}

  @impl true
  def handle_info(:sweep, state) do
    sweep(state, System.os_time(:second))
    Process.send_after(self(), :sweep, state.sweep_ms)
    {:noreply, state}
  end

  def handle_info(:snapshot, state) do
    state = write_snapshot(state)
    Process.send_after(self(), :snapshot, state.snapshot_ms)
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    write_snapshot(state)
    :ok
  end

  # --- Internals ---

  defp schedule(state) do
    Process.send_after(self(), :sweep, state.sweep_ms)
    Process.send_after(self(), :snapshot, state.snapshot_ms)
  end

  defp schema(table) do
    [{:__schema__, schema}] = :ets.lookup(table, :__schema__)
    schema
  end

  defp in_span?(start, from, to), do: start >= from and start <= to

  # `{{res, key, start}, $1, …, $n}` with the key bound; replace when the
  # max field is smaller than `value`. Tuples in the body are wrapped once.
  defp max_spec(%Schema{names: names}, row_key, position, value) do
    variables = Enum.map(1..length(names), &:"$#{&1}")
    head = List.to_tuple([row_key | variables])
    field_variable = :"$#{position - 1}"

    body_values =
      Enum.map(variables, fn variable -> if variable == field_variable, do: value, else: variable end)

    body = List.to_tuple([{row_key} | body_values])
    [{head, [{:<, field_variable, value}], [{body}]}]
  end

  defp sweep(state, now) do
    pruned =
      Enum.reduce(Resolution.all(), 0, fn resolution, acc ->
        cutoff = now - Resolution.retention(resolution)

        acc +
          :ets.select_delete(state.table, [
            {{{resolution, :_, :"$1"}, :_}, [{:<, :"$1", cutoff}], [true]}
          ])
      end)

    if state.retention_policy && pruned > 0,
      do: MediaCentaur.Retention.record_run(state.retention_policy, pruned)

    pruned
  end

  defp write_snapshot(%{snapshot_path: nil} = state), do: state

  defp write_snapshot(state) do
    writes = writes(state.table)

    if writes == state.snapshotted_writes do
      state
    else
      rows = :ets.select(state.table, [{{{:_, :_, :_}, :_}, [], [:"$_"]}])

      case Snapshot.write(state.snapshot_path, state.schema, rows) do
        :ok ->
          :ok

        {:error, reason} ->
          MediaCentaur.Log.warning(:system, "time series snapshot not written",
            path: state.snapshot_path,
            reason: inspect(reason)
          )
      end

      %{state | snapshotted_writes: writes}
    end
  end

  defp load_snapshot(%{snapshot_path: nil} = state), do: state

  defp load_snapshot(state) do
    case Snapshot.read(state.snapshot_path, state.schema) do
      {:ok, rows} ->
        :ets.insert(state.table, rows)
        state

      :empty ->
        state

      {:error, reason} ->
        MediaCentaur.Log.warning(:system, "time series snapshot ignored; starting empty",
          path: state.snapshot_path,
          reason: inspect(reason)
        )

        state
    end
  end
end
```

`rows/5` selects on the bound `{resolution, key, _}` prefix; the guard on `$1` for the span is done in Elixir because a match-spec guard cannot bind into a nested key tuple's third element directly without repeating it — keep the select as written. The `:__schema__` and `:__writes__` rows have atom keys, so the three-tuple key patterns never match them.

Check `MediaCentaur.Log.warning/3` exists with that arity (`lib/media_centaur/log.ex`); if the macro is `warning(component, message, metadata)` use it as written, otherwise adapt to its signature. `:system` is an existing component tag.

- [ ] **Step 5: Run the test**

Run: `~/scripts/agents/agent-mix test test/media_centaur/time_series/store_test.exs`
Expected: 6 tests, 0 failures. (The `Snapshot` module is referenced but not exercised; create the stub in Task 3 first if the compiler complains: an empty module with `write/3` returning `:ok` and `read/2` returning `:empty`.)

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/time_series/schema.ex lib/media_centaur/time_series/store.ex test/media_centaur/time_series/store_test.exs
git commit -m "feat(time_series): schema and round-robin store

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 3: Snapshot file

**Files:**
- Create: `lib/media_centaur/time_series/snapshot.ex`
- Test: `test/media_centaur/time_series/snapshot_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.TimeSeries.SnapshotTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TimeSeries.{Schema, Snapshot, Store}

  @schema Schema.new(requests: :sum, latency_max_ms: :max)
  @now 1_789_800_017

  @moduletag :tmp_dir

  test "write then read round-trips rows", %{tmp_dir: dir} do
    path = Path.join(dir, "traffic.snapshot")
    rows = [{{:"10s", :tmdb, 1_789_800_010}, 3, 180}, {{:"1h", :tmdb, 1_789_800_000}, 3, 180}]

    assert :ok = Snapshot.write(path, @schema, rows)
    assert {:ok, read} = Snapshot.read(path, @schema)
    assert Enum.sort(read) == Enum.sort(rows)
    refute File.exists?(path <> ".tmp")
  end

  test "a missing file is empty", %{tmp_dir: dir} do
    assert Snapshot.read(Path.join(dir, "none.snapshot"), @schema) == :empty
  end

  test "a file written for other fields is rejected", %{tmp_dir: dir} do
    path = Path.join(dir, "traffic.snapshot")
    :ok = Snapshot.write(path, Schema.new(other: :sum), [{{:"10s", :tmdb, 1}, 1}])
    assert {:error, :schema_mismatch} = Snapshot.read(path, @schema)
  end

  test "garbage is rejected", %{tmp_dir: dir} do
    path = Path.join(dir, "traffic.snapshot")
    File.write!(path, "not a snapshot")
    assert {:error, _} = Snapshot.read(path, @schema)
  end

  test "a store loads its snapshot on boot and writes on shutdown", %{tmp_dir: dir} do
    path = Path.join(dir, "traffic.snapshot")
    suffix = System.unique_integer([:positive])
    table = :"snapshot_store_#{suffix}"
    name = :"snapshot_store_name_#{suffix}"

    pid = start_supervised!({Store, name: name, table: table, schema: @schema, snapshot_path: path})
    Store.add(table, @schema, :tmdb, @now, %{requests: 2, latency_max_ms: 90})
    :ok = stop_supervised!(name)
    refute Process.alive?(pid)
    assert File.exists?(path)

    table2 = :"snapshot_store_#{suffix}_b"
    name2 = :"snapshot_store_name_#{suffix}_b"
    start_supervised!({Store, name: name2, table: table2, schema: @schema, snapshot_path: path})

    assert [{_, %{requests: 2, latency_max_ms: 90}}] =
             Store.rows(table2, :"10s", :tmdb, @now - 10, @now)
  end
end
```

`stop_supervised!/1` takes the child id, which for a `{Store, opts}` child spec is `Store` unless `child_spec` sets it — use `start_supervised!({Store, ...}, id: name)` and `stop_supervised!(name)` so two stores can coexist in one test. Adjust both calls accordingly.

- [ ] **Step 2: Run it to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/time_series/snapshot_test.exs`
Expected: `Snapshot` undefined (or the stub's `:empty`).

- [ ] **Step 3: Write Snapshot**

```elixir
defmodule MediaCentaur.TimeSeries.Snapshot do
  @moduledoc """
  The store's on-disk copy: one file holding
  `{:media_centaur_time_series, 1, fields, rows}` in External Term Format,
  compressed, written to `<path>.tmp` and renamed into place so a crash
  mid-write leaves the previous file intact.

  `read/2` accepts only a file whose tag, version and field list match the
  schema given; anything else is `{:error, reason}` and the caller starts
  empty. Observational data is never migrated.
  """

  alias MediaCentaur.TimeSeries.Schema

  @tag :media_centaur_time_series
  @version 1

  @spec write(Path.t(), Schema.t(), [tuple()]) :: :ok | {:error, term()}
  def write(path, %Schema{fields: fields}, rows) do
    binary = :erlang.term_to_binary({@tag, @version, fields, rows}, compressed: 6)
    tmp = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp, binary),
         :ok <- File.rename(tmp, path) do
      :ok
    end
  end

  @spec read(Path.t(), Schema.t()) :: {:ok, [tuple()]} | :empty | {:error, term()}
  def read(path, %Schema{fields: fields}) do
    case File.read(path) do
      {:error, :enoent} -> :empty
      {:error, reason} -> {:error, reason}
      {:ok, binary} -> decode(binary, fields)
    end
  end

  defp decode(binary, fields) do
    case :erlang.binary_to_term(binary, [:safe]) do
      {@tag, @version, ^fields, rows} when is_list(rows) -> {:ok, rows}
      {@tag, @version, _other_fields, _rows} -> {:error, :schema_mismatch}
      _other -> {:error, :unrecognised}
    end
  rescue
    ArgumentError -> {:error, :corrupt}
  end
end
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/time_series/`
Expected: all pass, including the boot/shutdown round trip from Task 2's `Store`.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/time_series/snapshot.ex test/media_centaur/time_series/snapshot_test.exs
git commit -m "feat(time_series): versioned snapshot file

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 4: LocalDay and Fold

**Files:**
- Create: `lib/media_centaur/time_series/local_day.ex`
- Create: `lib/media_centaur/time_series/fold.ex`
- Test: `test/media_centaur/time_series/fold_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.TimeSeries.FoldTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TimeSeries.{Fold, LocalDay, Schema, Store}

  @schema Schema.new(requests: :sum, failed: :sum, latency_max_ms: :max)
  # 2026-09-19 13:26:17 UTC
  @now 1_789_824_377

  setup do
    suffix = System.unique_integer([:positive])
    table = :"fold_table_#{suffix}"
    start_supervised!({Store, name: :"fold_store_#{suffix}", table: table, schema: @schema})
    %{table: table}
  end

  test "a 1h window is 60 one-minute buckets ending at the current minute, zero-filled",
       %{table: table} do
    Store.add(table, @schema, :tmdb, @now - 120, %{requests: 3, failed: 1, latency_max_ms: 300})
    Store.add(table, @schema, :tmdb, @now, %{requests: 1, failed: 0, latency_max_ms: 90})

    series = Fold.series(table, @schema, :tmdb, :"1h", @now, utc_offset: 0)

    assert length(series.starts) == 60
    assert List.last(series.starts) == @now - rem(@now, 60)
    assert hd(series.starts) == List.last(series.starts) - 59 * 60
    assert series.bar_seconds == 60
    assert Enum.sum(series.columns.requests) == 4
    assert Enum.at(series.columns.requests, 57) == 3
    assert Enum.at(series.columns.failed, 57) == 1
    assert Enum.at(series.columns.latency_max_ms, 57) == 300
    assert List.last(series.columns.requests) == 1
    assert series.totals == %{requests: 4, failed: 1, latency_max_ms: 300}
  end

  test "a 5h window sums five one-minute rows into each bar", %{table: table} do
    for offset <- 0..4, do: Store.add(table, @schema, :tmdb, @now - offset * 60, %{requests: 1, failed: 0, latency_max_ms: 1})

    series = Fold.series(table, @schema, :tmdb, :"5h", @now, utc_offset: 0)

    assert length(series.starts) == 60
    assert series.bar_seconds == 300
    assert Enum.sum(series.columns.requests) == 5
    # the five minutes straddle at most two 5-minute bars
    assert series.columns.requests |> Enum.reverse() |> Enum.take(2) |> Enum.sum() == 5
  end

  test "wide bars start on the local midnight given by the offset", %{table: table} do
    two_hours_east = 2 * 3_600
    series = Fold.series(table, @schema, :tmdb, :"1mo", @now, utc_offset: two_hours_east)

    local_midnight = LocalDay.start_of_day(@now, two_hours_east)
    assert rem(local_midnight - two_hours_east, 86_400) == 0
    assert Enum.all?(series.starts, &(rem(&1 - local_midnight, 43_200) == 0))
    assert List.last(series.starts) <= @now
    assert List.last(series.starts) + 43_200 > @now
  end

  test "a series with no rows is all zeros", %{table: table} do
    series = Fold.series(table, @schema, :github, :"5m", @now, utc_offset: 0)
    assert length(series.starts) == 30
    assert Enum.all?(series.columns.requests, &(&1 == 0))
    assert series.totals == %{requests: 0, failed: 0, latency_max_ms: 0}
  end

  test "LocalDay.start_of_day is the midnight before `unix` in the offset zone" do
    # 13:26:17 UTC at +02:00 is 15:26:17 local; local midnight is 22:00 UTC the day before.
    assert LocalDay.start_of_day(@now, 7_200) == @now - (15 * 3_600 + 26 * 60 + 17)
    # at -05:00 it is 08:26:17 local; local midnight is 05:00 UTC the same day.
    assert LocalDay.start_of_day(@now, -18_000) == @now - (8 * 3_600 + 26 * 60 + 17)
  end

  test "LocalDay.utc_offset_seconds is a whole number of minutes within a day" do
    offset = LocalDay.utc_offset_seconds()
    assert rem(offset, 60) == 0
    assert abs(offset) < 86_400
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/time_series/fold_test.exs`
Expected: `Fold` / `LocalDay` undefined.

- [ ] **Step 3: Write LocalDay and Fold**

`lib/media_centaur/time_series/local_day.ex`:

```elixir
defmodule MediaCentaur.TimeSeries.LocalDay do
  @moduledoc """
  Local-midnight alignment without a time-zone database.

  The app ships none (`DateTime.shift_zone/2` with a named zone falls back
  to UTC everywhere), so the local offset comes from the operating system
  through `:calendar.local_time/0` against `:calendar.universal_time/0`,
  read at fold time. That is the offset in force *now*: a day-wide bar
  that lies across a daylight-saving change is an hour longer or shorter
  than its neighbours, and bars before the change sit an hour off their
  local midnight until the window rolls past it. Documented, bounded, and
  not worth a dependency.
  """

  @day 86_400

  @doc "Seconds the machine's local clock is ahead of UTC (negative when behind)."
  @spec utc_offset_seconds() :: integer()
  def utc_offset_seconds do
    local = :calendar.datetime_to_gregorian_seconds(:calendar.local_time())
    universal = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time())
    local - universal
  end

  @doc "Epoch seconds of the local midnight at or before `unix`, for a zone `offset` seconds from UTC."
  @spec start_of_day(integer(), integer()) :: integer()
  def start_of_day(unix, offset) do
    local = unix + offset
    local - Integer.mod(local, @day) - offset
  end
end
```

`lib/media_centaur/time_series/fold.ex`:

```elixir
defmodule MediaCentaur.TimeSeries.Fold do
  @moduledoc """
  Rows of one key, folded into the bars of a `Window`: fixed-length
  columns per schema field, zero-filled, plus window totals (sum for
  `:sum` fields, max for `:max` fields).

  Bars are anchored so the last bar is the one in progress. Narrow bars
  (under 20 minutes) anchor on the epoch; wide bars anchor on the local
  midnight from `LocalDay`, so a 12-hour bar runs midnight to noon where
  the machine is. Pass `utc_offset:` to pin the zone (tests); by default
  it is read from the operating system.

  The result is what a tenant turns into a strip chart frame:

      %{
        window: :"1h", bar_seconds: 60,
        starts: [unix, …],                 # one per bar, ascending
        columns: %{requests: [int, …], …}, # same length as starts
        totals: %{requests: int, …}
      }
  """

  alias MediaCentaur.TimeSeries.{LocalDay, Schema, Store, Window}

  @type series :: %{
          window: Window.t(),
          bar_seconds: pos_integer(),
          starts: [integer()],
          columns: %{atom() => [integer()]},
          totals: %{atom() => integer()}
        }

  @spec series(atom(), Schema.t(), term(), Window.t(), integer(), keyword()) :: series()
  def series(table, %Schema{} = schema, key, window, now, opts \\ []) do
    bar = Window.bar_seconds(window)
    bars = Window.bars(window)
    anchor = anchor(window, now, opts)
    current = Integer.floor_div(now - anchor, bar)
    first = current - bars + 1
    starts = Enum.map(first..current, &(anchor + &1 * bar))
    from = hd(starts)

    rows = Store.rows(table, Window.resolution(window), key, from, now)

    empty = Map.new(schema.names, &{&1, :array.new(bars, default: 0)})

    filled =
      Enum.reduce(rows, empty, fn {start, values}, acc ->
        index = Integer.floor_div(start - anchor, bar) - first

        Enum.reduce(schema.fields, acc, fn {name, kind}, acc ->
          Map.update!(acc, name, fn column ->
            :array.set(index, combine(kind, :array.get(index, column), values[name]), column)
          end)
        end)
      end)

    columns = Map.new(filled, fn {name, column} -> {name, :array.to_list(column)} end)

    totals =
      Map.new(schema.fields, fn
        {name, :sum} -> {name, Enum.sum(columns[name])}
        {name, :max} -> {name, Enum.max(columns[name], fn -> 0 end)}
      end)

    %{window: window, bar_seconds: bar, starts: starts, columns: columns, totals: totals}
  end

  defp combine(:sum, current, value), do: current + value
  defp combine(:max, current, value), do: max(current, value)

  defp anchor(window, now, opts) do
    if Window.local_aligned?(window) do
      offset = Keyword.get_lazy(opts, :utc_offset, &LocalDay.utc_offset_seconds/0)
      LocalDay.start_of_day(now, offset)
    else
      0
    end
  end
end
```

Every row returned by `Store.rows/5` has `start >= from`, and `from` is a bar boundary, so `index` is always within `0..bars-1`.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/time_series/`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/time_series/local_day.ex lib/media_centaur/time_series/fold.ex test/media_centaur/time_series/fold_test.exs
git commit -m "feat(time_series): fold rows into window columns; local-day anchor

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 5: Traffic — the HTTP tenant

**Files:**
- Create: `lib/media_centaur/http_client/traffic.ex`
- Test: `test/media_centaur/http_client/traffic_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.HttpClient.TrafficTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.HttpClient.Traffic
  alias MediaCentaur.TimeSeries.Store

  @stop_event [:media_centaur, :http, :request, :stop]
  @now 1_789_824_377

  setup do
    suffix = System.unique_integer([:positive])
    store = :"traffic_store_#{suffix}"
    recent = :"traffic_recent_#{suffix}"

    start_supervised!(
      {Store, name: :"traffic_store_name_#{suffix}", table: store, schema: Traffic.schema()},
      id: :store
    )

    start_supervised!(
      {Traffic, name: :"traffic_#{suffix}", attach: false, store_table: store, recent_table: recent},
      id: :traffic
    )

    %{tables: [store_table: store, recent_table: recent]}
  end

  defp record(tables, overrides) do
    metadata =
      Map.merge(
        %{upstream: :tmdb, method: :get, path: "/3/movie/1", status: 200, error: nil, cache: :miss},
        Map.drop(overrides, [:duration_ms, :at])
      )

    duration =
      System.convert_time_unit(Map.get(overrides, :duration_ms, 100), :millisecond, :native)

    config = %{
      store: tables[:store_table],
      recent: tables[:recent_table],
      now: Map.get(overrides, :at, @now)
    }

    Traffic.handle_telemetry(@stop_event, %{duration: duration}, metadata, config)
  end

  test "a request counts requests and latency; a failure counts failed too", %{tables: tables} do
    record(tables, %{duration_ms: 200})
    record(tables, %{status: 500, duration_ms: 400})

    totals = Traffic.totals(:tmdb, [seconds: 900, now: @now] ++ tables)
    assert totals == %{requests: 2, failed: 1, cached: 0, mean_ms: 300, worst_ms: 400}
  end

  test "a transport error is a failure", %{tables: tables} do
    record(tables, %{status: nil, error: %RuntimeError{message: "closed"}})
    assert %{requests: 1, failed: 1} = Traffic.totals(:tmdb, [seconds: 900, now: @now] ++ tables)
  end

  test "a cache hit counts only cached and leaves the last outcome alone", %{tables: tables} do
    record(tables, %{cache: :hit})

    assert Traffic.totals(:tmdb, [seconds: 900, now: @now] ++ tables) ==
             %{requests: 0, failed: 0, cached: 1, mean_ms: nil, worst_ms: nil}

    assert Traffic.last(:tmdb, tables) == nil
  end

  test "last outcome and last success follow requests", %{tables: tables} do
    record(tables, %{at: @now - 30})
    assert %{outcome: :ok, at: %DateTime{}} = Traffic.last(:tmdb, tables)
    record(tables, %{at: @now, status: 503})
    assert %{outcome: :failed} = Traffic.last(:tmdb, tables)
    assert DateTime.to_unix(Traffic.last_success_at(:tmdb, tables)) == @now - 30
  end

  test "series carries went_out, failed, cached, mean and worst per bar", %{tables: tables} do
    record(tables, %{duration_ms: 100})
    record(tables, %{duration_ms: 300, status: 502})

    series = Traffic.series(:tmdb, :"1h", [now: @now, utc_offset: 0] ++ tables)

    assert length(series.starts) == 60
    assert List.last(series.went_out) == 1
    assert List.last(series.failed) == 1
    assert List.last(series.cached) == 0
    assert List.last(series.mean_ms) == 200
    assert List.last(series.worst_ms) == 300
    assert Enum.at(series.mean_ms, 0) == nil
    assert series.totals == %{requests: 2, failed: 1, cached: 0, mean_ms: 200, worst_ms: 300}
  end

  test "recent keeps the newest twenty, newest first", %{tables: tables} do
    for n <- 1..25, do: record(tables, %{path: "/3/movie/#{n}", at: @now + n})

    recent = Traffic.recent(tables)
    assert length(recent) == 20
    assert hd(recent).path == "/3/movie/25"
    assert List.last(recent).path == "/3/movie/6"
  end

  test "reads on a node without the tenant are empty" do
    tables = [store_table: :no_store, recent_table: :no_recent]
    assert Traffic.recent(tables) == []
    assert Traffic.last(:tmdb, tables) == nil
    assert %{requests: 0} = Traffic.totals(:tmdb, [seconds: 900, now: @now] ++ tables)
    assert length(Traffic.series(:tmdb, :"5m", [now: @now] ++ tables).starts) == 30
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/http_client/traffic_test.exs`
Expected: `Traffic` undefined.

- [ ] **Step 3: Write Traffic**

```elixir
defmodule MediaCentaur.HttpClient.Traffic do
  @moduledoc """
  The HTTP layer's record of requests per upstream over time — the
  tenant of `MediaCentaur.TimeSeries` behind the Connections strip charts.

  Attaches to `[:media_centaur, :http, :request, :stop]`
  (`MediaCentaur.HttpClient.Instrument`) and, in the handler, in the
  requesting process, counts the attempt into the store: `requests`,
  `failed` (transport error or status 400+), `cached` (a cache hit, which
  never reached the upstream and counts as nothing else), `latency_sum_ms`
  and `latency_max_ms`. It also keeps, in its own ETS table, a twenty-slot
  ring of the most recent requests (hits included) and, per upstream, the
  last outcome and the last success time.

  Reads: `series/3` for one upstream and window (the strip chart's
  columns), `totals/3` over an arbitrary span (the incident assessor's
  fifteen minutes), `recent/1`, `last/2`, `last_success_at/2`. All return
  empty values when the tables do not exist, which is the test
  environment, where `HttpClient.Supervisor` is not started.

  Pass `attach: false` to start an instance fed only by direct
  `handle_telemetry/4` calls; telemetry dispatch is global, so an attached
  test instance would count every request the suite makes. Tests pass
  their own `store_table:` / `recent_table:` and read with the same
  options.
  """
  use GenServer

  alias MediaCentaur.HttpClient.Instrument
  alias MediaCentaur.TimeSeries.{Fold, Schema, Store}

  @schema Schema.new(
            requests: :sum,
            failed: :sum,
            cached: :sum,
            latency_sum_ms: :sum,
            latency_max_ms: :max
          )
  @store_table :http_traffic
  @recent_table :http_traffic_recent
  @recent_slots 20

  @type outcome :: :ok | :failed
  @type totals :: %{
          requests: non_neg_integer(),
          failed: non_neg_integer(),
          cached: non_neg_integer(),
          mean_ms: non_neg_integer() | nil,
          worst_ms: non_neg_integer() | nil
        }

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "The store schema; `HttpClient.Supervisor` starts the store with it."
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @doc "The store table name the supervisor uses."
  @spec store_table() :: atom()
  def store_table, do: @store_table

  @doc """
  One upstream's bars for a window. Options: `now:` (unix seconds),
  `utc_offset:` (see `Fold`), `store_table:`.
  """
  @spec series(atom(), MediaCentaur.TimeSeries.Window.t(), keyword()) :: map()
  def series(upstream, window, opts \\ []) do
    fold =
      Fold.series(
        Keyword.get(opts, :store_table, @store_table),
        @schema,
        upstream,
        window,
        Keyword.get_lazy(opts, :now, fn -> System.os_time(:second) end),
        Keyword.take(opts, [:utc_offset])
      )

    columns = fold.columns

    %{
      window: window,
      bar_seconds: fold.bar_seconds,
      starts: fold.starts,
      went_out: Enum.zip_with(columns.requests, columns.failed, &(&1 - &2)),
      failed: columns.failed,
      cached: columns.cached,
      mean_ms: Enum.zip_with(columns.latency_sum_ms, columns.requests, &mean/2),
      worst_ms: Enum.zip_with(columns.latency_max_ms, columns.requests, &worst/2),
      totals: totals_from(fold.totals)
    }
  end

  @doc "Totals over the last `seconds:` (default 900) for one upstream, from the 10-second resolution."
  @spec totals(atom(), keyword()) :: totals()
  def totals(upstream, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> System.os_time(:second) end)
    seconds = Keyword.get(opts, :seconds, 900)
    table = Keyword.get(opts, :store_table, @store_table)

    table
    |> Store.rows(:"10s", upstream, now - seconds, now)
    |> Enum.reduce(%{requests: 0, failed: 0, cached: 0, latency_sum_ms: 0, latency_max_ms: 0}, fn {_start, values}, acc ->
      %{
        requests: acc.requests + values.requests,
        failed: acc.failed + values.failed,
        cached: acc.cached + values.cached,
        latency_sum_ms: acc.latency_sum_ms + values.latency_sum_ms,
        latency_max_ms: max(acc.latency_max_ms, values.latency_max_ms)
      }
    end)
    |> totals_from()
  end

  @doc "The twenty most recent requests, newest first."
  @spec recent(keyword()) :: [map()]
  def recent(opts \\ []) do
    table = Keyword.get(opts, :recent_table, @recent_table)

    case :ets.whereis(table) do
      :undefined ->
        []

      _tid ->
        table
        |> :ets.select([{{{:slot, :_}, :"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}])
        |> Enum.sort_by(&elem(&1, 0), :desc)
        |> Enum.map(&elem(&1, 1))
    end
  end

  @doc "Outcome and time of the upstream's most recent request, or nil."
  @spec last(atom(), keyword()) :: %{outcome: outcome(), at: DateTime.t()} | nil
  def last(upstream, opts \\ []) do
    case lookup(Keyword.get(opts, :recent_table, @recent_table), {:last, upstream}) do
      [{_, outcome, unix}] -> %{outcome: outcome, at: DateTime.from_unix!(unix)}
      [] -> nil
    end
  end

  @doc "When the upstream last answered successfully, or nil."
  @spec last_success_at(atom(), keyword()) :: DateTime.t() | nil
  def last_success_at(upstream, opts \\ []) do
    case lookup(Keyword.get(opts, :recent_table, @recent_table), {:last_success, upstream}) do
      [{_, unix}] -> DateTime.from_unix!(unix)
      [] -> nil
    end
  end

  @doc false
  def handle_telemetry(_event, %{duration: duration}, metadata, config) do
    now = Map.get_lazy(config, :now, fn -> System.os_time(:second) end)
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    hit? = metadata.cache == :hit
    failed? = metadata.error != nil or (is_integer(metadata.status) and metadata.status >= 400)
    upstream = metadata.upstream

    Store.add(config.store, @schema, upstream, now, %{
      requests: if(hit?, do: 0, else: 1),
      failed: if(failed? and not hit?, do: 1, else: 0),
      cached: if(hit?, do: 1, else: 0),
      latency_sum_ms: if(hit?, do: 0, else: duration_ms),
      latency_max_ms: if(hit?, do: 0, else: duration_ms)
    })

    entry = %{
      at: DateTime.from_unix!(now),
      upstream: upstream,
      method: metadata.method,
      path: metadata.path,
      status: metadata.status,
      error: metadata.error && Exception.message(metadata.error),
      duration_ms: duration_ms,
      cache: metadata.cache
    }

    recent = config.recent
    seq = :ets.update_counter(recent, :seq, {2, 1}, {:seq, 0})
    :ets.insert(recent, {{:slot, rem(seq, @recent_slots)}, seq, entry})

    unless hit? do
      :ets.insert(recent, {{:last, upstream}, if(failed?, do: :failed, else: :ok), now})
      unless failed?, do: :ets.insert(recent, {{:last_success, upstream}, now})
    end

    :ok
  rescue
    error ->
      MediaCentaur.Log.warning(:system, "http traffic not recorded",
        reason: Exception.message(error)
      )

      :ok
  end

  # --- GenServer ---

  @impl true
  def init(opts) do
    recent_table = Keyword.get(opts, :recent_table, @recent_table)
    store_table = Keyword.get(opts, :store_table, @store_table)

    ^recent_table =
      :ets.new(recent_table, [:set, :public, :named_table, write_concurrency: true])

    handler_id =
      if Keyword.get(opts, :attach, true) do
        handler_id = "http-traffic-#{inspect(Keyword.get(opts, :name, __MODULE__))}"
        :telemetry.detach(handler_id)

        :telemetry.attach(handler_id, Instrument.stop_event(), &__MODULE__.handle_telemetry/4, %{
          store: store_table,
          recent: recent_table
        })

        handler_id
      end

    {:ok, %{handler_id: handler_id}}
  end

  @impl true
  def terminate(_reason, %{handler_id: handler_id}) do
    if handler_id, do: :telemetry.detach(handler_id)
    :ok
  end

  # --- Internals ---

  defp lookup(table, key) do
    case :ets.whereis(table) do
      :undefined -> []
      _tid -> :ets.lookup(table, key)
    end
  end

  defp mean(_sum, 0), do: nil
  defp mean(sum, requests), do: div(sum, requests)

  defp worst(_max, 0), do: nil
  defp worst(max, _requests), do: max

  defp totals_from(%{requests: requests} = totals) do
    %{
      requests: requests,
      failed: totals.failed,
      cached: totals.cached,
      mean_ms: mean(totals.latency_sum_ms, requests),
      worst_ms: worst(totals.latency_max_ms, requests)
    }
  end
end
```

`Exception.message/1` on `metadata.error` mirrors `Stats`; `metadata.error` is an exception struct or nil.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/http_client/traffic_test.exs`
Expected: 8 tests, 0 failures. `HttpClient`'s Boundary does not yet list `TimeSeries`, so expect a Boundary compile error first: in `lib/media_centaur/http_client.ex` change the `use Boundary` to
`deps: [MediaCentaur.ErrorReports, MediaCentaur.IntegrationAvailability, MediaCentaur.TimeSeries]` and add `Traffic` to `exports` (keep `Stats` in exports until Task 7 deletes it).

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/http_client/traffic.ex lib/media_centaur/http_client.ex test/media_centaur/http_client/traffic_test.exs
git commit -m "feat(http_client): Traffic, the request time series tenant

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 6: IncidentContext reads Traffic

**Files:**
- Modify: `lib/media_centaur/http_client/incident_context.ex`
- Modify: `test/media_centaur/http_client/incident_context_test.exs`

- [ ] **Step 1: Rewrite the tests' fixture**

Open `test/media_centaur/http_client/incident_context_test.exs`. Every use of `Stats.empty_snapshot()` and of `%{upstreams: rows}` becomes a totals map keyed by upstream: `assess/3` now takes `%{upstream => Traffic.totals()}`. Replace the `alias …{IncidentContext, Stats}` with `alias MediaCentaur.HttpClient.IncidentContext`, and write the share fixtures as

```elixir
@zero %{requests: 0, failed: 0, cached: 0, mean_ms: nil, worst_ms: nil}

defp totals(overrides), do: Map.new(overrides, fn {id, t} -> {id, Map.merge(@zero, t)} end)

test "most image requests failing is a warning fault" do
  totals = totals(tmdb_images: %{requests: 12, failed: 7})
  assert {:fault, :upstream_failing, :warning, %{upstream: :tmdb_images}} =
           IncidentContext.assess(totals, up(), now())
end

test "under ten image requests is never graded by share" do
  assert :ok = IncidentContext.assess(totals(tmdb_images: %{requests: 9, failed: 9}), up(), now())
end
```

Keep every existing `unavailable` test unchanged apart from the first argument. Add:

```elixir
test "vitals report window figures per upstream" do
  vitals = IncidentContext.vitals()
  assert %{"upstreams" => upstreams, "cache_entries" => _} = vitals
  assert %{"window_requests" => 0, "window_failed" => 0, "mean_latency_ms" => nil, "worst_latency_ms" => nil} = upstreams["tmdb"]
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/http_client/incident_context_test.exs`
Expected: failures on the new shapes.

- [ ] **Step 3: Change IncidentContext**

Replace the `Stats` alias with `Traffic`, and:

```elixir
@impl true
def assess do
  assess(share_totals(), IntegrationAvailability.status(:tmdb), DateTime.utc_now())
end

@spec assess(%{atom() => Traffic.totals()}, Status.t(), DateTime.t()) :: :ok | fault()
def assess(totals_by_upstream, %Status{} = tmdb_status, %DateTime{} = now) do
  unavailable(tmdb_status, now) || failing_share(totals_by_upstream)
end

defp share_totals, do: Map.new(@assessed_by_share, &{&1, Traffic.totals(&1, seconds: 900)})

defp failing_share(totals_by_upstream) do
  @assessed_by_share
  |> Enum.map(&{&1, Map.get(totals_by_upstream, &1, %{requests: 0, failed: 0})})
  |> Enum.filter(fn {_id, t} -> t.requests >= @min_requests end)
  |> Enum.map(fn {id, t} -> {id, t.failed / t.requests} end)
  |> Enum.filter(fn {_id, share} -> share >= @failing_share end)
  |> Enum.max_by(fn {_id, share} -> share end, fn -> nil end)
  |> case do
    nil -> :ok
    {id, _share} ->
      {:fault, :upstream_failing, :warning,
       %{upstream: id, headline: "Most requests to #{Upstream.label(id)} are failing"}}
  end
end

@impl true
def vitals do
  %{
    "upstreams" =>
      Map.new(Upstream.ids(), fn id ->
        totals = Traffic.totals(id, seconds: 900)

        {to_string(id),
         %{
           "window_requests" => totals.requests,
           "window_failed" => totals.failed,
           "window_cached" => totals.cached,
           "mean_latency_ms" => totals.mean_ms,
           "worst_latency_ms" => totals.worst_ms
         }}
      end),
    "cache_entries" => Cache.stats().entries
  }
end
```

Update the moduledoc sentence that mentions `Stats` to name `Traffic.totals/2` over the last fifteen minutes.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/http_client/incident_context_test.exs`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/http_client/incident_context.ex test/media_centaur/http_client/incident_context_test.exs
git commit -m "refactor(http_client): incident assessor reads Traffic totals

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 7: Wire the supervisor, retire Stats, retention entry, datastore figure

**Files:**
- Modify: `lib/media_centaur/http_client/supervisor.ex`
- Modify: `lib/media_centaur/application.ex:87,211-212`
- Modify: `lib/media_centaur/http_client.ex:2-5` (drop `Stats` from exports)
- Modify: `lib/media_centaur/http_client/instrument.ex:31`
- Delete: `lib/media_centaur/http_client/stats.ex`, `test/media_centaur/http_client/stats_test.exs`
- Create: `lib/media_centaur/http_client/retention_policies.ex`
- Modify: `lib/media_centaur/retention/policy.ex:18-27` (add `:http` to the subsystem list)
- Modify: `config/config.exs:146-155`
- Modify: `lib/media_centaur/runtime/vitals.ex`, `lib/media_centaur_web/components/status_widgets/system.ex:81-87`
- Modify: `test/support/global_state_sandbox.ex:126-127`
- Modify: `docs/architecture.md:137`
- Test: `test/media_centaur/http_client/retention_policies_test.exs`, `test/media_centaur/runtime/vitals_test.exs` (extend if it exists, else create)

- [ ] **Step 1: Failing tests**

`test/media_centaur/http_client/retention_policies_test.exs`:

```elixir
defmodule MediaCentaur.HttpClient.RetentionPoliciesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.HttpClient.RetentionPolicies
  alias MediaCentaur.Retention.Policy

  test "declares the request-history policy on the Connections subsystem" do
    assert [%Policy{key: :request_history, subsystem: :http, mode: :external, run: nil}] =
             RetentionPolicies.policies()
  end
end
```

Vitals: add to the existing vitals test (or create `test/media_centaur/runtime/vitals_test.exs` with `use MediaCentaur.DataCase, async: false`):

```elixir
test "datastore figures include time-series snapshot bytes" do
  assert %{db: %{size_bytes: _, wal_bytes: _, time_series_bytes: bytes}} = Vitals.snapshot()
  assert is_integer(bytes) and bytes >= 0
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/http_client/retention_policies_test.exs test/media_centaur/runtime/vitals_test.exs`

- [ ] **Step 3: Supervisor and application**

`lib/media_centaur/http_client/supervisor.ex`:

```elixir
defmodule MediaCentaur.HttpClient.Supervisor do
  @moduledoc """
  Supervises the HTTP layer's stateful pieces: the response-cache
  coordinator, the request time-series store and `Traffic`, which feeds it.

  Started before any context that builds clients, in dev and prod only;
  under `:test` the seam runs uncached and unrecorded so `Req.Test`
  stubs never share state across tests, and `Traffic`'s reads return
  empty values.

  `snapshot_dir:` is where the store keeps `traffic.snapshot`; the
  application passes the database's directory.
  """
  use Supervisor

  alias MediaCentaur.HttpClient.Traffic
  alias MediaCentaur.TimeSeries.Store

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    snapshot_path =
      case Keyword.get(opts, :snapshot_dir) do
        nil -> nil
        dir -> Path.join(dir, "traffic.snapshot")
      end

    children = [
      MediaCentaur.HttpClient.Cache.Coordinator,
      {Store,
       name: Traffic.Store,
       table: Traffic.store_table(),
       schema: Traffic.schema(),
       snapshot_path: snapshot_path,
       retention_policy: :request_history},
      Traffic
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

`lib/media_centaur/application.ex`: change the helper to pass the directory —

```elixir
defp http_client_children(:test), do: []

defp http_client_children(_env) do
  snapshot_dir =
    case MediaCentaur.Settings.Config.get(:database_path) do
      nil -> nil
      path -> Path.dirname(path)
    end

  [{MediaCentaur.HttpClient.Supervisor, snapshot_dir: snapshot_dir}]
end
```

`MediaCentaur.Settings` is already in the application's Boundary deps. Confirm `Settings.Config.get(:database_path)` is the accessor `Runtime.Vitals` uses (it is, `vitals.ex:50`).

`lib/media_centaur/http_client.ex`: exports become `[Cache, Cache.Coordinator, IncidentContext, Instrument, Supervisor, Traffic, Upstream]`.

`lib/media_centaur/http_client/instrument.ex:31`: replace the sentence naming `Stats` with "`MediaCentaur.HttpClient.Traffic` counts it into the request time series behind the Connections strip charts."

Delete `lib/media_centaur/http_client/stats.ex` and `test/media_centaur/http_client/stats_test.exs`.

- [ ] **Step 4: Retention policy**

`lib/media_centaur/http_client/retention_policies.ex`:

```elixir
defmodule MediaCentaur.HttpClient.RetentionPolicies do
  @moduledoc """
  Retention policy owned by the HTTP layer: the request time series
  (`MediaCentaur.HttpClient.Traffic`) is a round-robin store whose own
  sweep removes rows past each resolution's retention once a minute and
  reports the count under `:request_history`.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.Retention.Policy

  @impl true
  def policies do
    [
      %Policy{
        key: :request_history,
        subsystem: :http,
        label: "Request history",
        description:
          "Ten-second buckets for an hour, minute buckets for six hours, ten-minute buckets for two days, hourly buckets for 31 days; swept continuously.",
        mode: :external
      }
    ]
  end
end
```

`lib/media_centaur/retention/policy.ex`: add `:http` to the documented subsystem list (lines 18-27) with the note "(`:http` is the Connections drill-in)". `config/config.exs`: add `MediaCentaur.HttpClient.RetentionPolicies` after `MediaCentaur.ErrorReports.RetentionPolicies` in `:retention_policy_providers`. `HttpClient`'s Boundary needs `MediaCentaur.Retention` in `deps` for the behaviour; add it.

- [ ] **Step 5: Vitals**

In `lib/media_centaur/runtime/vitals.ex` extend `db_sizes/0`:

```elixir
defp db_sizes do
  path = MediaCentaur.Settings.Config.get(:database_path)

  %{
    size_bytes: file_size(path),
    wal_bytes: file_size(wal_path(path)),
    time_series_bytes: time_series_bytes(path)
  }
end

defp time_series_bytes(nil), do: 0

defp time_series_bytes(path) do
  path
  |> Path.dirname()
  |> Path.join("*.snapshot")
  |> Path.wildcard()
  |> Enum.map(&file_size/1)
  |> Enum.sum()
end
```

Update the moduledoc's shape line to include `time_series_bytes`. In `status_widgets/system.ex`, after the WAL row (line 87) add a sibling row:

```heex
<div class="flex items-baseline gap-2">
  <span class="text-base-content/55">Request history</span>
  <span class="tabular-nums text-base-content/80">
    {format_bytes_iec(@system_vitals.db.time_series_bytes)}
  </span>
</div>
```

Update `storybook/status/system_widget.story.exs` fixtures to carry `time_series_bytes` (the story renders with the vitals map; a missing key crashes the render test).

- [ ] **Step 6: Sandbox text and architecture diagram**

`test/support/global_state_sandbox.ex:126-127`: text becomes `"response cache and request traffic are not started under :test"`. `docs/architecture.md:137`: `HttpSup[HttpClient.Supervisor<br/>Cache.Coordinator + TimeSeries.Store + Traffic]`.

- [ ] **Step 7: Compile, run the touched tests and the sandbox inventory**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors && ~/scripts/agents/agent-mix test test/media_centaur/http_client test/media_centaur/runtime test/media_centaur/global_state_sandbox_test.exs test/media_centaur/retention`
Expected: pass. Grep `Stats` under `lib/ test/ storybook/` — only the storybook `http_widget.story.exs` may still reference it (Task 16 rewrites it; until then the storybook compile test fails, which is expected between Tasks 7 and 16 — do Tasks 7 through 16 in one sitting, or temporarily point the story's alias at nothing by replacing its fixtures with `%{}` maps).

- [ ] **Step 8: Commit**

```bash
git add -A lib/media_centaur config/config.exs test/support/global_state_sandbox.ex docs/architecture.md test/media_centaur lib/media_centaur_web/components/status_widgets/system.ex storybook/status/system_widget.story.exs
git commit -m "feat(http_client): start the traffic store; retire Stats; retention entry; datastore figure

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 8: Vendor uPlot and add the chart CSS

**Files:**
- Create: `assets/vendor/uplot.js`
- Modify: `assets/css/app.css` (after the `@property` block ending at line 184, and a new component block near `.segmented-control`)

- [ ] **Step 1: Vendor the library**

```bash
curl -fsSL https://raw.githubusercontent.com/leeoniya/uPlot/1.6.32/dist/uPlot.esm.js -o assets/vendor/uplot.js
head -3 assets/vendor/uplot.js
```

Expected: the file begins with the uPlot license banner naming version 1.6.32. If the banner lacks the version, prepend `/*! uPlot 1.6.32 — https://github.com/leeoniya/uPlot — MIT */`.

- [ ] **Step 2: Registered color tokens**

After line 184 of `assets/css/app.css` (the last `@property`), add:

```css
/* Strip chart palette — registered as <color> so getComputedStyle hands the
   StripChart hook resolved colors a canvas accepts. Defined from theme
   tokens below; never read --color-* from JS directly. */
@property --strip-chart-bar-error { syntax: "<color>"; inherits: true; initial-value: transparent; }
@property --strip-chart-bar-solid { syntax: "<color>"; inherits: true; initial-value: transparent; }
@property --strip-chart-bar-muted { syntax: "<color>"; inherits: true; initial-value: transparent; }
@property --strip-chart-line { syntax: "<color>"; inherits: true; initial-value: transparent; }
@property --strip-chart-grid { syntax: "<color>"; inherits: true; initial-value: transparent; }
@property --strip-chart-axis-text { syntax: "<color>"; inherits: true; initial-value: transparent; }
@property --strip-chart-cursor { syntax: "<color>"; inherits: true; initial-value: transparent; }

:root {
  --strip-chart-bar-error: oklch(from var(--color-error) l c h / 0.95);
  --strip-chart-bar-solid: oklch(from var(--color-base-content) l c h / 0.42);
  --strip-chart-bar-muted: oklch(from var(--color-base-content) l c h / 0.14);
  --strip-chart-line: oklch(from var(--color-primary) l c h / 0.9);
  --strip-chart-grid: oklch(from var(--color-base-content) l c h / 0.07);
  --strip-chart-axis-text: oklch(from var(--color-base-content) l c h / 0.4);
  --strip-chart-cursor: oklch(from var(--color-base-content) l c h / 0.35);
}
```

- [ ] **Step 3: Component and uPlot base styles**

Add a block after the `.segmented-control` rules:

```css
/* Strip chart (UIDR pending) — six strips, one window, one cursor.
   Rows and canvases are owned by the StripChart hook (phx-update="ignore"). */
@layer components {
  .strip-chart-strips { display: flex; flex-direction: column; }
  .strip-chart-strip {
    display: grid;
    grid-template-columns: 11.5rem minmax(0, 1fr);
    gap: 1rem;
    align-items: center;
    padding: 0.625rem 0 0.5rem;
    border-top: 1px solid var(--strip-chart-grid);
  }
  .strip-chart-strip:first-child { border-top: 0; padding-top: 0.25rem; }
  .strip-chart-name {
    display: flex; align-items: center; gap: 0.5rem;
    font-size: 0.8125rem; color: oklch(from var(--color-base-content) l c h / 0.8);
  }
  .strip-chart-dot { width: 6px; height: 6px; border-radius: 9999px; background: oklch(from var(--color-base-content) l c h / 0.3); }
  .strip-chart-dot[data-dot="ok"] { background: var(--color-success); }
  .strip-chart-dot[data-dot="failed"] { background: var(--color-error); }
  .strip-chart-time { margin-left: auto; font-size: 0.6875rem; color: oklch(from var(--color-base-content) l c h / 0.4); }
  .strip-chart-figures {
    margin-top: 0.1875rem; font-size: 0.75rem; line-height: 1.5;
    color: oklch(from var(--color-base-content) l c h / 0.55);
    font-variant-numeric: tabular-nums;
  }
  .strip-chart-figures [data-tone="error"] { color: var(--color-error); }
  .strip-chart-figures [data-tone="warning"] { color: var(--color-warning); }
  .strip-chart-figures .strip-chart-sep { opacity: 0.45; }
  .strip-chart-plot { min-width: 0; }
  .strip-chart-footer {
    display: flex; justify-content: space-between; align-items: center; gap: 1rem;
    margin-top: 0.75rem; padding-top: 0.625rem; border-top: 1px solid var(--strip-chart-grid);
  }
  .strip-chart-legend { display: flex; gap: 0.875rem; font-size: 0.6875rem; color: oklch(from var(--color-base-content) l c h / 0.55); }
  .strip-chart-legend li { display: inline-flex; align-items: center; gap: 0.3125rem; }
  .strip-chart-swatch { display: inline-block; width: 9px; height: 9px; border-radius: 2px; }
  .strip-chart-swatch-error { background: var(--strip-chart-bar-error); }
  .strip-chart-swatch-solid { background: var(--strip-chart-bar-solid); }
  .strip-chart-swatch-muted { background: var(--strip-chart-bar-muted); }
  .strip-chart-swatch-line { width: 12px; height: 0; border-top: 2px solid var(--strip-chart-line); border-radius: 0; }

  /* uPlot base (from uPlot.min.css, 1.6.32), scoped and recolored. Legend and
     title styles are omitted: the hook renders neither. */
  .strip-chart .uplot, .strip-chart .uplot *, .strip-chart .uplot *::before, .strip-chart .uplot *::after { box-sizing: border-box; }
  .strip-chart .uplot { font-family: inherit; line-height: 1.5; width: min-content; }
  .strip-chart .u-wrap { position: relative; user-select: none; }
  .strip-chart .u-over, .strip-chart .u-under { position: absolute; }
  .strip-chart .u-under { overflow: hidden; }
  .strip-chart .uplot canvas { display: block; position: relative; width: 100%; height: 100%; }
  .strip-chart .u-axis { position: absolute; }
  .strip-chart .u-cursor-x, .strip-chart .u-cursor-y { position: absolute; left: 0; top: 0; pointer-events: none; will-change: transform; z-index: 100; }
  .strip-chart .u-hz .u-cursor-x { height: 100%; border-right: 1px dashed var(--strip-chart-cursor); }
  .strip-chart .u-hz .u-cursor-y { width: 100%; border-bottom: 1px dashed var(--strip-chart-cursor); }
  .strip-chart .u-cursor-pt { position: absolute; top: 0; left: 0; border-radius: 50%; border: 0 solid; pointer-events: none; will-change: transform; z-index: 100; background-clip: padding-box !important; }
  .strip-chart .u-axis.u-off, .strip-chart .u-select.u-off, .strip-chart .u-cursor-x.u-off, .strip-chart .u-cursor-y.u-off, .strip-chart .u-cursor-pt.u-off { display: none; }
  .strip-chart .u-select { background: oklch(0% 0 0 / 0.07); position: absolute; pointer-events: none; }
  .strip-chart .u-legend { display: none; }
}
```

- [ ] **Step 4: Build assets to confirm the CSS compiles**

Run: `~/scripts/agents/agent-mix assets.build`
Expected: no Tailwind errors. (Dev asset watchers are off; this is also what makes the change visible on the running dev server.)

- [ ] **Step 5: Commit**

```bash
git add assets/vendor/uplot.js assets/css/app.css
git commit -m "feat(assets): vendor uPlot 1.6.32; strip chart tokens and styles

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 9: StripChart component and story (Fable subagent)

**Files:**
- Create: `lib/media_centaur_web/components/strip_chart.ex`
- Create: `storybook/composites/strip_chart.story.exs`
- Modify: `storybook/composites/_composites.index.exs` (add `entry("strip_chart")`)

- [ ] **Step 1: Write the story first**

```elixir
defmodule MediaCentaurWeb.Storybook.Composites.StripChart do
  @moduledoc """
  Shell of the strip chart: card header, the window control on the house
  segmented pill, legend and footer slot. The strips themselves render
  from frames pushed to the `StripChart` hook under a live socket
  (`MediaCentaurWeb.Components.StripChart.Feed`); in isolation the hook
  container is empty, and the `phx-hook` / `phx-update="ignore"` wiring
  plus the pills' `aria-pressed` are the contract the story locks.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.StripChart.strip_chart/1
  def render_source, do: :function
  def layout, do: :one_column

  @legend [
    %{label: "failed", tone: "error"},
    %{label: "went out", tone: "solid"},
    %{label: "from cache", tone: "muted"},
    %{label: "mean latency", tone: "line"}
  ]

  def variations do
    [
      %Variation{
        id: :default_window,
        description: "Default 1h window, four-item legend, no footer",
        attributes: %{
          id: "story-traffic",
          title: "Requests",
          lede: "Requests are what went out; cache is what was answered here instead.",
          window: :"1h",
          windows: [:"5m", :"1h", :"5h", :"1d", :"1w", :"1mo"],
          legend: @legend
        }
      },
      %Variation{
        id: :month_with_footer,
        description: "1mo selected, footer slot filled",
        attributes: %{
          id: "story-traffic-month",
          title: "Requests",
          window: :"1mo",
          legend: @legend
        },
        slots: [
          """
          <:footer><span class="text-xs text-base-content/55">Recent requests ▸</span></:footer>
          """
        ]
      }
    ]
  end
end
```

- [ ] **Step 2: Write the component**

```elixir
defmodule MediaCentaurWeb.Components.StripChart do
  @moduledoc """
  The strip chart: N strips sharing one window, one time axis and one
  synced cursor, for any tenant with a time series to show.

  This component renders the shell — card header, the window control on
  the house segmented pill, legend, footer slot — and one element that
  carries `phx-hook="StripChart"` and `phx-update="ignore"`. The hook
  owns everything inside that element (rows, name columns, figures,
  canvases) and changes it only when a frame arrives; LiveView never
  patches it. Frames come from `MediaCentaurWeb.Components.StripChart.Feed`,
  whose moduledoc carries the frame contract.

  The pills push `strip_chart:window` with `phx-value-id` and
  `phx-value-window`; the feed handles that event and patches the URL.

  Story: `/storybook/composites/strip_chart`.
  """
  use MediaCentaurWeb, :html

  alias MediaCentaur.TimeSeries.Window

  @doc "Strip chart shell. The strips render from pushed frames."
  attr :id, :string, required: true, doc: "hook element id and the feed key"
  attr :title, :string, required: true
  attr :lede, :string, default: nil
  attr :window, :atom, required: true, values: Window.all()
  attr :windows, :list, default: Window.all(), doc: "the windows offered, in order"
  attr :legend, :list, default: [], doc: "%{label, tone} with tone in error | solid | muted | line"
  slot :footer, doc: "tenant content beside the legend"

  def strip_chart(assigns) do
    ~H"""
    <div class="card glass-inset strip-chart" data-testid={"strip-chart-#{@id}"}>
      <div class="card-body">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 class="card-title text-lg">{@title}</h2>
            <p :if={@lede} class="text-xs text-base-content/55">{@lede}</p>
          </div>
          <div class="tabs tabs-boxed segmented-control w-fit shrink-0" role="group" aria-label="Window">
            <button
              :for={window <- @windows}
              type="button"
              class={["tab cursor-pointer", window == @window && "tab-active"]}
              aria-pressed={to_string(window == @window)}
              phx-click="strip_chart:window"
              phx-value-id={@id}
              phx-value-window={window}
            >
              {window}
            </button>
          </div>
        </div>

        <div id={@id} phx-hook="StripChart" phx-update="ignore" class="strip-chart-strips" data-window={@window}>
        </div>

        <div class="strip-chart-footer">
          <ul class="strip-chart-legend">
            <li :for={item <- @legend}>
              <span class={"strip-chart-swatch strip-chart-swatch-#{item.tone}"}></span>{item.label}
            </li>
          </ul>
          {render_slot(@footer)}
        </div>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 3: Index entry**

In `storybook/composites/_composites.index.exs` add `def entry("strip_chart"), do: [icon: {:hero, "chart-bar"}, name: "Strip chart"]` beside the existing entries.

- [ ] **Step 4: Run the storybook tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: pass, including the new story. Open `http://localhost:2160/storybook/composites/strip_chart` on the dev server and confirm the pill and legend render.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/strip_chart.ex storybook/composites/
git commit -m "feat(web): StripChart shell component and story

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 10: StripChart.Feed

**Files:**
- Create: `lib/media_centaur_web/components/strip_chart/feed.ex`
- Modify: `config/test.exs` (add `config :media_centaur, :strip_chart_tick_ms, 50`)
- Test: `test/media_centaur_web/components/strip_chart/feed_test.exs` (pure helpers)

- [ ] **Step 1: Failing pure test**

```elixir
defmodule MediaCentaurWeb.Components.StripChart.FeedTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.StripChart.Feed

  test "with_window replaces or adds the window query parameter" do
    assert Feed.with_window("http://localhost/status?subsystem=http", :"5h") ==
             "/status?subsystem=http&window=5h"

    assert Feed.with_window("http://localhost/status?subsystem=http&window=1h", :"1mo") ==
             "/status?subsystem=http&window=1mo"
  end

  test "window_from_params falls back to the default" do
    assert Feed.window_from_params(%{"window" => "1w"}, :"1h") == :"1w"
    assert Feed.window_from_params(%{"window" => "2h"}, :"1h") == :"1h"
    assert Feed.window_from_params(%{}, :"1h") == :"1h"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/strip_chart/feed_test.exs`

- [ ] **Step 3: Write the Feed**

```elixir
defmodule MediaCentaurWeb.Components.StripChart.Feed do
  @moduledoc """
  The LiveView side of a strip chart: the window in the URL, one frame
  the moment the chart becomes active, a frame every ten seconds while it
  stays active and the tab is visible, nothing otherwise.

  A tenant attaches in `mount/3`:

      socket =
        Feed.attach(socket,
          id: "traffic",
          frame: &TrafficFrame.build/1,
          active?: &(&1["subsystem"] == "http")
        )

  and renders `<.strip_chart id="traffic" window={Feed.window(assigns, "traffic")} …>`.

  `frame` receives the window and returns the frame map; `active?`
  receives the URL params (it runs in a `handle_params` hook, before the
  tenant's own callback) and says whether the chart is on screen.

  ## Frame

  Pushed as `strip_chart:frame`. Columnar, fixed length per strip,
  zero-filled; `mean_ms`/`worst_ms` are `nil` in bars without requests.

      %{
        id: "traffic", window: "1h", bucket_seconds: 60,
        schema: %{
          bars: [%{key: "failed", label: "failed", tone: "error"},
                 %{key: "went_out", label: "went out", tone: "solid"},
                 %{key: "cached", label: "from cache", tone: "muted"}],
          bars_total_label: "requests",
          line: %{key: "mean_ms", worst_key: "worst_ms", label: "mean latency", unit: "ms"}
        },
        strips: [
          %{id: "tmdb", label: "TMDB", dot: "ok",
            figures: [[%{text: "189 requests"}, %{text: "5 failed", tone: "error"}], …],
            t: [unix, …], failed: [...], went_out: [...], cached: [...],
            mean_ms: [...], worst_ms: [...]}
        ]
      }

  `schema.line` may be omitted. Bars are drawn back to front in the
  order given, each as a full-height series from the baseline, so the
  hook stacks them with two additions per bar and no cumulative
  bookkeeping here.

  ## Events from the hook

  `strip_chart:visibility` `%{"id", "visible"}` on `visibilitychange`;
  `strip_chart:window` `%{"id", "window"}` from the pills. Both are
  handled here and halted.

  The tick interval is `:strip_chart_tick_ms` in the application env
  (10 s; the test config shortens it).
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, push_event: 3, push_patch: 2]

  alias MediaCentaur.TimeSeries.Window

  defmodule State do
    @moduledoc false
    @enforce_keys [:id, :window, :frame, :active?]
    defstruct [:id, :window, :frame, :active?, :uri, :timer, active: false, visible?: true]
  end

  @assign :strip_chart_feeds

  @spec attach(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def attach(socket, opts) do
    id = Keyword.fetch!(opts, :id)

    state = %State{
      id: id,
      window: Keyword.get(opts, :default_window, :"1h"),
      frame: Keyword.fetch!(opts, :frame),
      active?: Keyword.fetch!(opts, :active?)
    }

    socket
    |> put(state)
    |> attach_hook({:strip_chart_params, id}, :handle_params, &on_params(&1, &2, &3, id))
    |> attach_hook({:strip_chart_event, id}, :handle_event, &on_event(&1, &2, &3, id))
    |> attach_hook({:strip_chart_info, id}, :handle_info, &on_info(&1, &2, id))
  end

  @doc "The current window of the feed `id`, from assigns."
  @spec window(map(), String.t()) :: Window.t()
  def window(assigns, id), do: Map.fetch!(assigns[@assign], id).window

  @doc "Parses `window` from params, falling back to `default`."
  @spec window_from_params(map(), Window.t()) :: Window.t()
  def window_from_params(params, default) do
    case Window.parse(params["window"]) do
      {:ok, window} -> window
      :error -> default
    end
  end

  @doc "The request path of `uri` with `window` set in its query."
  @spec with_window(String.t(), Window.t()) :: String.t()
  def with_window(uri, window) do
    parsed = URI.parse(uri)

    query =
      (parsed.query || "")
      |> URI.decode_query()
      |> Map.put("window", Atom.to_string(window))
      |> URI.encode_query()

    "#{parsed.path}?#{query}"
  end

  # --- hooks ---

  defp on_params(params, uri, socket, id) do
    state = fetch(socket, id)
    active = state.active?.(params)
    window = window_from_params(params, :"1h")
    state = %{state | uri: uri, active: active, window: window}
    {:cont, socket |> put(state) |> resync(id)}
  end

  defp on_event("strip_chart:window", %{"id" => id, "window" => label}, socket, id) do
    state = fetch(socket, id)

    case Window.parse(label) do
      {:ok, window} -> {:halt, push_patch(socket, to: with_window(state.uri, window))}
      :error -> {:halt, socket}
    end
  end

  defp on_event("strip_chart:visibility", %{"id" => id, "visible" => visible}, socket, id) do
    state = %{fetch(socket, id) | visible?: visible == true}
    {:halt, socket |> put(state) |> resync(id)}
  end

  defp on_event(_event, _params, socket, _id), do: {:cont, socket}

  defp on_info({:strip_chart_tick, id}, socket, id) do
    socket = put(socket, %{fetch(socket, id) | timer: nil})
    {:halt, resync(socket, id)}
  end

  defp on_info(_message, socket, _id), do: {:cont, socket}

  # Push a frame and (re)arm when the chart is active, visible and connected;
  # otherwise make sure no timer is pending.
  defp resync(socket, id) do
    state = fetch(socket, id)
    socket = cancel(socket, state)

    if state.active and state.visible? and connected?(socket) do
      frame = state.window |> state.frame.() |> Map.put(:id, id)
      timer = Process.send_after(self(), {:strip_chart_tick, id}, tick_ms())

      socket
      |> push_event("strip_chart:frame", frame)
      |> put(%{fetch(socket, id) | timer: timer})
    else
      socket
    end
  end

  defp cancel(socket, %State{timer: nil}), do: socket

  defp cancel(socket, %State{timer: timer} = state) do
    Process.cancel_timer(timer)
    put(socket, %{state | timer: nil})
  end

  defp tick_ms, do: Application.get_env(:media_centaur, :strip_chart_tick_ms, 10_000)

  defp fetch(socket, id), do: Map.fetch!(socket.assigns[@assign] || %{}, id)

  defp put(socket, %State{id: id} = state) do
    feeds = Map.put(socket.assigns[@assign] || %{}, id, state)
    assign(socket, @assign, feeds)
  end
end
```

`config/test.exs`: add `config :media_centaur, :strip_chart_tick_ms, 50`.

- [ ] **Step 4: Run the tests and compile**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/strip_chart/feed_test.exs && ~/scripts/agents/agent-mix compile --warnings-as-errors`
Expected: pass. The Feed has no function components, so MC0009 does not ask for a story; if the check flags the module anyway, add `@storybook_status :skip` with reason "LiveView lifecycle helper; renders nothing".

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/strip_chart/feed.ex config/test.exs test/media_centaur_web/components/strip_chart/feed_test.exs
git commit -m "feat(web): StripChart.Feed — window param, tick, visibility

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 11: TrafficFrame

**Files:**
- Create: `lib/media_centaur_web/live/status_live/traffic_frame.ex`
- Test: `test/media_centaur_web/live/status_live/traffic_frame_test.exs`

- [ ] **Step 1: Failing test**

```elixir
defmodule MediaCentaurWeb.StatusLive.TrafficFrameTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.StatusLive.TrafficFrame

  @now ~U[2026-09-19 13:26:17Z]

  defp series(overrides) do
    Map.merge(
      %{
        window: :"1h",
        bar_seconds: 60,
        starts: [1, 2],
        went_out: [0, 0],
        failed: [0, 0],
        cached: [0, 0],
        mean_ms: [nil, nil],
        worst_ms: [nil, nil],
        totals: %{requests: 0, failed: 0, cached: 0, mean_ms: nil, worst_ms: nil}
      },
      overrides
    )
  end

  defp build(overrides) do
    TrafficFrame.build(
      :"1h",
      Keyword.merge(
        [
          now: @now,
          configured: %{prowlarr: true, download_client: true, usenet_download_client: false},
          series: fn _upstream, _window -> series(%{}) end,
          last: fn _upstream -> nil end,
          last_success_at: fn _upstream -> nil end,
          down_since: fn _upstream -> nil end,
          rate_limiter: nil
        ],
        overrides
      )
    )
  end

  test "strips are the always-on upstreams plus the configured ones, in panel order" do
    frame = build([])
    assert Enum.map(frame.strips, & &1.id) == ["tmdb", "tmdb_images", "prowlarr", "qbittorrent", "github"]
    assert frame.window == "1h"
    assert frame.bucket_seconds == 60
    assert Enum.map(frame.schema.bars, & &1.key) == ["failed", "went_out", "cached"]
    assert frame.schema.line.key == "mean_ms"
  end

  test "figures carry window totals with failed toned, cached only when present" do
    totals = %{requests: 189, failed: 5, cached: 577, mean_ms: 279, worst_ms: 1_200}

    frame =
      build(
        series: fn :tmdb, _ -> series(%{totals: totals}); _, _ -> series(%{}) end,
        last_success_at: fn :tmdb -> DateTime.add(@now, -12, :second); _ -> nil end,
        last: fn :tmdb -> %{outcome: :ok, at: @now}; _ -> nil end
      )

    tmdb = Enum.find(frame.strips, &(&1.id == "tmdb"))
    assert tmdb.dot == "ok"

    assert tmdb.figures == [
             [%{text: "189 requests"}, %{text: "5 failed", tone: "error"}],
             [%{text: "577 cached"}, %{text: "279 ms mean"}],
             [%{text: "ok 12 s ago"}]
           ]
  end

  test "a strip with no requests says so" do
    frame = build([])
    github = Enum.find(frame.strips, &(&1.id == "github"))
    assert github.dot == "none"
    assert github.figures == [[%{text: "No requests in this window"}], [%{text: "—"}]]
  end

  test "a down integration reads Down since in warning tone" do
    frame = build(down_since: fn :prowlarr -> ~U[2026-09-19 13:02:00Z]; _ -> nil end)
    prowlarr = Enum.find(frame.strips, &(&1.id == "prowlarr"))
    assert List.last(prowlarr.figures) == [%{text: "Down since 13:02", tone: "warning"}]
  end

  test "TMDB shows the rate-limiter budget when the limiter is running" do
    frame = build(rate_limiter: %{available: 28, total: 30, used: 2})
    tmdb = Enum.find(frame.strips, &(&1.id == "tmdb"))
    assert List.last(tmdb.figures) == [%{text: "28 of 30 slots free"}]
  end

  test "a failed last request colors the dot" do
    frame = build(last: fn :tmdb -> %{outcome: :failed, at: @now}; _ -> nil end)
    assert Enum.find(frame.strips, &(&1.id == "tmdb")).dot == "failed"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/status_live/traffic_frame_test.exs`

- [ ] **Step 3: Write TrafficFrame**

```elixir
defmodule MediaCentaurWeb.StatusLive.TrafficFrame do
  @moduledoc """
  Turns `MediaCentaur.HttpClient.Traffic` series into the strip chart
  frame the Connections drill-in pushes (contract in
  `MediaCentaurWeb.Components.StripChart.Feed`). Pure: every read has an
  injectable option so tests pass functions and fixed times.

  Strip membership: TMDB, TMDB images and GitHub always; Prowlarr and the
  two download clients when configured. Order is `Upstream.panel_ids/0`.
  The dot is the outcome of the upstream's last request. "Down since"
  from `IntegrationAvailability` replaces the last-success line while an
  integration is down. The TMDB strip adds the rate-limiter budget.
  """

  alias MediaCentaur.{Capabilities, IntegrationAvailability}
  alias MediaCentaur.HttpClient.{Traffic, Upstream}
  alias MediaCentaur.TimeSeries.Window

  import MediaCentaurWeb.LiveHelpers, only: [time_ago: 1]

  @schema %{
    bars: [
      %{key: "failed", label: "failed", tone: "error"},
      %{key: "went_out", label: "went out", tone: "solid"},
      %{key: "cached", label: "from cache", tone: "muted"}
    ],
    bars_total_label: "requests",
    line: %{key: "mean_ms", worst_key: "worst_ms", label: "mean latency", unit: "ms"}
  }

  @legend Enum.map(@schema.bars, &%{label: &1.label, tone: &1.tone}) ++
            [%{label: @schema.line.label, tone: "line"}]

  @always [:tmdb, :tmdb_images, :github]

  @doc "The legend items the Connections widget renders."
  @spec legend() :: [map()]
  def legend, do: @legend

  @spec build(Window.t(), keyword()) :: map()
  def build(window, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    configured = Keyword.get_lazy(opts, :configured, &configured/0)
    series = Keyword.get(opts, :series, &Traffic.series/2)
    last = Keyword.get(opts, :last, &Traffic.last/1)
    last_success_at = Keyword.get(opts, :last_success_at, &Traffic.last_success_at/1)
    down_since = Keyword.get(opts, :down_since, &IntegrationAvailability.down_since/1)
    rate_limiter = Keyword.get_lazy(opts, :rate_limiter, &fetch_rate_limiter/0)

    strips =
      for upstream <- strip_ids(configured) do
        s = series.(upstream, window)

        %{
          id: Atom.to_string(upstream),
          label: Upstream.label(upstream),
          dot: dot(last.(upstream)),
          figures:
            figures(upstream, s.totals, last_success_at.(upstream), down_since.(upstream), rate_limiter, now),
          t: s.starts,
          failed: s.failed,
          went_out: s.went_out,
          cached: s.cached,
          mean_ms: s.mean_ms,
          worst_ms: s.worst_ms
        }
      end

    %{
      id: "traffic",
      window: Atom.to_string(window),
      bucket_seconds: Window.bar_seconds(window),
      schema: @schema,
      strips: strips
    }
  end

  @doc "Which upstreams have a strip, in panel order."
  @spec strip_ids(%{atom() => boolean()}) :: [atom()]
  def strip_ids(configured) do
    Enum.filter(Upstream.panel_ids(), fn
      upstream when upstream in @always -> true
      :prowlarr -> configured[:prowlarr]
      :qbittorrent -> configured[:download_client]
      :sabnzbd -> configured[:usenet_download_client]
      _other -> false
    end)
  end

  @doc "Configuration flags the strip membership depends on."
  @spec configured() :: %{atom() => boolean()}
  def configured do
    %{
      prowlarr: Capabilities.configured?(:prowlarr),
      download_client: Capabilities.configured?(:download_client),
      usenet_download_client: Capabilities.configured?(:usenet_download_client)
    }
  end

  defp dot(nil), do: "none"
  defp dot(%{outcome: :ok}), do: "ok"
  defp dot(%{outcome: :failed}), do: "failed"

  defp figures(upstream, totals, last_success, down_since, rate_limiter, now) do
    lines =
      if totals.requests == 0 and totals.cached == 0 do
        [[%{text: "No requests in this window"}]]
      else
        [
          [%{text: "#{fmt(totals.requests)} requests"}, failed(totals.failed)],
          second_line(totals)
        ]
      end

    lines ++ [[last_line(last_success, down_since, now)]] ++ slots(upstream, rate_limiter)
  end

  defp failed(0), do: %{text: "0 failed"}
  defp failed(count), do: %{text: "#{fmt(count)} failed", tone: "error"}

  defp second_line(totals) do
    cached = if totals.cached > 0, do: [%{text: "#{fmt(totals.cached)} cached"}], else: []
    mean = if totals.mean_ms, do: [%{text: "#{duration(totals.mean_ms)} mean"}], else: []

    case cached ++ mean do
      [] -> [%{text: "—"}]
      segments -> segments
    end
  end

  defp last_line(_last_success, %DateTime{} = since, _now),
    do: %{text: "Down since #{Calendar.strftime(since, "%H:%M")}", tone: "warning"}

  defp last_line(nil, nil, _now), do: %{text: "—"}
  defp last_line(%DateTime{} = at, nil, _now), do: %{text: "ok #{time_ago(at)}"}

  defp slots(:tmdb, %{available: available, total: total}),
    do: [[%{text: "#{available} of #{total} slots free"}]]

  defp slots(_upstream, _status), do: []

  defp fmt(n), do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")

  defp duration(ms) when ms >= 1_000, do: "#{Float.round(ms / 1_000, 1)} s"
  defp duration(ms), do: "#{ms} ms"

  defp fetch_rate_limiter do
    MediaCentaur.TMDB.RateLimiter.status()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end
end
```

`time_ago/1` in `LiveHelpers` formats relative to the wall clock; the test passes `last_success_at` 12 s before `@now` but `time_ago` compares against `DateTime.utc_now/0`. Make the test robust: assert the last line's text starts with `"ok "` instead of the exact `"ok 12 s ago"`, or add a `now:` arity to `time_ago` if it already has one (check `live_helpers.ex:126-140`). Prefer the `starts_with?` assertion.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/status_live/traffic_frame_test.exs`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/status_live/traffic_frame.ex test/media_centaur_web/live/status_live/traffic_frame_test.exs
git commit -m "feat(status): TrafficFrame — Traffic series to strip chart frames

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 12: The StripChart hook (Fable subagent)

**Files:**
- Create: `assets/js/hooks/strip_chart.js`
- Create: `assets/js/hooks/strip_chart.test.js`
- Modify: `assets/js/app.js` (import and register `StripChart`)

- [ ] **Step 1: Failing bun tests for the pure helpers**

```js
import { describe, expect, test } from "bun:test"
import {
  stackColumns, hoverFigures, formatDuration, niceMax, integerIncrs, axisValuesFor, pxRatioFor,
} from "./strip_chart"

const schema = {
  bars: [
    { key: "failed", label: "failed", tone: "error" },
    { key: "went_out", label: "went out", tone: "solid" },
    { key: "cached", label: "from cache", tone: "muted" },
  ],
  bars_total_label: "requests",
  line: { key: "mean_ms", worst_key: "worst_ms", label: "mean latency", unit: "ms" },
}

const strip = {
  t: [100, 160], failed: [1, 0], went_out: [2, 3], cached: [4, 0], mean_ms: [180, 90], worst_ms: [400, 90],
}

describe("stackColumns", () => {
  test("returns uPlot data: x, then bars back to front as cumulative heights, then the line", () => {
    expect(stackColumns(schema, strip)).toEqual([
      [100, 160],
      [7, 3],   // cached total = failed + went_out + cached
      [3, 3],   // went_out total = failed + went_out
      [1, 0],   // failed
      [180, 90],
    ])
  })
  test("omits the line when the schema has none", () => {
    expect(stackColumns({ ...schema, line: undefined }, strip)).toHaveLength(4)
  })
})

describe("hoverFigures", () => {
  test("formats the bucket's figures from the columns", () => {
    expect(hoverFigures(schema, strip, 0, "13:26")).toEqual([
      [{ text: "13:26" }],
      [{ text: "7 requests" }, { text: "1 failed", tone: "error" }],
      [{ text: "4 from cache" }, { text: "180 ms mean" }, { text: "400 ms worst" }],
    ])
  })
  test("a bucket without requests has no latency and says 0 failed", () => {
    const quiet = { ...strip, failed: [0], went_out: [0], cached: [0], mean_ms: [null], worst_ms: [null] }
    expect(hoverFigures(schema, quiet, 0, "13:26")).toEqual([
      [{ text: "13:26" }],
      [{ text: "0 requests" }, { text: "0 failed" }],
    ])
  })
})

describe("formatDuration", () => {
  test("ms under a second, seconds above", () => {
    expect(formatDuration(180)).toBe("180 ms")
    expect(formatDuration(1200)).toBe("1.2 s")
    expect(formatDuration(3000)).toBe("3 s")
  })
})

describe("axes", () => {
  test("niceMax rounds up to 1/2/2.5/5/10 steps and never below 1", () => {
    expect(niceMax(0)).toBe(1)
    expect(niceMax(3)).toBe(5)
    expect(niceMax(7)).toBe(10)
    expect(niceMax(23)).toBe(25)
    expect(niceMax(120)).toBe(200)
  })
  test("integer increments only", () => {
    expect(integerIncrs().every(Number.isInteger)).toBe(true)
    expect(integerIncrs().slice(0, 4)).toEqual([1, 2, 5, 10])
  })
  test("clock labels up to a day, day labels for a week and a month", () => {
    expect(axisValuesFor("1h")).toBe("clock")
    expect(axisValuesFor("1d")).toBe("clock")
    expect(axisValuesFor("1w")).toBe("day")
    expect(axisValuesFor("1mo")).toBe("day")
  })
})

describe("pxRatioFor", () => {
  test("device pixel ratio times the UI scale, with sane fallbacks", () => {
    expect(pxRatioFor(2, "1.25")).toBe(2.5)
    expect(pxRatioFor(1, "")).toBe(1)
    expect(pxRatioFor(undefined, "0.8")).toBe(0.8)
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd assets && bun test js/hooks/strip_chart.test.js`
Expected: module not found.

- [ ] **Step 3: Write the hook**

```js
// StripChart — N uPlot strips sharing one window, one time axis and one
// synced cursor, drawn from frames the server pushes (contract in
// MediaCentaurWeb.Components.StripChart.Feed). The hook owns every element
// inside its container (phx-update="ignore"); the server changes them only
// by sending a frame.
//
// Sizing rule: widths are LAYOUT pixels (offsetWidth, never a bounding rect —
// the root runs under CSS zoom) and the canvas pixel ratio is
// devicePixelRatio × --ui-scale, so strips stay crisp at any UI scale.
// No timers, no animation loop: a redraw happens on a frame or a resize.
import uPlot from "../vendor/uplot"

const STRIP_HEIGHT = 72
const X_AXIS_SIZE = 22
const Y_AXIS_SIZE = 36
const LINE_AXIS_SIZE = 46

// --- pure helpers (bun-tested) ---

export function stackColumns(schema, strip) {
  const length = strip.t.length
  const bars = schema.bars
  const data = [strip.t]
  // back to front: the last declared series is the tallest (sum of all)
  for (let outer = bars.length - 1; outer >= 0; outer--) {
    const column = new Array(length)
    for (let i = 0; i < length; i++) {
      let total = 0
      for (let inner = 0; inner <= outer; inner++) total += strip[bars[inner].key][i] || 0
      column[i] = total
    }
    data.push(column)
  }
  if (schema.line) data.push(strip[schema.line.key])
  return data
}

export function formatDuration(ms) {
  if (ms == null) return null
  if (ms < 1000) return `${ms} ms`
  const seconds = Math.round(ms / 100) / 10
  return `${Number.isInteger(seconds) ? seconds.toFixed(0) : seconds.toFixed(1)} s`
}

export function formatCount(n) {
  return n.toLocaleString("en-US")
}

export function hoverFigures(schema, strip, idx, timeLabel) {
  const total = schema.bars.reduce((sum, bar) => sum + (strip[bar.key][idx] || 0), 0)
  const first = [{ text: `${formatCount(total)} ${schema.bars_total_label}` }]
  const second = []
  for (const bar of schema.bars) {
    const value = strip[bar.key][idx] || 0
    if (bar.tone === "error") {
      first.push(value > 0 ? { text: `${formatCount(value)} ${bar.label}`, tone: "error" } : { text: `0 ${bar.label}` })
    } else if (bar.tone === "muted" && value > 0) {
      second.push({ text: `${formatCount(value)} ${bar.label}` })
    }
  }
  if (schema.line) {
    const mean = strip[schema.line.key][idx]
    const worst = schema.line.worst_key ? strip[schema.line.worst_key][idx] : null
    if (mean != null) second.push({ text: `${formatDuration(mean)} mean` })
    if (worst != null) second.push({ text: `${formatDuration(worst)} worst` })
  }
  const lines = [[{ text: timeLabel }], first]
  if (second.length > 0) lines.push(second)
  return lines
}

export function niceMax(value) {
  if (!(value > 0)) return 1
  const power = Math.pow(10, Math.floor(Math.log10(value)))
  for (const step of [1, 2, 2.5, 5, 10]) if (step * power >= value) return step * power
  return 10 * power
}

export function integerIncrs() {
  return [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000]
}

export function axisValuesFor(window) {
  return window === "1w" || window === "1mo" ? "day" : "clock"
}

export function pxRatioFor(devicePixelRatio, uiScaleToken) {
  const dpr = devicePixelRatio > 0 ? devicePixelRatio : 1
  const scale = parseFloat(uiScaleToken)
  return dpr * (scale > 0 ? scale : 1)
}

// --- DOM ---

const DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function clockLabel(unix) {
  const date = new Date(unix * 1000)
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`
}

function dayLabel(unix) {
  const date = new Date(unix * 1000)
  return `${DAY_NAMES[date.getDay()]} ${date.getDate()}`
}

function readTheme() {
  const style = getComputedStyle(document.documentElement)
  const token = (name) => style.getPropertyValue(name).trim()
  return {
    error: token("--strip-chart-bar-error"),
    solid: token("--strip-chart-bar-solid"),
    muted: token("--strip-chart-bar-muted"),
    line: token("--strip-chart-line"),
    grid: token("--strip-chart-grid"),
    axisText: token("--strip-chart-axis-text"),
    uiScale: token("--ui-scale"),
  }
}

function renderFigures(container, lines) {
  container.replaceChildren()
  for (const line of lines) {
    const row = document.createElement("div")
    line.forEach((segment, index) => {
      if (index > 0) {
        const sep = document.createElement("span")
        sep.className = "strip-chart-sep"
        sep.textContent = " · "
        row.appendChild(sep)
      }
      const span = document.createElement("span")
      span.textContent = segment.text
      if (segment.tone) span.dataset.tone = segment.tone
      row.appendChild(span)
    })
    container.appendChild(row)
  }
}

export const StripChart = {
  mounted() {
    this.id = this.el.id
    this.strips = new Map()
    this.frame = null
    this.hoverIdx = null
    this.theme = readTheme()

    this.handleEvent("strip_chart:frame", (frame) => {
      if (frame.id !== this.id) return
      this.applyFrame(frame)
    })

    this.onVisibility = () => this.pushVisibility()
    document.addEventListener("visibilitychange", this.onVisibility)
    if (document.visibilityState === "hidden") this.pushVisibility()

    this.onScale = () => this.updatePxRatio()
    window.addEventListener("phx:ui-scale", this.onScale)

    this.resizePending = false
    this.observer = new ResizeObserver(() => {
      if (this.resizePending) return
      this.resizePending = true
      requestAnimationFrame(() => {
        this.resizePending = false
        this.resizeAll()
      })
    })
    this.observer.observe(this.el)
  },

  destroyed() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("phx:ui-scale", this.onScale)
    this.observer?.disconnect()
    for (const { chart } of this.strips.values()) chart.destroy()
    this.strips.clear()
  },

  pushVisibility() {
    this.pushEvent("strip_chart:visibility", { id: this.id, visible: document.visibilityState === "visible" })
  },

  applyFrame(frame) {
    const ids = frame.strips.map((s) => s.id)
    const current = [...this.strips.keys()]
    const sameSet = ids.length === current.length && ids.every((id, i) => id === current[i])
    const windowChanged = this.frame && this.frame.window !== frame.window
    this.frame = frame
    if (!sameSet || windowChanged) this.rebuild(frame)
    frame.strips.forEach((strip, index) => this.updateStrip(strip, index === frame.strips.length - 1))
  },

  rebuild(frame) {
    for (const { chart } of this.strips.values()) chart.destroy()
    this.strips.clear()
    this.el.replaceChildren()
    frame.strips.forEach((strip, index) => {
      const row = document.createElement("div")
      row.className = "strip-chart-strip"
      row.dataset.strip = strip.id

      const name = document.createElement("div")
      const title = document.createElement("div")
      title.className = "strip-chart-name"
      const dot = document.createElement("span")
      dot.className = "strip-chart-dot"
      const label = document.createElement("span")
      label.textContent = strip.label
      const time = document.createElement("span")
      time.className = "strip-chart-time"
      title.append(dot, label, time)
      const figures = document.createElement("div")
      figures.className = "strip-chart-figures"
      name.append(title, figures)

      const plot = document.createElement("div")
      plot.className = "strip-chart-plot"
      row.append(name, plot)
      this.el.appendChild(row)

      const isLast = index === frame.strips.length - 1
      const chart = new uPlot(this.options(frame, strip, isLast, plot.offsetWidth), stackColumns(frame.schema, strip), plot)
      this.strips.set(strip.id, { chart, dot, time, figures, plot, strip })
    })
  },

  updateStrip(strip, isLast) {
    const entry = this.strips.get(strip.id)
    if (!entry) return
    entry.strip = strip
    entry.dot.dataset.dot = strip.dot
    entry.chart.setData(stackColumns(this.frame.schema, strip))
    if (this.hoverIdx == null) renderFigures(entry.figures, strip.figures)
    else this.renderHover(entry, this.hoverIdx)
    void isLast
  },

  renderHover(entry, idx) {
    const strip = entry.strip
    if (idx == null || idx >= strip.t.length) {
      entry.time.textContent = ""
      renderFigures(entry.figures, strip.figures)
      return
    }
    const labeler = axisValuesFor(this.frame.window) === "day" ? dayLabel : clockLabel
    const lines = hoverFigures(this.frame.schema, strip, idx, labeler(strip.t[idx]))
    entry.time.textContent = lines[0][0].text
    renderFigures(entry.figures, lines.slice(1))
  },

  setHover(idx) {
    if (idx === this.hoverIdx) return
    this.hoverIdx = idx
    for (const entry of this.strips.values()) this.renderHover(entry, idx)
  },

  options(frame, strip, isLast, width) {
    const theme = this.theme
    const schema = frame.schema
    const labeler = axisValuesFor(frame.window) === "day" ? dayLabel : clockLabel
    const barTone = (tone) => theme[tone] || theme.solid
    const barsPath = uPlot.paths.bars({ size: [0.62, 100], align: 0 })

    const series = [{}]
    for (let i = schema.bars.length - 1; i >= 0; i--) {
      const bar = schema.bars[i]
      series.push({ scale: "y", paths: barsPath, fill: barTone(bar.tone), stroke: barTone(bar.tone), width: 0, points: { show: false } })
    }
    if (schema.line) {
      series.push({
        scale: "ms", stroke: theme.line, width: 1.5, spanGaps: false,
        points: { show: (u, seriesIdx, idx0, idx1) => idx1 - idx0 <= 1, size: 4, fill: theme.line },
      })
    }

    const axes = [
      {
        show: isLast, scale: "x", size: X_AXIS_SIZE, gap: 4, stroke: theme.axisText,
        font: "10px system-ui, sans-serif", ticks: { show: false }, grid: { stroke: theme.grid, width: 1 }, space: 60,
        values: (u, splits) => splits.map(labeler),
      },
      {
        scale: "y", size: Y_AXIS_SIZE, gap: 4, stroke: theme.axisText, font: "10px system-ui, sans-serif",
        ticks: { show: false }, grid: { stroke: theme.grid, width: 1 }, incrs: integerIncrs(), space: 28,
        values: (u, splits) => splits.map((v) => (Number.isInteger(v) ? formatCount(v) : "")),
      },
    ]
    const scales = { x: { time: true }, y: { range: (u, min, max) => [0, niceMax(max)] } }
    if (schema.line) {
      axes.push({
        scale: "ms", side: 1, size: LINE_AXIS_SIZE, gap: 4, stroke: theme.line, font: "10px system-ui, sans-serif",
        ticks: { show: false }, grid: { show: false }, space: 28,
        values: (u, splits) => splits.map((v) => (v === 0 ? "" : formatDuration(v))),
      })
      scales.ms = { range: (u, min, max) => [0, niceMax(max)] }
    }

    return {
      width, height: isLast ? STRIP_HEIGHT + X_AXIS_SIZE : STRIP_HEIGHT,
      pxRatio: pxRatioFor(window.devicePixelRatio, theme.uiScale),
      legend: { show: false },
      cursor: {
        sync: { key: this.id }, x: true, y: false, points: { show: false },
        drag: { x: false, y: false },
      },
      hooks: { setCursor: [(u) => this.setHover(u.cursor.idx)] },
      scales, axes, series,
    }
  },

  resizeAll() {
    this.strips.forEach(({ chart, plot }, id) => {
      const width = plot.offsetWidth
      if (width > 0 && width !== chart.width) chart.setSize({ width, height: chart.height })
      void id
    })
  },

  updatePxRatio() {
    this.theme = readTheme()
    const ratio = pxRatioFor(window.devicePixelRatio, this.theme.uiScale)
    for (const { chart } of this.strips.values()) chart.setPxRatio(ratio)
  },
}
```

Register in `assets/js/app.js`: `import { StripChart } from "./hooks/strip_chart"` beside the other hook imports and `StripChart,` in the `hooks: {}` object.

- [ ] **Step 4: Run the bun tests, then the JS reachability gate**

Run: `cd assets && bun test js/hooks/strip_chart.test.js && cd .. && ~/scripts/agents/agent-mix boundaries`
Expected: tests pass; no "Dead JS".

- [ ] **Step 5: Build assets**

Run: `~/scripts/agents/agent-mix assets.build`
Expected: esbuild bundles `uplot.js` without errors.

- [ ] **Step 6: Commit**

```bash
git add assets/js/hooks/strip_chart.js assets/js/hooks/strip_chart.test.js assets/js/app.js
git commit -m "feat(assets): StripChart hook over uPlot

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 13: StatusLive wiring and the Connections widget (Fable subagent for the widget + story)

**Files:**
- Modify: `lib/media_centaur_web/live/status_live.ex` (mount, ensure_loaded, activity_bundle, :refresh_vitals, fetch_rate_limiter)
- Rewrite: `lib/media_centaur_web/components/status_widgets/http.ex`
- Rewrite: `storybook/status/http_widget.story.exs`
- Modify: `test/media_centaur_web/live/status_live_test.exs:34-42`
- Rewrite: `test/media_centaur_web/components/status_widgets_http_test.exs`

- [ ] **Step 1: Failing LiveView tests** — replace the test at lines 34-42 with:

```elixir
describe "connections drill-in" do
  test "pushes a frame for the configured strips and the window from the URL", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status?subsystem=http&window=5h")

    assert has_element?(view, "#traffic[phx-hook='StripChart']")
    assert_push_event(view, "strip_chart:frame", %{id: "traffic", window: "5h", strips: strips})
    ids = Enum.map(strips, & &1.id)
    assert "tmdb" in ids and "tmdb_images" in ids and "github" in ids
    refute "steam" in ids
  end

  test "an unknown window falls back to 1h", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status?subsystem=http&window=2h")
    assert_push_event(view, "strip_chart:frame", %{window: "1h"})
  end

  test "the pill patches the URL and a fresh frame follows", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status?subsystem=http")
    assert_push_event(view, "strip_chart:frame", %{window: "1h"})

    view |> element("[phx-value-window='1w']") |> render_click()
    assert_patch(view, "/status?subsystem=http&window=1w")
    assert_push_event(view, "strip_chart:frame", %{window: "1w"})
  end

  test "frames keep coming on the tick and stop while hidden", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status?subsystem=http")
    assert_push_event(view, "strip_chart:frame", _first)
    assert_push_event(view, "strip_chart:frame", _second, 500)

    render_hook(view, "strip_chart:visibility", %{"id" => "traffic", "visible" => false})
    flush_frames(view)
    refute_push_event(view, "strip_chart:frame", _, 300)

    render_hook(view, "strip_chart:visibility", %{"id" => "traffic", "visible" => true})
    assert_push_event(view, "strip_chart:frame", _resumed, 500)
  end

  test "no frames while another drill-in is open", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, "/status?subsystem=tmdb")
    refute_push_event(view, "strip_chart:frame", _, 300)
  end
end
```

Add a private helper in the test module:

```elixir
defp flush_frames(view) do
  receive do
    {_ref, {:push_event, "strip_chart:frame", _}} -> flush_frames(view)
  after
    0 -> :ok
  end
end
```

(`assert_push_event` reads messages of that shape from the test process mailbox; the helper drains any frame that arrived before the hide.) `render_hook/3` requires a hook element: `render_hook(element(view, "#traffic"), "strip_chart:visibility", …)` — use the element form.

- [ ] **Step 2: Run to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/status_live_test.exs`

- [ ] **Step 3: StatusLive**

In `mount/3`, after the subscription reduce and before the `if connected?` block:

```elixir
socket =
  MediaCentaurWeb.Components.StripChart.Feed.attach(socket,
    id: "traffic",
    frame: &MediaCentaurWeb.StatusLive.TrafficFrame.build/1,
    active?: &(&1["subsystem"] == "http")
  )
```

Remove `rate_limiter:` and `http_stats:` from `ensure_loaded/1` (lines 173-174) and from the `:refresh_vitals` clause (keep `system_vitals`). Delete `fetch_rate_limiter/0` (lines 840-845) and the comment at 514-515. In `activity_bundle/1` replace the `:http` block with:

```elixir
# http (connections)
traffic_window: MediaCentaurWeb.Components.StripChart.Feed.window(assigns, "traffic"),
traffic_recent: MediaCentaur.HttpClient.Traffic.recent(),
```

- [ ] **Step 4: The widget**

`lib/media_centaur_web/components/status_widgets/http.ex`:

```elixir
defmodule MediaCentaurWeb.Components.StatusWidgets.Http do
  @moduledoc """
  Connections (`:http`) Activity widget: the request strip charts — one
  strip per upstream over the selected window — with the collapsed feed
  of the most recent requests in the chart's footer.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1. The
  strips themselves come from frames (`StatusLive.TrafficFrame`) pushed
  by `StripChart.Feed`; this widget renders the shell and the feed list.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.StripChart, only: [strip_chart: 1]

  alias MediaCentaur.HttpClient.Upstream
  alias MediaCentaur.TimeSeries.Window
  alias MediaCentaurWeb.StatusLive.TrafficFrame

  @doc "Connections Activity widget: request strip charts + recent-request feed."
  attr :traffic_window, :atom, required: true, values: Window.all()
  attr :traffic_recent, :list, default: [], doc: "Traffic.recent/0 — newest first"

  def http_widget(assigns) do
    assigns = assign(assigns, :legend, TrafficFrame.legend())

    ~H"""
    <div data-testid="http-widget">
      <.strip_chart
        id="traffic"
        title="Requests"
        lede="Requests are what went out; cache is what was answered here instead. Hover a bar to read that bucket."
        window={@traffic_window}
        legend={@legend}
      >
        <:footer>
          <details :if={@traffic_recent != []} data-component="http-recent">
            <summary class="cursor-pointer text-xs text-base-content/55">Recent requests</summary>
            <ul class="mt-2 space-y-0.5 font-mono text-xs">
              <li :for={entry <- @traffic_recent} id={recent_row_id(entry)} class="flex items-baseline gap-2">
                <span class="text-base-content/55 shrink-0">{Calendar.strftime(entry.at, "%H:%M:%S")}</span>
                <span class="text-base-content/60 shrink-0">{Upstream.label(entry.upstream)}</span>
                <span class="truncate text-base-content/80">
                  {entry.method |> to_string() |> String.upcase()} {entry.path}
                </span>
                <span class={["ml-auto shrink-0", outcome_class(entry)]}>{outcome_label(entry)}</span>
                <span class="text-base-content/55 shrink-0 tabular-nums">{entry.duration_ms}ms</span>
                <span class="text-base-content/55 shrink-0">{cache_label(entry.cache)}</span>
              </li>
            </ul>
          </details>
        </:footer>
      </.strip_chart>
    </div>
    """
  end

  defp outcome_label(%{error: error}) when is_binary(error), do: error
  defp outcome_label(%{status: status}), do: to_string(status)

  defp outcome_class(%{error: error}) when is_binary(error), do: "text-error"
  defp outcome_class(%{status: status}) when status >= 400, do: "text-error"
  defp outcome_class(_entry), do: "text-base-content/60"

  defp cache_label(:uncached), do: ""
  defp cache_label(outcome), do: to_string(outcome)

  # Stable iterator id (UIDR-012).
  defp recent_row_id(%{at: %DateTime{} = at, path: path}) do
    "http-recent-#{DateTime.to_unix(at, :microsecond)}-#{:erlang.phash2(path)}"
  end
end
```

The `<details>` inside the footer: when the footer is a `flex` row, wrap the details so it sits right; the footer slot content is the second flex child. If the recent list needs the full card width when open, give the details `class="basis-full"` — judge on the dev server.

- [ ] **Step 5: The story**

`storybook/status/http_widget.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Status.HttpWidget do
  @moduledoc """
  Connections Activity widget: the request strip chart shell over the
  selected window plus the recent-requests feed. Strips render from
  frames under a live socket (`StripChart.Feed`); here the hook container
  is empty and the window pills, legend and feed are the contract.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.StatusWidgets.Http.http_widget/1
  def render_source, do: :function
  def layout, do: :one_column

  defp seconds_ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  defp recent do
    [
      %{at: seconds_ago(3), upstream: :tmdb, method: :get, path: "/3/tv/1/season/1", status: 200, error: nil, duration_ms: 180, cache: :miss},
      %{at: seconds_ago(9), upstream: :tmdb_images, method: :get, path: "/t/p/w500/sample.jpg", status: 200, error: nil, duration_ms: 95, cache: :uncached},
      %{at: seconds_ago(40), upstream: :prowlarr, method: :get, path: "/api/v1/search", status: nil, error: "timeout", duration_ms: 5_000, cache: :uncached}
    ]
  end

  def variations do
    [
      %Variation{id: :hour, description: "1h window, feed collapsed", attributes: %{traffic_window: :"1h", traffic_recent: recent()}},
      %Variation{id: :month_empty_feed, description: "1mo window, no recent requests", attributes: %{traffic_window: :"1mo", traffic_recent: []}},
      %Variation{id: :windows, description: "Every window value the pill offers: :\"5m\", :\"1h\", :\"5h\", :\"1d\", :\"1w\", :\"1mo\"", attributes: %{traffic_window: :"5m", traffic_recent: []}}
    ]
  end
end
```

MC0009 reads `values:` literals from the story source textually; the `:windows` description carries all six.

- [ ] **Step 6: The widget's pure test**

Replace `test/media_centaur_web/components/status_widgets_http_test.exs` with a test of `TrafficFrame.strip_ids/1` if not already covered in Task 11 (it is); delete the file instead, since `panel_rows/2` no longer exists.

- [ ] **Step 7: Run the suite slices**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/status_live_test.exs test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: pass.

- [ ] **Step 8: Commit**

```bash
git add lib/media_centaur_web/live/status_live.ex lib/media_centaur_web/components/status_widgets/http.ex storybook/status/http_widget.story.exs test/media_centaur_web
git commit -m "feat(status): Connections drill-in shows request strip charts

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 14: Real-browser verification on the dev server

**Files:** none (verification only; fix what it finds in the module that owns it)

- [ ] **Step 1: Build assets and confirm the dev server reloaded**

Run: `~/scripts/agents/agent-mix assets.build` then `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:2160/status`
Expected: `200`.

- [ ] **Step 2: Six canvases, correct backing size**

```bash
~/scripts/agents/chromium-probe --with-console 'http://localhost:2160/status?subsystem=http' '
  await new Promise(r => setTimeout(r, 3000));
  const canvases = [...document.querySelectorAll("#traffic canvas")];
  const scale = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--ui-scale")) || 1;
  JSON.stringify({
    strips: document.querySelectorAll("#traffic .strip-chart-strip").length,
    canvases: canvases.length,
    ratio: canvases[0] && (canvases[0].width / canvases[0].offsetWidth),
    expected: devicePixelRatio * scale,
    figures: document.querySelector("#traffic .strip-chart-figures")?.textContent
  })'
```

Expected: `strips` equals the configured upstream count (at least 3), `canvases` the same, `ratio` equals `expected` within rounding, `figures` non-empty. The console output must show no errors.

- [ ] **Step 3: A frame every ten seconds, none while hidden**

Use `chromium-probe` to count `strip_chart:frame` events over 25 s by wrapping `liveSocket` — simplest: record `#traffic .strip-chart-figures` text at t=0 and t=22 s after generating traffic (open `/library` in another probe to trigger TMDB image requests, or curl the app's own image endpoint). Confirm the text changed. Then, since headless has no visibility events, verify the hidden path by the LiveView test in Task 13 (already green).

- [ ] **Step 4: Hover swaps figures**

Dispatch a synthetic `mousemove` on the first `.u-over` element at its centre and read every strip's `.strip-chart-time` — all must show the same clock label. Then dispatch `mouseleave` and confirm the time spans empty and figures return to totals.

- [ ] **Step 5: Look at it**

Run `~/scripts/agents/page-shot --url 'http://localhost:2160/status?subsystem=http' --viewport 1920x1080 --wait-ms 4000` and Read the PNG. Compare against the approved mockup (layout 2): left column, six strips, aligned plots, time labels only under the last strip, legend and Recent requests in the footer. Fix spacing in `app.css` if the strips do not match. Do not open the screenshot for the owner (they have the browser open).

- [ ] **Step 6: Record**

Append the probe outputs (numbers, not screenshots) under a `## Verification` heading at the end of this plan file and commit:

```bash
git add docs/superpowers/plans/2026-09-19-strip-chart-plan.md
git commit -m "docs(plan): strip chart browser verification results

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 15: ADR-070, glossary, architecture, storybook docs, spec amendment

**Files:**
- Create: `decisions/architecture/2026-09-19-070-time-series-outside-the-database.md`
- Modify: `decisions/README.md` (regenerate)
- Modify: `docs/GLOSSARY.md` (new "Time series" section; cross-reference in *Bucket*)
- Modify: `docs/architecture.md` (contexts table row)
- Modify: `docs/storybook.md` (two stories)
- Modify: `docs/superpowers/specs/2026-09-19-strip-chart-design.md` (dated amendment on local time)

- [ ] **Step 1: ADR-070**

```markdown
---
status: accepted
date: 2026-09-19
---
# Durable observational time series live outside the main database

## Context and Problem Statement

ADR-041 makes the database the only source of truth: no ETS state is
authoritative for a persistent fact. The request history behind the
Connections strip charts is a persistent fact (its events are gone once
counted) but it is observational, of fixed size, and written on a timer.
The main SQLite database is single-writer and already reports busy errors;
the owner refused another periodic writer on it. A second SQLite database
would thread a second Repo through config, release migration, the test
sandbox and every override TOML for transactional durability and SQL the
data does not need.

## Decision Outcome

Chosen option: "an ETS round-robin store with a periodic snapshot file",
because it adds no writer to the database, has a ceiling by construction,
and needs no migration machinery. `MediaCentaur.TimeSeries.Store` keeps
the rows; once a minute, if anything changed, and on clean shutdown, it
writes the whole table to `<database dir>/<tenant>.snapshot` atomically,
and loads it on boot. A file whose version or field list does not match
is ignored and the store starts empty: observational data is never
migrated.

This is a bounded exception to ADR-041, not a new rule for state in
general. It applies to a time series a tenant would graph — counts of an
event over time, kept at fixed resolutions — and to nothing that a user
created or that another table refers to.

### Consequences

* Good, because the database gains no writer and the busy-error surface
  does not grow.
* Good, because the store's cost is fixed and visible: about 12,000 rows
  per tenant, one file, listed on the Connections retention panel and in
  the System tile's datastore figure.
* Bad, because a hard crash loses up to one minute of counts. Accepted
  for request tallies.
* Bad, because a second copy of "where durable state lives" exists;
  `MediaCentaur.TimeSeries` and this record are the only places it may.
```

Run `scripts/gen-decisions-index`.

- [ ] **Step 2: Glossary** — add before "## Observability":

```markdown
## Time series

The vocabulary of the strip charts (design
`docs/superpowers/specs/2026-09-19-strip-chart-design.md`).

| Term | Meaning |
|---|---|
| **Time series** | Counts of an event along time, per key — requests per upstream. `MediaCentaur.TimeSeries` is the mechanism (store, fold, snapshot); a **tenant** (`HttpClient.Traffic`) owns one series family. |
| **Time bucket** | The span one bar covers, and the span the store counts into. Qualified because *bucket* alone is an incident group (below). In `TimeSeries` code, `bucket` means the time bucket. |
| **Resolution** | One of the four stored bucket widths — 10 s kept 1 h, 1 min kept 6 h, 10 min kept 2 d, 1 h kept 31 d (`TimeSeries.Resolution`). Every event is counted into all four. Not "tier", which already has two meanings here. |
| **Window** | The span a viewer selects — 5m, 1h, 5h, 1d, 1w, 1mo (`TimeSeries.Window`) — and the bar width and count it implies. One window drives every strip on a surface. Bars of 20 minutes and wider align to the machine's local midnight. |
| **Round-robin store** | `TimeSeries.Store`: the ETS table whose rows past their resolution's retention are swept once a minute, so the row count is bounded by construction. Counting happens in the caller with atomic ETS operations; the process only sweeps and snapshots. |
| **Snapshot** (time series) | The store's on-disk copy, `<database dir>/<tenant>.snapshot`, written whole and atomically once a minute when anything changed and on clean shutdown; loaded on boot; ignored on version mismatch (ADR-070). Unrelated to a `Cache.Worker` projection snapshot. |
| **Strip chart** | `MediaCentaurWeb.Components.StripChart`: N **strips** (a name column with figures beside a short wide chart) sharing one window, one time axis and one synced cursor. The hook owns the strips; the server sends **frames**. |
| **Frame** | One push of data from the LiveView to the `StripChart` hook — window, schema, and per strip its figures and columns (`StripChart.Feed` moduledoc). |
| **Feed** | `StripChart.Feed`: the LiveView-side lifecycle — window from the URL, one frame on becoming active, one every ten seconds while active and the tab is visible. |
| **Traffic** | `MediaCentaur.HttpClient.Traffic`: the HTTP layer's time series of requests per upstream (requests, failed, cached, latency sum and max), plus the twenty most recent requests and each upstream's last outcome. Replaced `HttpClient.Stats`. |
```

In the existing *Bucket* row under Observability, prepend: "An incident group (below); a *time bucket* is the span of one bar, see § Time series."

- [ ] **Step 3: architecture.md** — add a row to the contexts table: `| MediaCentaur.TimeSeries | Round-robin time-series store, fold, snapshot file | Tenants: HttpClient.Traffic. ADR-070 |`. The mermaid line was updated in Task 7.

- [ ] **Step 4: storybook.md** — add `strip_chart` (composites) and note `http_widget` now renders the shell only.

- [ ] **Step 5: Spec amendment** — under §4 of the design's *Fold* paragraph add:

> **Amendment 2026-09-19:** the app has no time-zone database, so the Console conversion named here falls back to UTC. Wide bars align to local midnight using the OS offset from `:calendar.local_time/0`, read at fold time (`TimeSeries.LocalDay`). Bars before a daylight-saving change sit an hour off until the window rolls past it.

- [ ] **Step 6: Commit**

```bash
git add decisions docs
git commit -m "docs: ADR-070, time-series glossary, architecture and spec amendment

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 16: Wiki

**Files:** `~/src/media-centaur/media-centaur.wiki/` — the *Status* page under Using Media Centaur, and *Troubleshooting*.

- [ ] **Step 1: Status page** — in the Connections drill-in section, replace the description of the table with:

> **Connections** shows one chart per server Media Centaur talks to — TMDB, TMDB images, Prowlarr, your download clients, GitHub. Pick a window (5 minutes to a month) and every chart follows it. Bars are requests per bar: grey went out, red failed, the faint segment was answered from the local cache and never went out. The blue line is the mean latency, on the right-hand scale. Hover any chart to read the same moment on all of them. Figures beside each chart are totals for the window. "Recent requests" at the bottom lists the last twenty.

- [ ] **Step 2: Troubleshooting** — add:

> **Request history is empty after a restart.** The charts' data lives in `traffic.snapshot` beside the database, written once a minute. A crash loses at most the last minute; a file the app cannot read (after a version change) is ignored and the history starts over. Nothing else depends on it.

- [ ] **Step 3: Commit and push the wiki**

```bash
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: Connections drill-in strip charts" && git push
```

---

### Task 17: Precommit

- [ ] **Step 1:** Run `~/scripts/agents/agent-mix precommit` (allow up to 20 minutes). Fix everything it reports in the module that owns the problem. Zero warnings.
- [ ] **Step 2:** Commit any fixes with `fix:` messages and the session trailer. Do not push.

---

## Self-review

**Spec coverage.** §1 drill-in → Tasks 11, 13, 14. §2 component → 8, 9, 12. §3 feed → 10. §4 store → 1–4. §5 Traffic and readers → 5, 6, 7. §6 boundaries → 5, 7. Retention entry, datastore figure → 7. ADR, glossary, wiki → 15, 16. Tests at three levels → every task plus 14. Deferred items stay deferred.

**Type consistency.** `Store.add(table, schema, key, unix, values)` everywhere; `Store.rows(table, resolution, key, from, to)` everywhere; `Traffic.series/3` returns `went_out/failed/cached/mean_ms/worst_ms/totals`; `TrafficFrame.build/2` consumes exactly that; the frame keys `t/failed/went_out/cached/mean_ms/worst_ms/figures/dot/label/id` match `stackColumns`, `hoverFigures` and `rebuild`; `Feed.window(assigns, id)` is what the widget bundle reads.

## Verification (Task 14, 2026-09-19)

Dev server, headless Chromium (`--ui-scale` 0.7, device pixel ratio 1.5),
`/status?subsystem=http`, all six upstreams configured on this machine:

| Check | Result |
|---|---|
| Strips / canvases | 6 / 6 |
| Plot area heights (px, `.u-over`) | 50 on every strip, last strip included |
| Canvas backing store per plot px | 1.5 (device pixel ratio; the plot cell cancels the root zoom, see hook header) |
| Figures after 21 s with LAN clients polling | qBittorrent 61 → 62 requests, SABnzbd 120 → 124: frames arrive on the tick |
| Hover at 50 % of the TMDB strip | all six `.strip-chart-time` read the same bucket ("11:50"); cleared on `mouseleave` |
| Recent requests rows / unique ids | 20 / 20 |
| Console | no errors |
| Screenshot vs approved mockup (layout 2) | matches: left column, hairlines, aligned plots, grid on every strip, time labels only under the last strip, legend + Recent requests in the footer |

Hidden-tab pause and window-pill patching are covered by
`test/media_centaur_web/live/status_live_test.exs` ("connections drill-in").

Deviations from the plan, all in the hook and recorded in its header comment:
uPlot 1.6.32 has no `pxRatio` option, so the plot cell runs at
`zoom: calc(1 / var(--ui-scale))` and every length handed to uPlot is
scaled by the UI scale; explicit `padding` equalises the plot areas
because a hidden x-axis keeps uPlot's auto padding; zero bars are `null`
so no baseline dash is drawn; isolated line points use `points.filter`.
