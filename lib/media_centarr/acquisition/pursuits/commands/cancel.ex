defmodule MediaCentarr.Acquisition.Pursuits.Commands.Cancel do
  @moduledoc "Closes a pursuit by user request."

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.PursuitCancelled
  alias MediaCentarr.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, cancelled_by: by, reason: reason})
      when is_atom(by) and is_binary(reason) do
    Runner.run(id, "pursuit cancelled", fn pursuit ->
      with {:ok, updated} <- Repo.update(Pursuit.cancel_changeset(pursuit)),
           {:ok, _event} <-
             Events.record(%PursuitCancelled{
               pursuit_id: updated.id,
               pursuit_title: updated.title,
               occurred_at: DateTime.utc_now(:second),
               cancelled_by: Atom.to_string(by),
               reason: reason
             }) do
        {:ok, updated}
      end
    end)
  end
end
