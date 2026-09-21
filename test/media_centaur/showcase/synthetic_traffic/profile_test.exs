defmodule MediaCentaur.Showcase.SyntheticTraffic.ProfileTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Showcase.SyntheticTraffic.Profile

  # One day, sampled a minute at a time, is enough to see a profile's shape
  # without the test knowing its tuning constants.
  defp day(upstream, bar_seconds \\ 60) do
    start = 1_789_000_000

    for index <- 0..(div(86_400, bar_seconds) - 1) do
      Profile.sample(upstream, start + index * bar_seconds, bar_seconds)
    end
  end

  defp total(samples, key), do: samples |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()

  describe "sample/3" do
    test "a bucket always samples the same, whichever pass reaches it" do
      # The backfill and the later ticks both sample the same buckets; if
      # the answer moved, the chart would rewrite its own history.
      assert Profile.sample(:tmdb, 1_789_000_000, 60) == Profile.sample(:tmdb, 1_789_000_000, 60)

      assert Profile.sample(:qbittorrent, 1_789_000_000, 10) ==
               Profile.sample(:qbittorrent, 1_789_000_000, 10)
    end

    test "buckets differ from each other — the history is not a flat band" do
      distinct = :qbittorrent |> day() |> Enum.uniq() |> length()

      assert distinct > 3, "every bucket identical reads as generated, not recorded"
    end

    test "a poller runs all day; a search upstream is quiet by comparison" do
      polling = total(day(:qbittorrent), :requests)
      searching = total(day(:prowlarr), :requests)

      assert polling > 1_000, "a queue poller should make thousands of requests a day"
      assert searching < polling / 10, "searches are occasional, polling is constant"
      assert searching > 0, "a configured indexer should still be used"
    end

    test "latency totals are consistent with the request count" do
      for upstream <- Profile.upstreams() do
        samples = day(upstream)

        for sample <- samples do
          assert sample.latency_sum_ms >= 0
          assert sample.failed <= sample.requests, "a failure is a request that went out"

          if sample.requests == 0 do
            assert sample.latency_sum_ms == 0
            assert sample.latency_max_ms == 0
          else
            assert sample.latency_max_ms > 0
            assert sample.latency_sum_ms >= sample.latency_max_ms
          end
        end
      end
    end

    test "a cached request is not also a request that went out" do
      # `Traffic` counts a cache hit as `cached` only — it never reached the
      # upstream, so it carries no latency and cannot have failed.
      samples = day(:tmdb)

      assert total(samples, :cached) > 0, "TMDB reads should hit the response cache"
      assert Enum.all?(samples, &(&1.cached >= 0))
    end

    test "failures are rare but present across a day" do
      failures = total(day(:prowlarr), :failed)
      requests = total(day(:prowlarr), :requests)

      assert failures > 0, "a day with no failure at all reads as fake"
      assert failures < requests / 4, "a quarter of requests failing is an outage, not health"
    end

    test "traffic is busier in the evening than in the small hours" do
      # Diurnal shape is what separates plausible history from a flat band.
      quiet = Profile.sample(:tmdb, hour_at(4), 3_600)
      busy = Profile.sample(:tmdb, hour_at(20), 3_600)

      assert busy.requests > quiet.requests
    end

    defp hour_at(hour) do
      # A fixed date so the sample is stable; midnight UTC plus `hour`.
      DateTime.to_unix(DateTime.new!(~D[2026-09-14], Time.new!(hour, 0, 0), "Etc/UTC"))
    end
  end
end
