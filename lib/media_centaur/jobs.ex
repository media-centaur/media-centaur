defmodule MediaCentaur.Jobs do
  use Boundary, top_level?: true, deps: []

  @moduledoc """
  The app's side of Oban (ADR-077): what happens when a job fails.

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

  This is the only module that reads Oban's job records.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Log.Component

  @handler_id __MODULE__

  @doc "Attaches the failure handler. Called once at application start."
  @spec attach() :: :ok | {:error, :already_exists}
  def attach do
    :telemetry.attach(@handler_id, [:oban, :job, :exception], &__MODULE__.handle_event/4, nil)
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

  defp worker_component(worker) do
    worker
    |> String.to_existing_atom()
    |> Component.for_module()
    |> Kernel.||(:system)
  rescue
    ArgumentError -> :system
  end

  defp short_worker(worker), do: worker |> String.split(".") |> List.last()
end
