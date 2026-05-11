defmodule MediaCentarr.Acquisition.Pursuits.Commands.RequestDecision do
  @moduledoc "Transitions a pursuit to needs_decision."

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.UserDecisionRequested
  alias MediaCentarr.Repo

  @doc """
  Transitions an active pursuit to `:needs_decision`. Alternatives are fetched
  just-in-time when the user opens the decision card (Prowlarr re-search on
  view, excluding `tried_release_guids`) — the command itself only records
  the transition + prompt.

  Idempotent: re-issuing the command on a pursuit already in
  `:needs_decision` is a no-op and returns `{:ok, pursuit}`. This lets
  the `PursueTarget` worker call this safely on every wake without
  having to itself track whether the pursuit is already awaiting a
  user pick.
  """
  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, prompt: prompt}) when is_binary(prompt) do
    label = fn pursuit -> "pursuit needs decision — #{pursuit.title} — #{prompt}" end

    Runner.run(id, label, fn
      %Pursuit{state: "needs_decision"} = pursuit ->
        {:ok, pursuit}

      pursuit ->
        with {:ok, updated} <- Repo.update(Pursuit.request_decision_changeset(pursuit)),
             {:ok, _event} <-
               Events.record(%UserDecisionRequested{
                 pursuit_id: updated.id,
                 pursuit_title: updated.title,
                 occurred_at: DateTime.utc_now(:second),
                 prompt: prompt
               }) do
          {:ok, updated}
        end
    end)
  end
end
