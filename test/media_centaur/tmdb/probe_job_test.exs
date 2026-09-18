defmodule MediaCentaur.TMDB.ProbeJobTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.TMDB.ProbeJob
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client()
    :ok = TmdbStubs.mark_ready!()
    :ok
  end

  test "a probe that answers marks TMDB up and the job completes" do
    {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})
    Req.Test.stub(:tmdb, fn conn -> Req.Test.json(conn, %{"images" => %{}}) end)

    assert :ok = perform_probe()
    assert IntegrationAvailability.up?(:tmdb)
  end

  test "a probe that fails snoozes at the cadence and leaves TMDB down" do
    {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})
    Req.Test.stub(:tmdb, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:snooze, 300} = perform_probe()
    refute IntegrationAvailability.up?(:tmdb)
  end

  test "an unconfigured TMDB completes rather than snoozing forever" do
    {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})
    :ok = TmdbStubs.mark_unconfigured!()

    Req.Test.stub(:tmdb, fn _conn -> flunk("an unconfigured TMDB must not be probed") end)

    assert :ok = perform_probe()
  end

  defp perform_probe do
    Oban.Testing.perform_job(ProbeJob, %{}, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite)
  end
end
