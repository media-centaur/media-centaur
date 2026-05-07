defmodule MediaCentarr.Acquisition.Pursuits.Commands.Cancel do
  @moduledoc "Closes a pursuit by user request."

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Events.PursuitCancelled
  alias MediaCentarr.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, cancelled_by: by, reason: reason})
      when is_atom(by) and is_binary(reason) do
    case Repo.get(Pursuit, id) do
      nil ->
        {:error, :not_found}

      %Pursuit{} = pursuit ->
        tap(
          Repo.transaction(fn ->
            with {:ok, updated} <- Repo.update(Pursuit.cancel_changeset(pursuit)),
                 {:ok, _event} <- record_event(updated, by, reason) do
              updated
            else
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end),
          fn
            {:ok, %Pursuit{title: t}} -> Log.info(:acquisition, "pursuit cancelled — #{t}")
            _ -> :ok
          end
        )
    end
  end

  defp record_event(pursuit, cancelled_by, reason) do
    Events.record(%PursuitCancelled{
      pursuit_id: pursuit.id,
      pursuit_title: pursuit.title,
      occurred_at: DateTime.utc_now(:second),
      cancelled_by: Atom.to_string(cancelled_by),
      reason: reason
    })
  end
end
