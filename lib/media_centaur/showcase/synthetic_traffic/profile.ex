defmodule MediaCentaur.Showcase.SyntheticTraffic.Profile do
  @moduledoc """
  How much traffic each upstream makes, and what it looks like — the
  "plausible" half of `MediaCentaur.Showcase.SyntheticTraffic`. Pure, so
  the shape can be tested without an ETS store or a clock.

  `sample/3` answers one question: for this upstream, in the bucket
  starting at this second and lasting this long, what did the HTTP layer
  record? The counters it returns are `MediaCentaur.HttpClient.Traffic`'s
  schema, so the caller hands them straight to the time-series store.

  Two things make the result look like a real instance rather than a
  band of identical bars:

    * **Each upstream behaves like itself.** A queue poller runs a fixed
      cadence around the clock; an indexer is used in short bursts when
      somebody searches; the update check fires a couple of times a day.
      Cache hits, latency and failure rates differ the same way.
    * **Traffic follows the day.** Everything that is driven by a person
      at the keyboard quietens overnight.

  Randomness is derived from the bucket itself (`:erlang.phash2/2`), not
  from a PRNG's state, so a bucket always samples the same whether it is
  reached by the boot-time backfill or by a later tick, and the demo
  instance draws the same history every time it starts.
  """

  alias MediaCentaur.HttpClient.Upstream

  @typedoc "One bucket's counters, in `MediaCentaur.HttpClient.Traffic`'s schema."
  @type sample :: %{
          requests: non_neg_integer(),
          failed: non_neg_integer(),
          cached: non_neg_integer(),
          latency_sum_us: non_neg_integer(),
          latency_max_us: non_neg_integer()
        }

  # per_minute    requests that go out in a quiet minute
  # burst         {chance per minute, extra requests} — a search, a refresh
  # latency_us    typical round trip, microseconds
  # spread_us     how much slower the slow ones are, microseconds
  # failure_rate  share of requests that come back 400+ or not at all
  # cache_rate    share of reads the response cache answers
  # diurnal?      driven by a person, so it follows the clock
  @profiles %{
    tmdb: %{
      per_minute: 0.3,
      burst: {0.04, 30},
      latency_us: 130_000,
      spread_us: 240_000,
      failure_rate: 0.006,
      cache_rate: 0.5,
      diurnal?: true
    },
    tmdb_images: %{
      per_minute: 0.2,
      burst: {0.03, 18},
      latency_us: 85_000,
      spread_us: 170_000,
      failure_rate: 0.004,
      cache_rate: 0.3,
      diurnal?: true
    },
    prowlarr: %{
      per_minute: 0.05,
      burst: {0.012, 5},
      latency_us: 460_000,
      spread_us: 900_000,
      failure_rate: 0.04,
      cache_rate: 0.0,
      diurnal?: true
    },
    qbittorrent: %{
      per_minute: 6.0,
      burst: {0.0, 0},
      latency_us: 600,
      spread_us: 2_500,
      failure_rate: 0.001,
      cache_rate: 0.0,
      diurnal?: false
    },
    sabnzbd: %{
      per_minute: 4.0,
      burst: {0.0, 0},
      latency_us: 800,
      spread_us: 3_000,
      failure_rate: 0.001,
      cache_rate: 0.0,
      diurnal?: false
    },
    github: %{
      per_minute: 0.017,
      burst: {0.0, 0},
      latency_us: 190_000,
      spread_us: 140_000,
      failure_rate: 0.0,
      cache_rate: 0.0,
      diurnal?: false
    }
  }

  # Multiplier by local hour: asleep, morning, working day, evening peak.
  @diurnal {0.15, 0.1, 0.1, 0.1, 0.1, 0.15, 0.3, 0.5, 0.7, 0.8, 0.85, 0.9, 0.9, 0.85, 0.8, 0.85, 0.95,
            1.1, 1.3, 1.4, 1.4, 1.2, 0.8, 0.4}

  @doc "The upstreams this module can sample — every one the Connections panel rows."
  @spec upstreams() :: [Upstream.id()]
  def upstreams, do: Enum.filter(Upstream.panel_ids(), &Map.has_key?(@profiles, &1))

  @doc "An unremarkable round trip to `upstream`, in microseconds."
  @spec typical_latency_us(Upstream.id()) :: pos_integer()
  def typical_latency_us(upstream), do: Map.fetch!(@profiles, upstream).latency_us

  @doc """
  The counters for `upstream` in the `bar_seconds`-wide bucket starting at
  `bucket_start` (unix seconds). Deterministic.
  """
  @spec sample(Upstream.id(), integer(), pos_integer()) :: sample()
  def sample(upstream, bucket_start, bar_seconds) when bar_seconds > 0 do
    profile = Map.fetch!(@profiles, upstream)
    minutes = bar_seconds / 60

    steady = profile.per_minute * minutes * diurnal(profile, bucket_start)

    attempts =
      count(steady, upstream, bucket_start, :rate) +
        bursts(profile, upstream, bucket_start, minutes)

    cached = share(attempts, profile.cache_rate, upstream, bucket_start, :cache)
    requests = attempts - cached
    failed = share(requests, profile.failure_rate, upstream, bucket_start, :fail)

    {sum_us, max_us} = latency(profile, requests, upstream, bucket_start)

    %{
      requests: requests,
      failed: failed,
      cached: cached,
      latency_sum_us: sum_us,
      latency_max_us: max_us
    }
  end

  # A fractional expectation becomes a whole count: the floor, plus the
  # remainder as a chance. Over many buckets the mean is the expectation.
  defp count(expected, upstream, bucket_start, salt) do
    whole = trunc(expected)
    if unit(upstream, bucket_start, salt) < expected - whole, do: whole + 1, else: whole
  end

  defp bursts(%{burst: {+0.0, _size}}, _upstream, _bucket_start, _minutes), do: 0

  defp bursts(%{burst: {chance, size}} = profile, upstream, bucket_start, minutes) do
    expected = chance * minutes * diurnal(profile, bucket_start)
    count(expected, upstream, bucket_start, :burst) * size
  end

  defp share(0, _rate, _upstream, _bucket_start, _salt), do: 0
  defp share(_total, +0.0, _upstream, _bucket_start, _salt), do: 0

  defp share(total, rate, upstream, bucket_start, salt) do
    min(total, count(total * rate, upstream, bucket_start, salt))
  end

  defp latency(_profile, 0, _upstream, _bucket_start), do: {0, 0}

  defp latency(profile, requests, upstream, bucket_start) do
    # One slow request in the bucket sets the maximum; the rest sit near
    # the typical round trip. That is the shape a real bucket has, and it
    # is what makes the mean-latency line move at all.
    slowest = profile.latency_us + trunc(profile.spread_us * unit(upstream, bucket_start, :slow))
    typical = profile.latency_us + trunc(profile.spread_us * 0.2 * unit(upstream, bucket_start, :typ))

    {slowest + (requests - 1) * typical, slowest}
  end

  defp diurnal(%{diurnal?: false}, _bucket_start), do: 1.0

  defp diurnal(%{diurnal?: true}, bucket_start) do
    elem(@diurnal, rem(div(bucket_start, 3_600), 24))
  end

  # A stable [0, 1) drawn from the bucket itself, so nothing depends on
  # the order buckets are visited in.
  defp unit(upstream, bucket_start, salt) do
    :erlang.phash2({upstream, bucket_start, salt}, 1_000_000) / 1_000_000
  end
end
