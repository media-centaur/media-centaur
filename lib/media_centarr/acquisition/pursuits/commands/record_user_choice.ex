defmodule MediaCentarr.Acquisition.Pursuits.Commands.RecordUserChoice do
  @moduledoc "Applies the user-picked alternative."

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
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
    case Repo.get(Pursuit, id) do
      nil ->
        {:error, :not_found}

      %Pursuit{} = pursuit ->
        tap(
          Repo.transaction(fn ->
            previous_guid = List.last(pursuit.tried_release_guids)

            with {:ok, attempted} <-
                   Repo.update(Pursuit.record_attempt_changeset(pursuit, guid)),
                 {:ok, resumed} <- Repo.update(Pursuit.resume_changeset(attempted)),
                 {:ok, _decision_event} <- record_decision(resumed, label),
                 {:ok, _fallback_event} <- record_fallback(resumed, previous_guid) do
              resumed
            else
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end),
          fn
            {:ok, %Pursuit{title: t}} ->
              Log.info(:acquisition, "user picked alternative for pursuit — #{t} — #{label}")

            _ ->
              :ok
          end
        )
    end
  end

  defp record_decision(pursuit, choice) do
    Events.record(%UserDecisionRecorded{
      pursuit_id: pursuit.id,
      pursuit_title: pursuit.title,
      occurred_at: DateTime.utc_now(:second),
      choice: choice
    })
  end

  defp record_fallback(pursuit, previous_guid) do
    Events.record(%FallbackInitiated{
      pursuit_id: pursuit.id,
      pursuit_title: pursuit.title,
      occurred_at: DateTime.utc_now(:second),
      previous_guid: previous_guid,
      reason: "user_choice"
    })
  end
end
