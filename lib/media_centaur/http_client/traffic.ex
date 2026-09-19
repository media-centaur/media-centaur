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
  columns), `totals/2` over an arbitrary span (the incident assessor's
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

  require MediaCentaur.Log

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

  @doc """
  Totals over the last `seconds:` (default 900) for one upstream, from the
  10-second resolution. Options: `now:`, `store_table:`.
  """
  @spec totals(atom(), keyword()) :: totals()
  def totals(upstream, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> System.os_time(:second) end)
    seconds = Keyword.get(opts, :seconds, 900)
    table = Keyword.get(opts, :store_table, @store_table)
    zero = %{requests: 0, failed: 0, cached: 0, latency_sum_ms: 0, latency_max_ms: 0}

    table
    |> Store.rows(:"10s", upstream, now - seconds, now)
    |> Enum.reduce(zero, fn {_start, values}, acc ->
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

  @doc "The twenty most recent requests, newest first. Option: `recent_table:`."
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
      [{_key, outcome, unix}] -> %{outcome: outcome, at: DateTime.from_unix!(unix)}
      [] -> nil
    end
  end

  @doc "When the upstream last answered successfully, or nil."
  @spec last_success_at(atom(), keyword()) :: DateTime.t() | nil
  def last_success_at(upstream, opts \\ []) do
    case lookup(Keyword.get(opts, :recent_table, @recent_table), {:last_success, upstream}) do
      [{_key, unix}] -> DateTime.from_unix!(unix)
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

    if !hit? do
      :ets.insert(recent, {{:last, upstream}, if(failed?, do: :failed, else: :ok), now})
      if !failed?, do: :ets.insert(recent, {{:last_success, upstream}, now})
    end

    :ok
  rescue
    error ->
      MediaCentaur.Log.warning(:system, "http traffic not recorded", reason: Exception.message(error))

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
