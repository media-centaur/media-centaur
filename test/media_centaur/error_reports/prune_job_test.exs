defmodule MediaCentaur.ErrorReports.PruneJobTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.ErrorReports.PruneJob
  alias MediaCentaur.ErrorReports.Store

  defp seed_event(fingerprint, occurred_at) do
    {:ok, _} =
      Store.insert_event(
        build_diagnostic_event_attrs(fingerprint: fingerprint, occurred_at: occurred_at)
      )
  end

  test "prunes events older than the default 30-day retention, keeping fresh ones" do
    now = DateTime.utc_now()
    seed_event("fp_prune", DateTime.add(now, -40 * 24 * 3600, :second))
    seed_event("fp_prune", DateTime.add(now, -2 * 24 * 3600, :second))

    assert {:ok, 1} = perform_job(PruneJob, %{})

    assert [remaining] = Store.list_recent_events("fp_prune")
    assert DateTime.after?(remaining.occurred_at, DateTime.add(now, -3 * 24 * 3600, :second))
  end

  test "honours a retention_days override from job args" do
    now = DateTime.utc_now()
    seed_event("fp_short", DateTime.add(now, -5 * 24 * 3600, :second))

    assert {:ok, 1} = perform_job(PruneJob, %{"retention_days" => 3})
    assert Store.list_recent_events("fp_short") == []
  end

  defp perform_job(worker, args) do
    case Oban.Testing.perform_job(worker, args, repo: MediaCentaur.Repo) do
      :ok -> {:ok, :ok}
      {:ok, value} -> {:ok, value}
      other -> other
    end
  end
end
