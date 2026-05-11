defmodule MediaCentarr.Acquisition.Pursuits.Commands.Satisfy do
  @moduledoc "Closes a pursuit on verified arrival."

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.PursuitSatisfied
  alias MediaCentarr.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, final_target_id: target_id, final_release_title: title}) do
    Runner.run(id, "pursuit satisfied", fn pursuit ->
      with {:ok, updated} <- Repo.update(Pursuit.satisfy_changeset(pursuit)),
           {:ok, _event} <-
             Events.record(%PursuitSatisfied{
               pursuit_id: updated.id,
               pursuit_title: updated.title,
               occurred_at: DateTime.utc_now(:second),
               final_target_id: target_id,
               final_release_title: title
             }) do
        {:ok, updated}
      end
    end)
  end
end
