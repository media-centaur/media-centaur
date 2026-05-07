defmodule MediaCentarr.Acquisition.Pursuits.Commands.Exhaust do
  @moduledoc "Closes a pursuit at give-up time."

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Events.PursuitExhausted
  alias MediaCentarr.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, reason: reason}) when is_atom(reason) do
    case Repo.get(Pursuit, id) do
      nil ->
        {:error, :not_found}

      %Pursuit{} = pursuit ->
        tap(
          Repo.transaction(fn ->
            with {:ok, updated} <- Repo.update(Pursuit.exhaust_changeset(pursuit)),
                 {:ok, _event} <- record_event(updated, reason) do
              updated
            else
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end),
          fn
            {:ok, %Pursuit{title: t}} -> Log.info(:acquisition, "pursuit exhausted — #{t}")
            _ -> :ok
          end
        )
    end
  end

  defp record_event(pursuit, reason) do
    Events.record(%PursuitExhausted{
      pursuit_id: pursuit.id,
      pursuit_title: pursuit.title,
      occurred_at: DateTime.utc_now(:second),
      attempt_count: pursuit.attempt_count,
      reason: Atom.to_string(reason)
    })
  end
end
