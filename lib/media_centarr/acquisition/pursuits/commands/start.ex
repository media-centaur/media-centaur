defmodule MediaCentarr.Acquisition.Pursuits.Commands.Start do
  @moduledoc "Creates a pursuit when its first grab is initiated."

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Events.PursuitStarted
  alias MediaCentarr.Repo

  @doc """
  Atomically inserts a Pursuit row and records the `pursuit_started` event.
  Returns `{:ok, pursuit}` on success or `{:error, changeset}` when the
  pursuit changeset fails. Event recording goes through `Events.record/1`
  so persistence and PubSub broadcast share one write path.
  """
  @spec execute(map()) :: {:ok, Pursuit.t()} | {:error, Ecto.Changeset.t()}
  def execute(args) when is_map(args) do
    result =
      Repo.transaction(fn ->
        with {:ok, pursuit} <- Repo.insert(Pursuit.create_changeset(args)),
             {:ok, _event} <-
               Events.record(%PursuitStarted{
                 pursuit_id: pursuit.id,
                 pursuit_title: pursuit.title,
                 occurred_at: DateTime.utc_now(:second),
                 origin: pursuit.origin
               }) do
          pursuit
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, %Pursuit{title: title}} -> Log.info(:acquisition, "pursuit started — #{title}")
      _ -> :ok
    end

    result
  end
end
