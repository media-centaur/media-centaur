defmodule MediaCentaur.HttpClient.Stats do
  @moduledoc """
  Folds the HTTP instrumentation event into the per-upstream figures the
  Status page's Connections tile shows.

  Attaches to `[:media_centaur, :http, :request, :stop]`
  (`MediaCentaur.HttpClient.Instrument`), receives one sample per
  request via `GenServer.cast`, and serves a snapshot via
  `GenServer.call`. Mirrors `MediaCentaur.TMDB.MetadataStats`; the
  handler id derives from the registered name so per-test instances
  attach independently.

  ## Snapshot shape

      %{
        window_minutes: 15,
        upstreams: [
          %{
            id: :tmdb, label: "TMDB",
            window: %{requests: 42, errors: 1, median_latency_ms: 180,
                      cache: %{hit: 30, miss: 10, revalidate: 2, reload: 0}},
            session: %{requests: 900, errors: 3},
            last_success_at: DateTime.t() | nil,
            last_failure_at: DateTime.t() | nil
          },
          …one row per `MediaCentaur.HttpClient.Upstream` id, in order…
        ],
        recent: [%{at:, upstream:, method:, path:, status:, error:, duration_ms:, cache:}, …]
      }

  `requests`, `errors`, and `median_latency_ms` describe what reached
  the upstream: cache hits are not requests, they are counted under
  `cache.hit` only, so a repeated search that the cache answers moves
  the hit count and nothing else. A request counts as an error when it
  failed at the transport or answered with a status of 400 or above.
  `recent` is newest-first and bounded to the last #{20} requests, hits
  included. Window figures cover the last fifteen minutes; session
  figures accumulate since boot.
  """
  use GenServer

  alias MediaCentaur.HttpClient.{Instrument, Upstream}

  @window_ms to_timeout(minute: 15)
  @max_recent 20

  # --- Public API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "The current snapshot, or the empty snapshot when the server is not running."
  @spec snapshot(GenServer.server()) :: map()
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  catch
    :exit, _ -> empty_snapshot()
  end

  @doc "The snapshot before any request: every upstream at zero."
  @spec empty_snapshot() :: map()
  def empty_snapshot do
    %{
      window_minutes: div(@window_ms, 60_000),
      upstreams: Enum.map(Upstream.ids(), &row(&1, [], empty_session())),
      recent: []
    }
  end

  @doc "Cache hits as a share of window requests the cache took part in, `nil` when none."
  @spec hit_ratio(%{
          hit: non_neg_integer(),
          miss: non_neg_integer(),
          revalidate: non_neg_integer(),
          reload: non_neg_integer()
        }) ::
          float() | nil
  def hit_ratio(%{hit: hit, miss: miss, revalidate: revalidate, reload: reload}) do
    case hit + miss + revalidate + reload do
      0 -> nil
      total -> hit / total
    end
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    handler_id = "http-stats-#{inspect(name)}"
    :telemetry.detach(handler_id)

    :telemetry.attach(handler_id, Instrument.stop_event(), &__MODULE__.handle_telemetry/4, %{
      stats: self()
    })

    {:ok, %{samples: [], session: %{}, recent: [], handler_id: handler_id}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    state = prune(state)

    snapshot = %{
      window_minutes: div(@window_ms, 60_000),
      upstreams:
        Enum.map(Upstream.ids(), fn id ->
          row(
            id,
            Enum.filter(state.samples, &(&1.upstream == id)),
            Map.get(state.session, id, empty_session())
          )
        end),
      recent: state.recent
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_cast({:request, sample, entry}, state) do
    session =
      Map.update(
        state.session,
        sample.upstream,
        bump(empty_session(), sample, entry),
        &bump(&1, sample, entry)
      )

    state = %{
      state
      | samples: [sample | state.samples],
        session: session,
        recent: Enum.take([entry | state.recent], @max_recent)
    }

    {:noreply, prune(state)}
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach(state.handler_id)
    :ok
  end

  # --- Telemetry wiring ---

  @doc false
  def handle_telemetry(_event, %{duration: duration}, metadata, %{stats: stats}) do
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    error? = metadata.error != nil or (is_integer(metadata.status) and metadata.status >= 400)

    sample = %{
      at_ms: System.monotonic_time(:millisecond),
      upstream: metadata.upstream,
      error?: error?,
      duration_ms: duration_ms,
      cache: metadata.cache
    }

    entry = %{
      at: DateTime.utc_now(),
      upstream: metadata.upstream,
      method: metadata.method,
      path: metadata.path,
      status: metadata.status,
      error: metadata.error && Exception.message(metadata.error),
      duration_ms: duration_ms,
      cache: metadata.cache
    }

    GenServer.cast(stats, {:request, sample, entry})
  end

  # --- Internals ---

  defp empty_session, do: %{requests: 0, errors: 0, last_success_at: nil, last_failure_at: nil}

  # A hit never reached the upstream: nothing to count against it.
  defp bump(session, %{cache: :hit}, _entry), do: session

  defp bump(session, %{error?: true}, entry) do
    %{session | requests: session.requests + 1, errors: session.errors + 1, last_failure_at: entry.at}
  end

  defp bump(session, _sample, entry) do
    %{session | requests: session.requests + 1, last_success_at: entry.at}
  end

  defp prune(state) do
    cutoff = System.monotonic_time(:millisecond) - @window_ms
    %{state | samples: Enum.take_while(state.samples, &(&1.at_ms > cutoff))}
  end

  defp row(id, samples, session) do
    wire = Enum.reject(samples, &(&1.cache == :hit))

    %{
      id: id,
      label: Upstream.label(id),
      window: %{
        requests: length(wire),
        errors: Enum.count(wire, & &1.error?),
        median_latency_ms: median(Enum.map(wire, & &1.duration_ms)),
        cache: %{
          hit: Enum.count(samples, &(&1.cache == :hit)),
          miss: Enum.count(samples, &(&1.cache == :miss)),
          revalidate: Enum.count(samples, &(&1.cache == :revalidate)),
          reload: Enum.count(samples, &(&1.cache == :reload))
        }
      },
      session: %{requests: session.requests, errors: session.errors},
      last_success_at: session.last_success_at,
      last_failure_at: session.last_failure_at
    }
  end

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    Enum.at(sorted, div(length(sorted), 2))
  end
end
