defmodule MediaCentarr.Acquisition.Pursuits.Policy do
  @moduledoc """
  Pure decision function mapping a `Snapshot` to an `Action`.

  Inputs are a frozen snapshot built by `Snapshots.build/1`. There is no
  I/O, no DB access, no PubSub. Every code path is exercised by
  `PolicyTest` against constructed snapshots.

  Rules, in evaluation order:

  1. Pursuit already terminal → `:no_action`
  2. Pursuit awaiting user input (`awaiting_decision_at` set) → `:no_action`
  3. Sustained zero-seeders confirmed → `{:auto_cancel, :zero_seeders}`
  4. Sustained stall confirmed → `{:request_decision, prompt}`
  5. Exhaustion budget reached → `{:exhaust, :max_attempts}`
  6. Otherwise → `:no_action`

  Stall and zero-seeders rules fire only when the corresponding window has
  elapsed (`*_window_elapsed?` derived in `Snapshots`). Until observation
  state is populated by the Watcher, those flags are `nil` (cond branches
  short-circuit safely on falsy).
  """

  alias MediaCentarr.Acquisition.Pursuits.{Action, Snapshot, State}

  @spec evaluate(Snapshot.t()) :: Action.t()
  def evaluate(%Snapshot{} = snapshot) do
    cond do
      State.terminal?(snapshot.pursuit.state) -> :no_action
      State.awaiting_decision?(snapshot.pursuit) -> :no_action
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

  defp exhaustion_reached?(%Snapshot{pursuit: pursuit, now: now, thresholds: thresholds}) do
    pursuit.attempt_count >= thresholds.max_attempts and
      DateTime.diff(now, pursuit.inserted_at, :day) >= thresholds.min_age_days
  end
end
