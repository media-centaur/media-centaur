defmodule MediaCentaur.Acquisition.Pursuits.Commands.PickTarget do
  @moduledoc """
  Records the user's chosen release as the new target — used by both
  the decision card ("Try this one") and the manual-search submit flow.

  Replaces v0.54/0.55's `RecordUserChoice` command, and unifies it
  with the manual-grab target-creation that previously lived inline
  in `Acquisition.grab/2`.

  The pick is recorded before anything is grabbed: the release becomes a
  `grabbing` target (`Targets.start_grabbing/4`) whose `Jobs.GrabTarget`
  hands it to Prowlarr (campaign durable-work, G1). Nothing here makes an
  HTTP request.

  ## Side effects

  Inside one Repo transaction, on the units the pick covers — the
  awaiting-or-lead unit (`Units.lead/1`), plus, when the picked release
  is a pack on a TV pursuit, every other live unit of the pursuit whose
  episode the pack contains (a season pack picked for one episode lands
  the pursuit's other episodes of that season too, so their own targets
  stop searching for what is already on its way):

  1. For each covered unit: mark its previous `current_target` as
     `failed` (reason `"replaced_by_pick"`) if it isn't already terminal,
     and clear `unit.awaiting_decision_at`.
  2. Write the picked release as a `grabbing` target covering those
     units, with its grab job (`Targets.start_grabbing/4`, which also
     points each unit at it and records the pick as the unit's attempt,
     so a later `ChangeTarget` won't re-suggest the release).
  3. Record `user_decision_recorded` + `fallback_initiated` events.
  """

  alias MediaCentaur.Acquisition.CancelReasons

  alias MediaCentaur.Acquisition.Pursuits.Commands.{Helpers, Runner}
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.{FallbackInitiated, UserDecisionRecorded}
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Unit, Units, UnitState}
  alias MediaCentaur.Search.{ReleaseCoverage, SearchResult}
  alias MediaCentaur.Acquisition.Targets
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

    log_label = fn pursuit ->
      "pursuit target picked — #{pursuit.title} — #{label}"
    end

    Runner.run(id, log_label, fn pursuit ->
      # Awaiting-or-lead: a pick from the decision card lands on the
      # unit that asked for it (Units.lead_of/1 prefers the awaiting
      # unit); per-unit drill-down lands with Phase 1c.
      unit = Units.lead(pursuit.id)
      previous_guid = List.last(unit.tried_release_guids || [])
      now = DateTime.utc_now(:second)

      with {:ok, units} <- release_units(covered_units(pursuit, unit, result)),
           {:ok, _grabbing} <- Targets.start_grabbing(pursuit, result, units, origin: origin),
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
  end

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

  # Frees each covered unit for the pick: its previous target closed as
  # replaced, its pending decision answered.
  defp release_units(units) do
    Enum.reduce_while(units, {:ok, []}, fn unit, {:ok, released} ->
      with {:ok, _previous_target} <-
             Helpers.fail_current_target(unit, CancelReasons.replaced_by_pick()),
           {:ok, resumed} <- Repo.update(Unit.clear_awaiting_decision_changeset(unit)) do
        {:cont, {:ok, released ++ [resumed]}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end
end
