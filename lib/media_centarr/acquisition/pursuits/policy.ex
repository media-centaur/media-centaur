defmodule MediaCentarr.Acquisition.Pursuits.Policy do
  @moduledoc """
  Pure decision function mapping a `Snapshot` to an `Action`.

  Inputs are a frozen snapshot built by `Snapshots.build/1`. There is no
  I/O, no DB access, no PubSub. Every code path is exercised by
  `PolicyTest` against constructed snapshots.

  ## v1 scope

  Implements the **exhaustion** rule (`attempt_count` ≥ threshold AND
  pursuit older than deadline → `{:exhaust, :max_attempts}`).

  Stall and zero-seeder rules are intentionally **deferred to a follow-up
  iteration** because correct sliding-window detection requires
  persistence we don't yet have (per-pursuit health-observation history).
  Until that lands, the Watcher records the pursuit's `attempt_count` and
  age; user-visible stall handling happens manually via the decision
  card. The architectural shape — Snapshot → Policy → Action → Command —
  is in place so adding the rules later is purely additive.
  """

  alias MediaCentarr.Acquisition.Pursuits.{Action, Snapshot, State}

  # Default thresholds. Configurable via `MediaCentarr.Config` in a
  # follow-up; for now these are baked in so Policy stays pure.
  @max_attempts 4
  @min_age_days 6

  @spec evaluate(Snapshot.t()) :: Action.t()
  def evaluate(%Snapshot{pursuit: pursuit, now: now}) do
    cond do
      State.terminal?(pursuit.state) -> :no_action
      pursuit.state == "needs_decision" -> :no_action
      exhaustion_reached?(pursuit, now) -> {:exhaust, :max_attempts}
      true -> :no_action
    end
  end

  defp exhaustion_reached?(pursuit, now) do
    pursuit.attempt_count >= @max_attempts and
      DateTime.diff(now, pursuit.inserted_at, :day) >= @min_age_days
  end
end
