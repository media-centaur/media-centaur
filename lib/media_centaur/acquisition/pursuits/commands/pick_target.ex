defmodule MediaCentaur.Acquisition.Pursuits.Commands.PickTarget do
  @moduledoc """
  Records the user's chosen release as the new target — used by both
  the decision card ("Try this one") and the manual-search submit flow.

  Replaces v0.54/0.55's `RecordUserChoice` command, and unifies it
  with the manual-grab target-creation that previously lived inline
  in `Acquisition.grab/2`.

  Caller is responsible for the Prowlarr HTTP submit (`Prowlarr.grab/1`)
  *before* invoking this command — atomicity is bounded to the unit
  + target rows + events.

  ## Side effects

  Inside one Repo transaction, on the units the pick covers — the
  awaiting-or-lead unit (`Units.lead/1`), plus, when the picked release
  is a pack on a TV pursuit, every other live unit of the pursuit whose
  episode the pack contains (a season pack picked for one episode lands
  the pursuit's other episodes of that season too, so their own targets
  stop searching for what is already on its way):

  1. Insert a new target in `acquired` carrying the picked release's
     guid / title / quality.
  2. For each covered unit: mark its previous `current_target` as
     `failed` (reason `"replaced_by_pick"`) if it isn't already terminal,
     record the coverage row, point `unit.current_target_id` at the new
     target, bump `unit.attempt_count` and append the picked guid to
     `unit.tried_release_guids` (so a subsequent `ChangeTarget` won't
     re-suggest the same release), and clear `unit.awaiting_decision_at`.
  3. Record `user_decision_recorded` + `fallback_initiated` events.
  """

  alias MediaCentaur.Acquisition.CancelReasons

  alias MediaCentaur.Acquisition.Pursuits.Commands.{Helpers, Runner}
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.{FallbackInitiated, UserDecisionRecorded}
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, TargetUnit, Unit, Units, UnitState}
  alias MediaCentaur.Search.{ReleaseCoverage, SearchResult}
  alias MediaCentaur.Acquisition.{InfoHash, Target}
  alias MediaCentaur.Downloads.QueueMonitor
  alias MediaCentaur.Repo

  @doc """
  Records the picked release on a pursuit.

  Required: `pursuit_id`, `result :: SearchResult.t()`, `choice_label :: String.t()`.
  Optional: `origin :: "auto" | "manual"` (defaults to `"manual"`).
  """
  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, result: %SearchResult{} = result, choice_label: label} = args)
      when is_binary(label) do
    origin = Map.get(args, :origin, "manual")
    torrent_hash = InfoHash.resolve(result)

    log_label = fn pursuit ->
      "pursuit target picked — #{pursuit.title} — #{label}"
    end

    id
    |> Runner.run(log_label, fn pursuit ->
      # Awaiting-or-lead: a pick from the decision card lands on the
      # unit that asked for it (Units.lead_of/1 prefers the awaiting
      # unit); per-unit drill-down lands with Phase 1c.
      unit = Units.lead(pursuit.id)
      previous_guid = List.last(unit.tried_release_guids || [])
      now = DateTime.utc_now(:second)

      with {:ok, new_target} <- insert_acquired_target(pursuit, result, origin, torrent_hash),
           :ok <- cover(covered_units(pursuit, unit, result), new_target, result),
           {:ok, _decision_event} <-
             Events.record(%UserDecisionRecorded{
               pursuit_id: pursuit.id,
               pursuit_title: pursuit.title,
               occurred_at: now,
               choice: label
             }),
           {:ok, _fallback_event} <-
             Events.record(%FallbackInitiated{
               pursuit_id: pursuit.id,
               pursuit_title: pursuit.title,
               occurred_at: now,
               previous_guid: previous_guid,
               reason: "user_choice"
             }) do
        {:ok, pursuit}
      end
    end)
    |> tap(&hurry_the_queue_along/1)
  end

  # Prowlarr has just pushed this release to the download client, so the cached
  # queue snapshot is known-stale at exactly the moment the user is watching
  # the pursuit for a sign of life. Ask for a fresh one instead of waiting out
  # the 10-30 s cadence.
  defp hurry_the_queue_along({:ok, %Pursuit{}}), do: QueueMonitor.poll_now()
  defp hurry_the_queue_along(_error), do: :ok

  # The lead unit always; on a TV pursuit, every other live unit whose
  # episode the picked release's scope contains as well.
  defp covered_units(%Pursuit{recipe_type: "tmdb", tmdb_type: "tv"} = pursuit, %Unit{} = lead, result) do
    scope = ReleaseCoverage.classify(result.title)

    others =
      pursuit.id
      |> Units.for_pursuit()
      |> Enum.filter(fn unit ->
        unit.id != lead.id and not UnitState.terminal?(unit.state) and
          is_integer(unit.season_number) and is_integer(unit.episode_number) and
          ReleaseCoverage.covers?(scope, unit.season_number, unit.episode_number)
      end)

    [lead | others]
  end

  defp covered_units(%Pursuit{}, %Unit{} = lead, _result), do: [lead]

  defp cover(units, %Target{} = target, %SearchResult{} = result) do
    Enum.reduce_while(units, :ok, fn unit, :ok ->
      with {:ok, _previous_target} <-
             Helpers.fail_current_target(unit, CancelReasons.replaced_by_pick()),
           {:ok, _coverage} <-
             Repo.insert(TargetUnit.create_changeset(%{target_id: target.id, unit_id: unit.id})),
           {:ok, attempted} <- Repo.update(Unit.record_attempt_changeset(unit, result.guid)),
           {:ok, with_target} <- Repo.update(Unit.set_current_target_changeset(attempted, target.id)),
           {:ok, _resumed} <- Repo.update(Unit.clear_awaiting_decision_changeset(with_target)) do
        {:cont, :ok}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp insert_acquired_target(%Pursuit{} = pursuit, %SearchResult{} = result, origin, torrent_hash) do
    result
    |> Target.acquired_changeset(pursuit_id: pursuit.id, origin: origin, torrent_hash: torrent_hash)
    |> Repo.insert()
  end
end
