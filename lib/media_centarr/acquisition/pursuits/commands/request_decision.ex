defmodule MediaCentarr.Acquisition.Pursuits.Commands.RequestDecision do
  @moduledoc "Transitions a pursuit to needs_decision."

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Events.UserDecisionRequested
  alias MediaCentarr.Repo

  @doc """
  Transitions an active pursuit to `:needs_decision`. Alternatives are fetched
  just-in-time when the user opens the decision card (Prowlarr re-search on
  view, excluding `tried_release_guids`) — the command itself only records
  the transition + prompt.
  """
  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, prompt: prompt}) when is_binary(prompt) do
    case Repo.get(Pursuit, id) do
      nil ->
        {:error, :not_found}

      %Pursuit{} = pursuit ->
        tap(
          Repo.transaction(fn ->
            with {:ok, updated} <- Repo.update(Pursuit.request_decision_changeset(pursuit)),
                 {:ok, _event} <- record_event(updated, prompt) do
              updated
            else
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end),
          fn
            {:ok, %Pursuit{title: t}} ->
              Log.info(:acquisition, "pursuit needs decision — #{t} — #{prompt}")

            _ ->
              :ok
          end
        )
    end
  end

  defp record_event(pursuit, prompt) do
    Events.record(%UserDecisionRequested{
      pursuit_id: pursuit.id,
      pursuit_title: pursuit.title,
      occurred_at: DateTime.utc_now(:second),
      prompt: prompt
    })
  end
end
