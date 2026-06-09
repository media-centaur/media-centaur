defmodule MediaCentaur.Acquisition.Pursuits.Commands.ChangeTarget do
  @moduledoc """
  Pivots an active pursuit's unit to a fresh target — abandoning the
  current release attempt and starting a new search.

  Replaces v0.54/0.55's `ReSearch` command. The recipe lives on the
  pursuit, so this command is uniform regardless of how the pursuit
  was initiated:

  - **TMDB recipe** — new target enters `seeking`; the `PursueTarget`
    worker auto-picks the best Prowlarr result (excluding the unit's
    `tried_release_guids`).
  - **Prowlarr-query recipe** — new target enters `seeking`; the
    worker fetches Prowlarr results and sets the unit's
    `awaiting_decision_at` flag for the user to pick.

  ## Side effects

  Inside one Repo transaction, on the pursuit's unit (`Units.single!/1`
  until unit-scoped args land — ADR-055):

  1. Mark the unit's previous `current_target` as `failed` (reason
     `"replaced_by_user_pivot"`) if it isn't already terminal.
  2. Insert a fresh target in `seeking`, covering the unit.
  3. Update `unit.current_target_id` to the new target.
  4. Record a `target_changed` event.

  After the transaction commits, enqueue `Jobs.PursueTarget` for the
  new target. The Oban insert is intentionally outside the transaction
  because Oban writes go through `Repo.insert` and we don't want a
  partial enqueue if the inner transaction rolls back.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Jobs.PursueTarget, as: PursueTargetWorker
  alias MediaCentaur.Acquisition.Pursuits
  alias MediaCentaur.Acquisition.Pursuits.Commands.Runner
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.TargetChanged
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, State, TargetUnit, Unit, UnitState, Units}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Acquisition.TargetStatus
  alias MediaCentaur.Repo

  @doc """
  Optional `:unit_id` scopes the pivot to one unit of a composite (the
  unit-board drill-down). Without it, the pivot acts on the lead unit —
  the same thread the modal displays (`Units.lead_of/1`).
  """
  @spec execute(%{pursuit_id: Ecto.UUID.t()}) ::
          {:ok, Pursuit.t()} | {:error, :not_found | :not_eligible | term()}
  def execute(%{pursuit_id: id} = args) when is_binary(id) do
    with {:ok, %Pursuit{state: state} = _pursuit} <- Pursuits.get(id),
         true <- state in State.in_flight() do
      do_execute(id, args)
    else
      false -> {:error, :not_eligible}
      {:error, :not_found} = error -> error
    end
  end

  defp do_execute(id, args) do
    result =
      Runner.run(id, "pursuit target changed", fn pursuit ->
        unit = resolve_unit(pursuit, args)

        # A terminal unit doesn't pivot — a fresh seeking target on a
        # satisfied unit would re-grab something already landed.
        with true <- unit.state in UnitState.in_flight() || {:error, :not_eligible},
             {:ok, _previous} <- maybe_fail_current_target(unit),
             {:ok, new_target} <- insert_seeking_target(pursuit),
             {:ok, _coverage} <-
               Repo.insert(TargetUnit.create_changeset(%{target_id: new_target.id, unit_id: unit.id})),
             {:ok, updated_unit} <-
               Repo.update(Unit.set_current_target_changeset(unit, new_target.id)),
             {:ok, _cleared} <-
               Repo.update(Unit.clear_awaiting_decision_changeset(updated_unit)),
             {:ok, _event} <-
               Events.record(%TargetChanged{
                 pursuit_id: pursuit.id,
                 pursuit_title: pursuit.title,
                 occurred_at: DateTime.utc_now(:second),
                 target_id: new_target.id
               }) do
          {:ok, {pursuit, new_target}}
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

  defp resolve_unit(_pursuit, %{unit_id: unit_id}) when is_binary(unit_id) do
    {:ok, unit} = Units.get(unit_id)
    unit
  end

  defp resolve_unit(pursuit, _args), do: Units.lead(pursuit.id)

  defp maybe_fail_current_target(%Unit{current_target_id: nil}), do: {:ok, nil}

  defp maybe_fail_current_target(%Unit{current_target_id: target_id}) do
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
