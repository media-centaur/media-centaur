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

  @doc """
  Runs `fun` and returns `{result, inserts}`: every Oban job `fun`
  inserted in the calling process, oldest first, as
  `%{worker: String.t(), args: map(), in_transaction?: boolean()}`.

  `in_transaction?` is `MediaCentaur.Repo.in_transaction?/0` at the moment
  of the insert (it is `false` under the SQL sandbox outside an explicit
  transaction). It is how a test holds ADR-077 rule 1: a durable job is
  inserted in the transaction that records the decision, never after it
  commits.
  """
  @spec capture_inserts((-> result)) :: {result, [map()]} when result: term()
  def capture_inserts(fun) do
    test_pid = self()
    handler_id = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler_id,
      [:oban, :engine, :insert_job, :start],
      fn _event, _measurements, %{changeset: changeset}, _config ->
        if self() == test_pid do
          send(
            test_pid,
            {handler_id,
             %{
               worker: Ecto.Changeset.get_field(changeset, :worker),
               args: Ecto.Changeset.get_field(changeset, :args),
               in_transaction?: MediaCentaur.Repo.in_transaction?()
             }}
          )
        end
      end,
      nil
    )

    try do
      result = fun.()
      {result, collect(handler_id, [])}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp collect(handler_id, inserts) do
    receive do
      {^handler_id, insert} -> collect(handler_id, [insert | inserts])
    after
      0 -> Enum.reverse(inserts)
    end
  end

  defp queues do
    :media_centaur
    |> Application.fetch_env!(Oban)
    |> Keyword.fetch!(:queues)
    |> Keyword.keys()
  end
end
