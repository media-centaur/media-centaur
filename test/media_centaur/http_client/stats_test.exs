defmodule MediaCentaur.HttpClient.StatsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.HttpClient.Stats

  @stop_event [:media_centaur, :http, :request, :stop]

  setup do
    name = :"http_stats_test_#{System.unique_integer([:positive])}"
    pid = start_supervised!({Stats, name: name})
    %{stats: pid, name: name}
  end

  # Delivers one sample straight to this instance, bypassing telemetry's
  # global dispatch (every running Stats instance would otherwise count it).
  defp record(stats, overrides) do
    metadata =
      Map.merge(
        %{upstream: :tmdb, method: :get, path: "/3/movie/1", status: 200, error: nil, cache: :miss},
        overrides
      )

    duration = System.convert_time_unit(Map.get(overrides, :duration_ms, 100), :millisecond, :native)
    Stats.handle_telemetry(@stop_event, %{duration: duration}, metadata, %{stats: stats})
  end

  defp row(name, id), do: Enum.find(Stats.snapshot(name).upstreams, &(&1.id == id))

  test "the empty snapshot lists every upstream at zero" do
    snapshot = Stats.empty_snapshot()

    assert Enum.map(snapshot.upstreams, & &1.id) == MediaCentaur.HttpClient.Upstream.ids()
    assert Enum.all?(snapshot.upstreams, &(&1.window.requests == 0 and &1.session.requests == 0))
    assert snapshot.recent == []
  end

  test "a request lands in its upstream's window and session figures", %{stats: stats, name: name} do
    record(stats, %{duration_ms: 120})
    record(stats, %{duration_ms: 0, cache: :hit})
    record(stats, %{upstream: :github, path: "/repos", status: 404, cache: :uncached})

    # The hit never went out: it counts under cache.hit and nowhere else.
    tmdb = row(name, :tmdb)
    assert tmdb.window.requests == 1
    assert tmdb.window.errors == 0
    assert tmdb.window.median_latency_ms == 120
    assert tmdb.window.cache == %{hit: 1, miss: 1, revalidate: 0, reload: 0}
    assert tmdb.session == %{requests: 1, errors: 0}
    assert %DateTime{} = tmdb.last_success_at
    assert tmdb.last_failure_at == nil

    github = row(name, :github)

    assert github.window == %{
             requests: 1,
             errors: 1,
             median_latency_ms: 100,
             cache: %{hit: 0, miss: 0, revalidate: 0, reload: 0}
           }

    assert %DateTime{} = github.last_failure_at
  end

  test "a transport error counts as an error and is described in the feed", %{stats: stats, name: name} do
    record(stats, %{status: nil, error: %Req.TransportError{reason: :econnrefused}})

    assert row(name, :tmdb).window.errors == 1
    assert [%{status: nil, error: "connection refused", upstream: :tmdb}] = Stats.snapshot(name).recent
  end

  test "the recent feed is newest-first and bounded", %{stats: stats, name: name} do
    for i <- 1..25, do: record(stats, %{path: "/3/movie/#{i}"})

    recent = Stats.snapshot(name).recent
    assert length(recent) == 20
    assert hd(recent).path == "/3/movie/25"
  end

  test "an unavailable server answers with the empty snapshot" do
    assert Stats.snapshot(:"http_stats_not_running_#{System.unique_integer([:positive])}") ==
             Stats.empty_snapshot()
  end

  describe "hit_ratio/1" do
    test "is nil without cache participation" do
      assert Stats.hit_ratio(%{hit: 0, miss: 0, revalidate: 0, reload: 0}) == nil
    end

    test "is hits over every cache outcome" do
      assert Stats.hit_ratio(%{hit: 3, miss: 1, revalidate: 0, reload: 0}) == 0.75
    end
  end
end
