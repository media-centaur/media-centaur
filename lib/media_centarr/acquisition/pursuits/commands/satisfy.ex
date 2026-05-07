defmodule MediaCentarr.Acquisition.Pursuits.Commands.Satisfy do
  @moduledoc "Closes a pursuit on verified arrival."

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Events.PursuitSatisfied
  alias MediaCentarr.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, final_grab_id: grab_id, final_release_title: title}) do
    case Repo.get(Pursuit, id) do
      nil ->
        {:error, :not_found}

      %Pursuit{} = pursuit ->
        tap(
          Repo.transaction(fn ->
            with {:ok, updated} <- Repo.update(Pursuit.satisfy_changeset(pursuit)),
                 {:ok, _event} <- record_event(updated, grab_id, title) do
              updated
            else
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end),
          fn
            {:ok, %Pursuit{title: t}} -> Log.info(:acquisition, "pursuit satisfied — #{t}")
            _ -> :ok
          end
        )
    end
  end

  defp record_event(pursuit, grab_id, release_title) do
    Events.record(%PursuitSatisfied{
      pursuit_id: pursuit.id,
      pursuit_title: pursuit.title,
      occurred_at: DateTime.utc_now(:second),
      final_grab_id: grab_id,
      final_release_title: release_title
    })
  end
end
