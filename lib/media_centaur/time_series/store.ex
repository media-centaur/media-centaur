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
  @schema_key :__schema__

  # Match-spec variables for up to `Schema.max_fields/0` counter fields,
  # written out so no atom is built at runtime.
  @match_variables [:"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8"]

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

  @doc """
  Rows of one resolution and key with a bucket start in `from..to`,
  ascending, as `{bucket_start, values}`.
  """
  @spec rows(atom(), Resolution.t(), term(), integer(), integer()) :: [{integer(), map()}]
  def rows(table, resolution, key, from, to) do
    case :ets.whereis(table) do
      :undefined ->
        []

      _tid ->
        schema = schema(table)

        table
        |> :ets.select([
          {head(schema, {resolution, key, :"$1"}), [{:andalso, {:>=, :"$1", from}, {:"=<", :"$1", to}}],
           [:"$_"]}
        ])
        |> Enum.map(fn row -> {row |> elem(0) |> elem(2), Schema.values(schema, row)} end)
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

  @doc """
  Discards every row, synchronously. For a caller that *owns* the table's
  contents and rebuilds them wholesale — `MediaCentaur.Showcase.SyntheticTraffic`
  regenerating the demo instance's history at boot, on top of whatever the
  snapshot restored. A tenant counting real events must never call this.
  """
  @spec clear(GenServer.server()) :: :ok
  def clear(server), do: GenServer.call(server, :clear)

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

    :ets.insert(table, {@schema_key, schema})

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
    Process.send_after(self(), :sweep, state.sweep_ms)
    Process.send_after(self(), :snapshot, state.snapshot_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:sweep, now}, _from, state), do: {:reply, sweep(state, now), state}
  def handle_call(:snapshot, _from, state), do: {:reply, :ok, write_snapshot(state)}

  def handle_call(:clear, _from, state) do
    # Data rows only — the table also holds the schema and the write
    # counter, and a store that lost its schema cannot answer a read.
    :ets.select_delete(state.table, [{head(state.schema, {:_, :_, :_}), [], [true]}])
    {:reply, :ok, state}
  end

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

  defp schema(table) do
    [{@schema_key, schema}] = :ets.lookup(table, @schema_key)
    schema
  end

  # A match-spec head of the row's full arity: the key pattern, then one
  # wildcard per field. A two-element head would never match a row.
  defp head(%Schema{names: names}, key_pattern) do
    List.to_tuple([key_pattern | List.duplicate(:_, length(names))])
  end

  # `{{res, key, start}, $1, …, $n}` with the key bound; replace the row
  # when the max field is smaller than `value`. Tuples in the body are
  # wrapped once, as match specs require.
  defp max_spec(%Schema{names: names}, row_key, position, value) do
    variables = Enum.take(@match_variables, length(names))
    head = List.to_tuple([row_key | variables])
    field_variable = Enum.at(variables, position - 2)

    body_values =
      Enum.map(variables, fn variable ->
        if variable == field_variable, do: value, else: variable
      end)

    body = List.to_tuple([{row_key} | body_values])
    [{head, [{:<, field_variable, value}], [{body}]}]
  end

  defp sweep(state, now) do
    pruned =
      Enum.reduce(Resolution.all(), 0, fn resolution, acc ->
        cutoff = now - Resolution.retention(resolution)

        acc +
          :ets.select_delete(state.table, [
            {head(state.schema, {resolution, :_, :"$1"}), [{:<, :"$1", cutoff}], [true]}
          ])
      end)

    if state.retention_policy && pruned > 0 do
      MediaCentaur.Retention.record_run(state.retention_policy, pruned)
    end

    pruned
  end

  defp write_snapshot(%{snapshot_path: nil} = state), do: state

  defp write_snapshot(state) do
    writes = writes(state.table)

    if writes == state.snapshotted_writes do
      state
    else
      rows = :ets.select(state.table, [{head(state.schema, {:_, :_, :_}), [], [:"$_"]}])

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
