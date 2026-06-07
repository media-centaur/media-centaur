defmodule MediaCentaur.SelfUpdate.IncidentContextAssessTest do
  @moduledoc """
  Integration coverage for the `assess/0` shell — that it gathers the durable
  `Health` snapshot, the last-check timestamp, and config, and that it is wired
  into the diagnostics registry the evaluator polls. The fault *logic* is
  covered exhaustively by the pure `decide/4` tests.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ErrorReports.Contributors
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
end
