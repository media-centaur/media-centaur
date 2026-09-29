defmodule MediaCentaur.JobRuns do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Runs the Oban jobs a test has enqueued, as production's queues would.

  The suite runs Oban in `testing: :manual` (ADR-077, rule 10): an insert
  stores the job and runs nothing, exactly as in production, where the
  insert commits with the decision that owes it and a queue picks it up
  afterwards. A test that needs the work done calls
  `run_enqueued_jobs/0` after the act that enqueued it.
  """

  @doc """
  Drains every configured queue until no available job is left — a job
  that enqueues another (a committed plan's `PursueTarget`) is run too, in
  whichever queue it lands. Scheduled and snoozed jobs are not run: they
  are not due. A job that raises re-raises here, so the test fails on it.
  """
  @spec run_enqueued_jobs() :: :ok
  def run_enqueued_jobs do
    ran =
      Enum.reduce(queues(), 0, fn queue, ran ->
        result = Oban.drain_queue(queue: queue, with_recursion: true, with_safety: false)
        ran + result.success + result.failure + result.cancelled + result.discard
      end)

    if ran > 0, do: run_enqueued_jobs(), else: :ok
  end

  defp queues do
    :media_centaur
    |> Application.fetch_env!(Oban)
    |> Keyword.fetch!(:queues)
    |> Keyword.keys()
  end
end
