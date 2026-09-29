defmodule MediaCentaur.JobsTest do
  # Sync: the failure handler is attached globally, and capture_log reads
  # the global logger.
  use MediaCentaur.DataCase, async: false

  import ExUnit.CaptureLog

  defmodule ReturnsError do
    use Oban.Worker, queue: :maintenance, max_attempts: 3

    @impl Oban.Worker
    def perform(%Oban.Job{}), do: {:error, :upstream_unavailable}
  end

  defmodule Raises do
    use Oban.Worker, queue: :maintenance, max_attempts: 3

    @impl Oban.Worker
    def perform(%Oban.Job{}), do: raise("sample job failure")
  end

  defp perform(worker, attempt) do
    Oban.Testing.perform_job(worker, %{"sample_id" => 7},
      repo: MediaCentaur.Repo,
      engine: Oban.Engines.Lite,
      attempt: attempt
    )
  end

  describe "a failed job is logged (ADR-077, rule 7)" do
    test "an error Oban will retry is a warning, kept out of incidents" do
      log = capture_log([metadata: [:mc_incident]], fn -> perform(ReturnsError, 1) end)

      assert log =~ "[warning]"
      assert log =~ "ReturnsError"
      assert log =~ "attempt 1 of 3, will retry"
      assert log =~ "upstream_unavailable"
      assert log =~ "mc_incident=skip"
    end

    test "a raise Oban will retry is a warning that reaches incidents" do
      log =
        capture_log([metadata: [:mc_incident]], fn ->
          assert_raise RuntimeError, fn -> perform(Raises, 1) end
        end)

      assert log =~ "[warning]"
      assert log =~ "sample job failure"
      assert log =~ "attempt 1 of 3, will retry"
      refute log =~ "mc_incident=skip"
    end

    test "a job on its last attempt is discarded, and that is an error" do
      log = capture_log(fn -> perform(ReturnsError, 3) end)

      assert log =~ "[error]"
      assert log =~ "ReturnsError"
      assert log =~ "attempt 3 of 3, discarded"
      assert log =~ "sample_id"
    end
  end
end
