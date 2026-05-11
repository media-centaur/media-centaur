defmodule MediaCentarr.Acquisition.Pursuits.Commands.ChangeTarget do
  @moduledoc """
  Pivots an active pursuit to a fresh target — abandoning the current
  release attempt and starting a new search.

  Replaces v0.54/0.55's `ReSearch` command. The recipe lives on the
  pursuit, so this command is uniform regardless of how the pursuit
  was initiated:

  - **TMDB recipe** — new target enters `seeking`; the `PursueTarget`
    worker auto-picks the best Prowlarr result (excluding
    `tried_release_guids`).
  - **Prowlarr-query recipe** — new target enters `seeking`; the
    worker fetches Prowlarr results and transitions the pursuit to
    `needs_decision` for the user to pick.

  ## Side effects

  Inside one Repo transaction:

  1. Mark the previous `current_target` as `failed` (reason
     `"replaced_by_user_pivot"`) if it isn't already terminal.
  2. Insert a fresh target in `seeking` for the pursuit.
  3. Update `pursuit.current_target_id` to the new target.
  4. Record a `target_changed` event.

  After the transaction commits, enqueue `Jobs.PursueTarget` for the
  new target. The Oban insert is intentionally outside the transaction
  because Oban writes go through `Repo.insert` and we don't want a
  partial enqueue if the inner transaction rolls back.
  """

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Jobs.PursueTarget, as: PursueTargetWorker
  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit, State}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.TargetChanged
  alias MediaCentarr.Acquisition.Target
  alias MediaCentarr.Acquisition.TargetStatus
  alias MediaCentarr.Repo

  @spec execute(%{pursuit_id: Ecto.UUID.t()}) ::
          {:ok, Pursuit.t()} | {:error, :not_found | :not_eligible | term()}
  def execute(%{pursuit_id: id}) when is_binary(id) do
    with {:ok, %Pursuit{state: state} = _pursuit} <- Pursuits.get(id),
         true <- state in State.in_flight() do
      do_execute(id)
    else
      false -> {:error, :not_eligible}
      {:error, :not_found} = error -> error
    end
  end

  defp do_execute(id) do
    result =
      Runner.run(id, "pursuit target changed", fn pursuit ->
        with {:ok, _previous} <- maybe_fail_current_target(pursuit),
             {:ok, new_target} <- insert_seeking_target(pursuit),
             {:ok, updated_pursuit} <-
               Repo.update(Pursuit.set_current_target_changeset(pursuit, new_target.id)),
             {:ok, _event} <-
               Events.record(%TargetChanged{
                 pursuit_id: updated_pursuit.id,
                 pursuit_title: updated_pursuit.title,
                 occurred_at: DateTime.utc_now(:second),
                 target_id: new_target.id
               }) do
          {:ok, {updated_pursuit, new_target}}
        end
      end)

    case result do
      {:ok, {updated_pursuit, new_target}} ->
        enqueue_pursue(new_target)
        {:ok, updated_pursuit}

      other ->
        other
    end
  end

  defp maybe_fail_current_target(%Pursuit{current_target_id: nil}), do: {:ok, nil}

  defp maybe_fail_current_target(%Pursuit{current_target_id: target_id}) do
    case Repo.get(Target, target_id) do
      nil ->
        {:ok, nil}

      %Target{status: status} = target ->
        if TargetStatus.terminal?(status) do
          {:ok, target}
        else
          target
          |> Target.failed_changeset("replaced_by_user_pivot")
          |> Repo.update()
        end
    end
  end

  defp insert_seeking_target(%Pursuit{} = pursuit) do
    %{pursuit_id: pursuit.id, title: pursuit.title, origin: pursuit.origin}
    |> Target.create_changeset()
    |> Repo.insert()
  end

  defp enqueue_pursue(%Target{} = target) do
    case Oban.insert(PursueTargetWorker.new(%{"target_id" => target.id})) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Log.warning(:acquisition, "PursueTarget enqueue failed — #{inspect(reason)}")
        :ok
    end
  end
end
