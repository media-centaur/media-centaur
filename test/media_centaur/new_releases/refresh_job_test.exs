defmodule MediaCentaur.NewReleases.RefreshJobTest do
  use MediaCentaur.DataCase, async: false

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

  test "held while TMDB is down: no request, the membership untouched, and the run snoozes to try again" do
    {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

    assert {:snooze, 300} = perform()
    refute_receive {:tmdb_hit, _path}
    assert NewReleases.members() == []
  end

  test "with TMDB up the shelf is refreshed" do
    assert :ok = perform()
    assert_receive {:tmdb_hit, "/3/discover/movie"}
    assert NewReleases.refs() == [{901, :movie}]
  end

  test "the job runs daily and once at boot, as one unique job" do
    crontab = cron_entries(Application.get_env(:media_centaur, Oban)[:plugins])
    assert {"3 4 * * *", RefreshJob} in crontab
    assert {"@reboot", RefreshJob} in crontab
  end

  defp cron_entries(plugins) do
    Enum.find_value(plugins, [], fn
      {Oban.Plugins.Cron, opts} -> Keyword.fetch!(opts, :crontab)
      _plugin -> nil
    end)
  end
end
