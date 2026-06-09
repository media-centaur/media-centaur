defmodule MediaCentaur.ErrorReports.SupersededSweepJobTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.ErrorReports.EnvMetadata
  alias MediaCentaur.ErrorReports.Incident
  alias MediaCentaur.ErrorReports.Store
  alias MediaCentaur.ErrorReports.SupersededSweepJob

  test "resolves open :log incidents from a superseded version, sparing the current one" do
    {:ok, superseded} =
      Store.upsert_log_incident(
        build_log_incident_attrs(fingerprint: "fp_old", app_version_at_last: "0.0.0-superseded")
      )

    {:ok, current} =
      Store.upsert_log_incident(
        build_log_incident_attrs(
          fingerprint: "fp_now",
          app_version_at_last: EnvMetadata.app_version()
        )
      )

    assert {:ok, 1} = Oban.Testing.perform_job(SupersededSweepJob, %{}, repo: MediaCentaur.Repo)

    assert Repo.get!(Incident, superseded.id).status == :resolved
    assert Repo.get!(Incident, current.id).status == :open
  end

  test "is a no-op when nothing is superseded" do
    {:ok, current} =
      Store.upsert_log_incident(
        build_log_incident_attrs(
          fingerprint: "fp_only_current",
          app_version_at_last: EnvMetadata.app_version()
        )
      )

    assert {:ok, 0} = Oban.Testing.perform_job(SupersededSweepJob, %{}, repo: MediaCentaur.Repo)
    assert Repo.get!(Incident, current.id).status == :open
  end
end
