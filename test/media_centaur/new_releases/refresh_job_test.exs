defmodule MediaCentaur.NewReleases.RefreshJobTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Features
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.NewReleases
  alias MediaCentaur.NewReleases.RefreshJob
  alias MediaCentaur.TmdbStubs

  setup context do
    TmdbStubs.mark_ready!()
    TmdbStubs.setup_artwork_cache(context)
    test_pid = self()

    Req.Test.stub(:tmdb, fn conn ->
      send(test_pid, {:tmdb_hit, conn.request_path})

      if conn.request_path == "/3/discover/movie" do
        Req.Test.json(conn, %{
          "total_pages" => 1,
          "results" => [%{"id" => 901, "release_date" => "2026-10-30", "title" => "Movie A"}]
        })
      else
        Req.Test.json(conn, TmdbStubs.movie_detail(%{"id" => 901}))
      end
    end)

    :ok
  end

  defp perform do
    Oban.Testing.perform_job(RefreshJob, %{}, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite)
  end

  test "while Discovery is off a run already waiting does nothing" do
    Features.set(:discovery, false)

    assert :ok = perform()
    refute_receive {:tmdb_hit, _path}
    assert NewReleases.members() == []
  end

  test "held while TMDB is down: no request, the membership untouched, and the run snoozes to try again" do
    {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

    assert {:snooze, 300} = perform()
    refute_receive {:tmdb_hit, _path}
    assert NewReleases.members() == []
  end

  test "with the feature on and TMDB up the shelf is refreshed" do
    assert :ok = perform()
    assert_receive {:tmdb_hit, "/3/discover/movie"}
    assert NewReleases.refs() == [{901, :movie}]
  end

  test "the shelf has no cron entry: the feature's runtime owns its schedule" do
    crontab =
      Enum.find_value(Application.get_env(:media_centaur, Oban)[:plugins], [], fn
        {Oban.Plugins.Cron, opts} -> Keyword.fetch!(opts, :crontab)
        _plugin -> nil
      end)

    refute Enum.any?(crontab, fn {_expression, worker} -> worker == RefreshJob end)
  end
end
