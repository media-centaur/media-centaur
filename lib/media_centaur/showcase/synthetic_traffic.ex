defmodule MediaCentaur.Showcase.SyntheticTraffic do
  use Boundary, top_level?: true, check: [in: false, out: false]
  use GenServer

  @moduledoc """
  Gives the showcase instance a request history, so Status → Connections
  draws the strip charts a working install draws.

  ## Why this is a process and not part of the seeder

  Everything else the showcase shows is a database row: the catalog, the
  watch history, even the two status incidents `Showcase.seed_status_incidents!/0`
  opens. Those are written once by `mix seed.showcase` and travel with
  the database file.

  The request history does not. It lives in `MediaCentaur.TimeSeries`'
  ETS table, keyed to wall-clock time and swept against a retention
  policy, so a history seeded at reseed time is gone by the time anybody
  boots the demo — and a showcase server started a week later draws five
  empty strips labelled "No requests in this window". Making it a
  process that rebuilds the history relative to *boot* means the
  instance reads as live whenever it starts, with no reseed.

  ## What it writes

  Two paths, for two reasons:

    * **The backfill** (31 days, at start) writes aggregates straight to
      the store with `TimeSeries.Store.add/5`. Telemetry cannot express a
      past request — the handler stamps its own clock — and a month of
      real request volume is millions of events besides.
    * **The tick** (every ten seconds, thereafter) emits the ordinary
      `MediaCentaur.HttpClient.Instrument` stop event, one per synthetic
      request. `Traffic` is already attached to it in dev and prod, so
      the recent-requests ring, each upstream's last outcome and its last
      success time all fill through the real path rather than through a
      second copy of that logic here.

  Shape comes from `#{inspect(__MODULE__)}.Profile`, which is pure and
  deterministic — the same boot draws the same history.

  ## When it runs

  Only when `:showcase_mode` is set, and never under `:test`. The flag
  lives in the Settings database, which is read *after* the supervision
  tree is up (`Application.post_supervisor_hooks/1`), so this process
  starts idle and begins on the `{:config_updated, :showcase_mode, true}`
  broadcast that the overlay publishes — the same channel the derived
  caches use.
  """

  alias MediaCentaur.HttpClient.{Instrument, Traffic}
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Showcase.SyntheticTraffic.Profile
  alias MediaCentaur.TimeSeries.Store
  alias MediaCentaur.Topics

  require MediaCentaur.Log

  @tick_ms 10_000

  # How far back the history goes, and how finely each stretch of it is
  # drawn. Coarse where the chart's own buckets are coarse: the windows
  # that reach back a month read hourly rows, so drawing that stretch
  # minute by minute would be work nothing renders. Spans are disjoint,
  # so every second of history is written exactly once.
  @bands [
    {0, 3_600, 10},
    {3_600, 6 * 3_600, 60},
    {6 * 3_600, 2 * 86_400, 600},
    {2 * 86_400, 31 * 86_400, 3_600}
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Replaces `table`'s contents with a fresh history for `upstreams`, ending
  at `now`. Clears first: the store restores its snapshot at boot, and
  adding a second month on top of a restored one would stack the counts
  on every restart. In showcase mode this process owns the table.

  Exposed so a test can drive it against its own store; the process calls
  it with `Traffic`'s.
  """
  @spec backfill(GenServer.server(), atom(), [atom()], integer()) :: :ok
  def backfill(server, table, upstreams, now) do
    :ok = Store.clear(server)

    for {from, to, bar_seconds} <- @bands,
        bucket <- buckets(now, from, to, bar_seconds),
        upstream <- upstreams do
      sample = Profile.sample(upstream, bucket, bar_seconds)

      if sample.requests > 0 or sample.cached > 0 do
        Store.add(table, Traffic.schema(), upstream, bucket, sample)
      end
    end

    :ok
  end

  @doc """
  Emits one tick's worth of requests for `upstreams` as
  `MediaCentaur.HttpClient.Instrument` stop events, as though they had
  just happened.
  """
  @spec emit_tick([atom()], integer()) :: :ok
  def emit_tick(upstreams, now) do
    bucket = now - Integer.mod(now, 10)

    for upstream <- upstreams do
      sample = Profile.sample(upstream, bucket, 10)
      emit_requests(upstream, sample)
      emit_hits(upstream, sample.cached)
    end

    :ok
  end

  @doc """
  Emits one successful request per upstream. The backfill writes counters
  but no outcome — `Traffic` keeps each upstream's last result and last
  success in its own table, filled only by the live event — so without
  this every strip but the busiest would show a grey dot and no last
  success, which reads as "never answered" rather than "quiet right now".
  """
  @spec prime([atom()]) :: :ok
  def prime(upstreams) do
    for upstream <- upstreams do
      emit(upstream, Profile.typical_latency_ms(upstream), status: 200, cache: :miss)
    end

    :ok
  end

  @impl true
  def init(_opts) do
    :ok = Topics.subscribe(Topics.config_updates())

    if Config.get(:showcase_mode), do: {:ok, :idle, {:continue, :start}}, else: {:ok, :idle}
  end

  @impl true
  def handle_continue(:start, :idle), do: {:noreply, start_generating()}
  def handle_continue(:start, state), do: {:noreply, state}

  @impl true
  def handle_info({:config_updated, :showcase_mode, true}, :idle) do
    {:noreply, start_generating()}
  end

  def handle_info(:tick, :running) do
    emit_tick(Profile.upstreams(), System.os_time(:second))
    schedule_tick()
    {:noreply, :running}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp start_generating do
    now = System.os_time(:second)
    upstreams = Profile.upstreams()

    backfill(Traffic.Store, Traffic.store_table(), upstreams, now)
    prime(upstreams)
    emit_tick(upstreams, now)
    schedule_tick()

    MediaCentaur.Log.info(
      :system,
      "showcase synthetic traffic: #{length(upstreams)} upstreams, 31 days backfilled"
    )

    :running
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)

  # Bucket starts from `to` seconds ago up to `from` seconds ago, aligned
  # to the bar width so each lands in a bucket of its own.
  defp buckets(now, from, to, bar_seconds) do
    first = align(now - to, bar_seconds)
    last = align(now - from, bar_seconds)

    Enum.take_while(Stream.iterate(first, &(&1 + bar_seconds)), &(&1 < last))
  end

  defp align(unix_seconds, bar_seconds), do: unix_seconds - Integer.mod(unix_seconds, bar_seconds)

  defp emit_requests(_upstream, %{requests: 0}), do: :ok

  defp emit_requests(upstream, sample) do
    # The bucket's failures land on its first requests; latency is the
    # bucket's slowest for one of them and the remainder shared evenly,
    # which is what the aggregate backfill writes for the same bucket.
    typical = div(max(sample.latency_sum_ms - sample.latency_max_ms, 0), max(sample.requests, 1))

    for index <- 1..sample.requests//1 do
      failed? = index <= sample.failed
      duration_ms = if index == 1, do: sample.latency_max_ms, else: typical

      emit(upstream, duration_ms,
        status: if(failed?, do: 503, else: 200),
        cache: :miss
      )
    end

    :ok
  end

  defp emit_hits(_upstream, 0), do: :ok

  defp emit_hits(upstream, count) do
    for _index <- 1..count//1, do: emit(upstream, 0, status: 200, cache: :hit)
    :ok
  end

  defp emit(upstream, duration_ms, opts) do
    :telemetry.execute(
      Instrument.stop_event(),
      %{duration: System.convert_time_unit(duration_ms, :millisecond, :native)},
      %{
        upstream: upstream,
        method: :get,
        host: "showcase",
        path: "/",
        status: Keyword.fetch!(opts, :status),
        error: nil,
        cache: Keyword.fetch!(opts, :cache),
        rate_limit_wait: 0
      }
    )
  end
end
