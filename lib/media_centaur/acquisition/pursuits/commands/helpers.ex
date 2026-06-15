defmodule MediaCentaur.Acquisition.Pursuits.Commands.Helpers do
  @moduledoc """
  Shared building blocks for the pursuit command modules (ChangeTarget,
  AutoCancel, PickTarget). Each is a small, side-effecting step that more
  than one command performs identically; keeping one copy here stops the
  commands drifting (e.g. one forgetting to fail the prior target before
  seeking a new one).
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Jobs.PursueTarget, as: PursueTargetWorker
  alias MediaCentaur.Acquisition.{Target, TargetStatus}
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Unit}
  alias MediaCentaur.Repo

  @doc "Inserts a fresh `:seeking` target for the pursuit."
  @spec insert_seeking_target(Pursuit.t()) :: {:ok, Target.t()} | {:error, Ecto.Changeset.t()}
  def insert_seeking_target(%Pursuit{} = pursuit) do
    %{pursuit_id: pursuit.id, title: pursuit.title, origin: pursuit.origin}
    |> Target.create_changeset()
    |> Repo.insert()
  end

  @doc """
  Enqueues the PursueTarget worker for `target`. Always returns `:ok` — an
  enqueue failure is logged, not propagated, so it can't roll back the
  surrounding command transaction.
  """
  @spec enqueue_pursue(Target.t()) :: :ok
  def enqueue_pursue(%Target{} = target) do
    case Oban.insert(PursueTargetWorker.new(%{"target_id" => target.id})) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Log.warning(:acquisition, "PursueTarget enqueue failed — #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Fails the unit's current target (if any, and not already terminal) with
  `reason`, so a replacement can be sought. Returns `{:ok, prior_target |
  nil}` or the failed-update result.
  """
  @spec fail_current_target(Unit.t(), String.t()) ::
          {:ok, Target.t() | nil} | {:error, Ecto.Changeset.t()}
  def fail_current_target(%Unit{current_target_id: nil}, _reason), do: {:ok, nil}

  def fail_current_target(%Unit{current_target_id: target_id}, reason) do
    case Repo.get(Target, target_id) do
      nil ->
        {:ok, nil}

      %Target{status: status} = target ->
        if TargetStatus.terminal?(status) do
          {:ok, target}
        else
          target
          |> Target.failed_changeset(reason)
          |> Repo.update()
        end
    end
  end
end
