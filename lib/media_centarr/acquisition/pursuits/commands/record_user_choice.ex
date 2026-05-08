defmodule MediaCentarr.Acquisition.Pursuits.Commands.RecordUserChoice do
  @moduledoc "Applies the user-picked alternative."

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.{FallbackInitiated, UserDecisionRecorded}
  alias MediaCentarr.Repo

  @doc """
  Records the user's pick on a `needs_decision` pursuit and resumes it.

  Caller is responsible for the actual Prowlarr grab + new Grab insertion;
  this command handles the pursuit-side bookkeeping (state transition,
  attempt accounting, events). Splitting these is intentional — Prowlarr
  is HTTP and cannot share an Ecto transaction, so atomicity is bounded
  to the pursuit row + events.
  """
  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, chosen_guid: guid, choice_label: label})
      when is_binary(guid) and is_binary(label) do
    log_label = fn pursuit -> "user picked alternative for pursuit — #{pursuit.title} — #{label}" end

    Runner.run(id, log_label, fn pursuit ->
      previous_guid = List.last(pursuit.tried_release_guids)
      now = DateTime.utc_now(:second)

      with {:ok, attempted} <-
             Repo.update(Pursuit.record_attempt_changeset(pursuit, guid)),
           {:ok, resumed} <- Repo.update(Pursuit.resume_changeset(attempted)),
           {:ok, _decision_event} <-
             Events.record(%UserDecisionRecorded{
               pursuit_id: resumed.id,
               pursuit_title: resumed.title,
               occurred_at: now,
               choice: label
             }),
           {:ok, _fallback_event} <-
             Events.record(%FallbackInitiated{
               pursuit_id: resumed.id,
               pursuit_title: resumed.title,
               occurred_at: now,
               previous_guid: previous_guid,
               reason: "user_choice"
             }) do
        {:ok, resumed}
      end
    end)
  end
end
