defmodule MediaCentaur.Jobs do
  use Boundary, top_level?: true, deps: []

  @moduledoc """
  The app's side of Oban (ADR-077): what happens when a job fails, and
  what happens to a job the last run left executing.

  ## Failures

  Oban records a failed attempt in `oban_jobs.errors` and nowhere else.
  `attach/0` subscribes to `[:oban, :job, :exception]` so every failure
  reaches the Console, and through it ErrorReports and Status, tagged with
  the component of the context that owns the worker
  (`Log.Component.for_module/1`):

    * an attempt Oban will retry after the worker **returned** `{:error, _}`
      is a warning kept out of incidents (`mc_incident: :skip`) — the worker
      said it expected to be asked again, as with a transient upstream error;
    * an attempt Oban will retry after the worker **raised, crashed or timed
      out** is a warning that reaches incidents — a retry may succeed, but
      the crash is still a defect;
    * a **discarded** job — its last attempt failed — is an error.

  ## Orphaned jobs

  A job still `executing` when the node stops — a crash, or a job that
  outran Oban's shutdown grace period — stays `executing` in the database.
  `rescue_orphans/1` runs at boot and makes every job attempted *before
  this boot* available again, or discards it when that was its last
  attempt. The app runs one node per database (Oban's `Peers.Isolated`
  assumes the same), so a job attempted before this node started cannot
  still be running: the rescue is exact, needs no guess at how long a job
  may take, and a job the new queues pick up is never touched. Oban's
  time-based `Lifeline` plugin was declined for that reason — a plan run
  legitimately takes tens of minutes.

  This is the only module that reads or writes Oban's job records.
  """

  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Log.Component
  alias MediaCentaur.Repo

  @handler_id __MODULE__

  @doc "Attaches the failure handler. Called once at application start."
  @spec attach() :: :ok | {:error, :already_exists}
  def attach do
    :telemetry.attach(@handler_id, [:oban, :job, :exception], &__MODULE__.handle_event/4, nil)
  end

  @doc """
  Makes every job left `executing` by a run before `booted_at` available
  again — or discarded, when it had used its last attempt. Returns the
  counts. Called once at boot, with a time taken before Oban started.
  """
  @spec rescue_orphans(DateTime.t()) :: %{rescued: non_neg_integer(), discarded: non_neg_integer()}
  def rescue_orphans(%DateTime{} = booted_at) do
    orphans = where(Oban.Job, [job], job.state == "executing" and job.attempted_at < ^booted_at)

    {discarded, discarded_jobs} =
      orphans
      |> where([job], job.attempt >= job.max_attempts)
      |> select([job], job)
      |> Repo.update_all(set: [state: "discarded", discarded_at: DateTime.utc_now()])

    {rescued, rescued_jobs} =
      orphans
      |> where([job], job.attempt < job.max_attempts)
      |> select([job], job)
      |> Repo.update_all(set: [state: "available"])

    Enum.each(discarded_jobs, fn job ->
      Log.error(worker_component(job.worker), fn -> describe_orphan(job, "discarded") end)
    end)

    Enum.each(rescued_jobs, fn job ->
      Log.info(worker_component(job.worker), fn -> describe_orphan(job, "available again") end)
    end)

    %{rescued: rescued, discarded: discarded}
  end

  @doc false
  def handle_event(
        [:oban, :job, :exception],
        _measurements,
        %{job: job, state: state, reason: reason},
        _config
      ) do
    component = worker_component(job.worker)
    message = fn -> describe(job, state, reason) end

    case {state, reason} do
      {:discard, _reason} -> Log.error(component, message)
      {_retry, %Oban.PerformError{}} -> Log.warning(component, message, mc_incident: :skip)
      {_retry, _raised} -> Log.warning(component, message)
    end
  end

  defp describe(job, state, reason) do
    outcome = if state == :discard, do: "discarded", else: "will retry"

    "job #{short_worker(job.worker)} ##{job.id} failed, attempt #{job.attempt} of " <>
      "#{job.max_attempts}, #{outcome} — #{Exception.message(reason)} — args #{inspect(job.args)}"
  end

  defp describe_orphan(job, outcome) do
    "job #{short_worker(job.worker)} ##{job.id} was left executing by the last run " <>
      "(attempt #{job.attempt} of #{job.max_attempts}), #{outcome} — args #{inspect(job.args)}"
  end

  # Oban stores the worker without the `Elixir.` prefix its atom carries.
  defp worker_component(worker) do
    ("Elixir." <> worker)
    |> String.to_existing_atom()
    |> Component.for_module()
    |> Kernel.||(:system)
  rescue
    ArgumentError -> :system
  end

  defp short_worker(worker), do: worker |> String.split(".") |> List.last()
end
