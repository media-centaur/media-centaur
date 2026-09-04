defmodule MediaCentaur.SelfUpdate.IncidentContextAssessTest do
  @moduledoc """
  Integration coverage for the `assess/0` shell — that it gathers the durable
  `Health` snapshot, the last-check timestamp, and config, and that it is wired
  into the diagnostics registry the evaluator polls. The fault *logic* is
  covered exhaustively by the pure `decide/4` tests.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ErrorReports.Contributors
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.SelfUpdate
  alias MediaCentaur.SelfUpdate.{Health, IncidentContext}

  test "is registered as a diagnostics assessor for :self_update" do
    assert {:self_update, IncidentContext} in Contributors.assessors()
  end

  test "reports :ok when nothing has gone wrong" do
    assert IncidentContext.assess() == :ok
  end

  test "surfaces a recorded apply failure as an error fault" do
    :ok = Health.record_apply_failed(:checksum_mismatch)

    assert {:fault, :apply_failed, :error, _ids} = IncidentContext.assess()
  end

  test "surfaces a sustained check-failure streak as a warning fault" do
    for _ <- 1..3, do: Health.record_check_failure()

    assert {:fault, :check_failing, :warning, _ids} = IncidentContext.assess()
  end

  describe "scheduled_checks_enabled?/0 — the gate the probe shares with the checker job" do
    test "is false where checks never run, however the preference is set" do
      Config.update(:update_check_enabled, true)

      refute SelfUpdate.scheduled_checks_enabled?()
    end

    test "follows the preference where checks run" do
      Application.put_env(:media_centaur, :environment, :prod)
      on_exit(fn -> Application.put_env(:media_centaur, :environment, :test) end)

      Config.update(:update_check_enabled, true)
      assert SelfUpdate.scheduled_checks_enabled?()

      Config.update(:update_check_enabled, false)
      refute SelfUpdate.scheduled_checks_enabled?()
    end
  end

  describe "vitals/0" do
    test "returns a side-effect-free health snapshot" do
      vitals = IncidentContext.vitals()

      assert is_map(vitals)
      assert is_binary(vitals["version"])
      assert Map.has_key?(vitals, "classification")
      assert Map.has_key?(vitals, "check_failure_streak")
      assert Map.has_key?(vitals, "apply_failed")

      # Reading vitals must never trigger a check.
      assert MediaCentaur.SelfUpdate.last_check_at() == :none
    end

    test "reflects a recorded apply failure and check-failure streak" do
      :ok = Health.record_apply_failed(:checksum_mismatch)
      Health.record_check_failure()

      vitals = IncidentContext.vitals()

      assert vitals["apply_failed"] == true
      assert vitals["check_failure_streak"] == 1
    end
  end
end
