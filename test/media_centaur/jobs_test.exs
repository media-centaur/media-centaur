# A failing worker named under a context, so its failure is attributed to
# that context's component.
defmodule MediaCentaur.Acquisition.JobsTestWorker do
  use Oban.Worker, queue: :acquisition, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: {:error, :upstream_unavailable}
end

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

    test "the failure is tagged with the component of the worker's context" do
      log =
        capture_log([metadata: [:component]], fn ->
          perform(MediaCentaur.Acquisition.JobsTestWorker, 3)
        end)

      assert log =~ "component=acquisition"
    end

    test "a job on its last attempt is discarded, and that is an error" do
      log = capture_log(fn -> perform(ReturnsError, 3) end)

      assert log =~ "[error]"
      assert log =~ "ReturnsError"
      assert log =~ "attempt 3 of 3, discarded"
      assert log =~ "sample_id"
    end
  end

  describe "rescue_orphans/1 — a job left executing by the last run (ADR-077, rule 8)" do
    setup do
      {:ok, job} = Oban.insert(ReturnsError.new(%{"sample_id" => 7}))
      %{job: job, booted_at: DateTime.utc_now()}
    end

    defp executing(job, attempted_at, attempt) do
      force_attrs(job, state: "executing", attempted_at: attempted_at, attempt: attempt)
    end

    defp state_of(job), do: Repo.get!(Oban.Job, job.id).state

    test "a job attempted before this boot is available again", %{job: job, booted_at: booted_at} do
      executing(job, DateTime.add(booted_at, -60), 1)

      assert %{rescued: 1, discarded: 0} = MediaCentaur.Jobs.rescue_orphans(booted_at)
      assert state_of(job) == "available"
    end

    test "a job attempted since this boot is running, and is left alone", %{
      job: job,
      booted_at: booted_at
    } do
      executing(job, DateTime.add(booted_at, 1), 1)

      assert %{rescued: 0, discarded: 0} = MediaCentaur.Jobs.rescue_orphans(booted_at)
      assert state_of(job) == "executing"
    end

    test "an orphan on its last attempt is discarded, and that is an error", %{
      job: job,
      booted_at: booted_at
    } do
      executing(job, DateTime.add(booted_at, -60), 3)

      log =
        capture_log(fn ->
          assert %{rescued: 0, discarded: 1} = MediaCentaur.Jobs.rescue_orphans(booted_at)
        end)

      assert state_of(job) == "discarded"
      assert log =~ "[error]"
      assert log =~ "ReturnsError"
    end
  end
end
