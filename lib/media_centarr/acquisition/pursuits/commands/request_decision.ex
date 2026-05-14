defmodule MediaCentarr.Acquisition.Pursuits.Commands.RequestDecision do
  @moduledoc "Sets the pursuit's awaiting-decision flag and records the prompt."

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.UserDecisionRequested
  alias MediaCentarr.Repo

  @doc """
  Sets `awaiting_decision_at` on the pursuit and records a
  `user_decision_requested` event with the prompt. The pursuit's
  lifecycle state is unchanged — it's still `active`, just blocked on
  user input. Alternatives are fetched just-in-time when the user opens
  the decision card.

  Idempotent: re-issuing the command on a pursuit that already has
  `awaiting_decision_at` set is a no-op and returns `{:ok, pursuit}`.
  This lets the `PursueTarget` worker call this safely on every wake
  without having to itself track whether the pursuit is already
  awaiting a user pick.
  """
  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, prompt: prompt}) when is_binary(prompt) do
    label = fn pursuit -> "pursuit awaiting decision — #{pursuit.title} — #{prompt}" end
    now = DateTime.utc_now(:second)

    Runner.run(id, label, fn
      %Pursuit{awaiting_decision_at: %DateTime{}} = pursuit ->
        {:ok, pursuit}

      pursuit ->
        with {:ok, updated} <-
               Repo.update(Pursuit.set_awaiting_decision_changeset(pursuit, now)),
             {:ok, _event} <-
               Events.record(%UserDecisionRequested{
                 pursuit_id: updated.id,
                 pursuit_title: updated.title,
                 occurred_at: now,
                 prompt: prompt
               }) do
          {:ok, updated}
        end
    end)
  end
end
