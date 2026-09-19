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

  defp strip(frame, id), do: Enum.find(frame.strips, &(&1.id == id))

  test "strips are the always-on upstreams plus the configured ones, in panel order" do
    frame = build([])

    assert Enum.map(frame.strips, & &1.id) == [
             "tmdb",
             "tmdb_images",
             "prowlarr",
             "qbittorrent",
             "github"
           ]

    assert frame.window == "1h"
    assert frame.bucket_seconds == 60
    assert Enum.map(frame.schema.bars, & &1.key) == ["failed", "went_out", "cached"]
    assert frame.schema.line.key == "mean_ms"
  end

  test "figures carry window totals with failed toned, cached only when present" do
    totals = %{requests: 1_189, failed: 5, cached: 577, mean_ms: 279, worst_ms: 1_200}

    frame =
      build(
        series: fn
          :tmdb, _ -> series(%{totals: totals})
          _, _ -> series(%{})
        end,
        last_success_at: fn
          :tmdb -> DateTime.add(@now, -12, :second)
          _ -> nil
        end,
        last: fn
          :tmdb -> %{outcome: :ok, at: @now}
          _ -> nil
        end
      )

    tmdb = strip(frame, "tmdb")
    assert tmdb.dot == "ok"

    assert [
             [%{text: "1,189 requests"}, %{text: "5 failed", tone: "error"}],
             [%{text: "577 cached"}, %{text: "279 ms mean"}],
             [%{text: "ok " <> _}]
           ] = tmdb.figures
  end

  test "a strip with no requests says so" do
    github = strip(build([]), "github")
    assert github.dot == "none"
    assert github.figures == [[%{text: "No requests in this window"}], [%{text: "—"}]]
  end

  test "a down integration reads Down since in warning tone" do
    frame =
      build(
        down_since: fn
          :prowlarr -> ~U[2026-09-19 13:02:00Z]
          _ -> nil
        end
      )

    assert List.last(strip(frame, "prowlarr").figures) ==
             [%{text: "Down since 13:02", tone: "warning"}]
  end

  test "TMDB shows the rate-limiter budget when the limiter is running" do
    frame = build(rate_limiter: %{available: 28, total: 30, used: 2})
    assert List.last(strip(frame, "tmdb").figures) == [%{text: "28 of 30 slots free"}]
    assert List.last(strip(frame, "github").figures) == [%{text: "—"}]
  end

  test "a failed last request colors the dot" do
    frame =
      build(
        last: fn
          :tmdb -> %{outcome: :failed, at: @now}
          _ -> nil
        end
      )

    assert strip(frame, "tmdb").dot == "failed"
  end

  test "latency at or above a second reads in seconds" do
    totals = %{requests: 3, failed: 0, cached: 0, mean_ms: 1_650, worst_ms: 2_000}
    frame = build(series: fn _, _ -> series(%{totals: totals}) end)
    assert [_, [%{text: "1.7 s mean"}], _] = strip(frame, "github").figures
  end
end
