defmodule MediaCentaur.Acquisition.Pursuits.Policy do
  @moduledoc """
  Pure decision function mapping a `Snapshot` to an `Action`.

  Inputs are a frozen snapshot built by `Snapshots.build/4`. There is no
  I/O, no DB access, no PubSub. Every code path is exercised by
  `PolicyTest` against constructed snapshots.

  The snapshot is unit-scoped (ADR-055): the attempt thread — decision
  flag, attempt count, observation windows — lives on the unit, and the
  emitted action targets that unit.

  Rules, in evaluation order:

  1. Pursuit or unit already terminal → `:no_action`
  2. Unit awaiting user input (`awaiting_decision_at` set) → `:no_action`
  3. Sustained zero-seeders confirmed → `{:auto_cancel, :zero_seeders}`
  4. Sustained stall confirmed → `{:request_decision, prompt}`
  5. Exhaustion budget reached → `{:exhaust, :max_attempts}`
  6. Otherwise → `:no_action`

  Stall and zero-seeders rules fire only when the corresponding window has
  elapsed (`*_window_elapsed?` derived in `Snapshots`). Until observation
  state is populated by the Watcher, those flags are `nil` (cond branches
  short-circuit safely on falsy).
  """

  alias MediaCentaur.Acquisition.Pursuits.{Action, Snapshot, State, UnitState}

  @spec evaluate(Snapshot.t()) :: Action.t()
  def evaluate(%Snapshot{} = snapshot) do
    cond do
      State.terminal?(snapshot.pursuit.state) -> :no_action
      UnitState.terminal?(snapshot.unit.state) -> :no_action
      UnitState.awaiting_decision?(snapshot.unit) -> :no_action
      zero_seeders_confirmed?(snapshot) -> {:auto_cancel, :zero_seeders}
      stall_confirmed?(snapshot) -> {:request_decision, stall_prompt(snapshot)}
      exhaustion_reached?(snapshot) -> {:exhaust, :max_attempts}
      true -> :no_action
    end
  end

  defp zero_seeders_confirmed?(%Snapshot{
         zero_seeders_observed?: true,
         zero_seeders_window_elapsed?: true
       }), do: true

  defp zero_seeders_confirmed?(_), do: false

  defp stall_confirmed?(%Snapshot{stall_observed?: true, stall_window_elapsed?: true}), do: true
  defp stall_confirmed?(_), do: false

  defp stall_prompt(%Snapshot{thresholds: %{stall_window_hours: hours}}),
    do: "Download stalled for #{hours}+ hours — pick an alternative release."

  defp exhaustion_reached?(%Snapshot{unit: unit, now: now, thresholds: thresholds}) do
    unit.attempt_count >= thresholds.max_attempts and
      DateTime.diff(now, unit.inserted_at, :day) >= thresholds.min_age_days
  end
end
