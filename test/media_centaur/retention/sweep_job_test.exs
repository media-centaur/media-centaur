defmodule MediaCentaur.Retention.SweepJobTest do
  @moduledoc """
  Integration coverage for the daily retention sweep against the REAL
  provider registry from config — every declared `:sweep` policy must
  run cleanly on a fresh database and record its run row, so a broken
  or unrunnable provider fails here rather than at 04:33 in production.
  """
  use MediaCentaur.DataCase, async: false
  use Oban.Testing, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite

  import MediaCentaur.TestFactory

  alias MediaCentaur.Retention
  alias MediaCentaur.Retention.{Policy, SweepJob}
  alias MediaCentaur.ErrorReports.Store

  test "prunes diagnostic events older than 30 days through the real providers" do
    now = DateTime.utc_now()

    {:ok, _} =
      Store.insert_event(
        build_diagnostic_event_attrs(
          fingerprint: "fp_sweep",
          occurred_at: DateTime.add(now, -40 * 24 * 3600, :second)
        )
      )

    {:ok, _} =
      Store.insert_event(build_diagnostic_event_attrs(fingerprint: "fp_sweep", occurred_at: now))

    assert :ok = perform_job(SweepJob, %{})

    assert [remaining] = Store.list_recent_events("fp_sweep")
    assert DateTime.after?(remaining.occurred_at, DateTime.add(now, -1, :second))
    assert %{pruned_last_run: 1} = Retention.get_run(:diagnostic_events)
  end

  test "every declared sweep policy runs cleanly and records a run row" do
    assert :ok = perform_job(SweepJob, %{})

    for %Policy{mode: :sweep, key: key} <- Retention.policies() do
      assert %{last_ran_at: %DateTime{}} = Retention.get_run(key),
             "sweep policy #{key} did not record a run"
    end
  end

  test "every policy routes to a known Status-page subsystem" do
    known_subsystems = [
      :watcher,
      :pipeline,
      :tmdb,
      :playback,
      :library,
      :acquisition,
      :self_update,
      :system
    ]

    for %Policy{} = policy <- Retention.policies() do
      assert policy.subsystem in known_subsystems,
             "policy #{policy.key} routes to unknown subsystem #{policy.subsystem}"

      assert policy.description != ""

      if policy.mode == :sweep do
        assert is_function(policy.run, 0),
               "sweep policy #{policy.key} is missing a run function"
      end
    end
  end
end
