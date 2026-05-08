defmodule MediaCentarr.Acquisition.QueueStatus do
  @moduledoc """
  Pure derivation of queue freshness status from a `QueueState` plus
  the current poll cadence.

  The status drives the queue badge in the UI and gives diagnostic
  visibility into why the queue might look stale. Cleanly separated
  from `QueueMonitor` so the contract is testable without spinning up
  the GenServer.

  ## Status grades

  - `:initializing` — no successful poll has happened yet and no error
    has been recorded. Common during startup or right after a settings
    change.
  - `:live` — last successful poll happened within `2 × cadence_ms`.
    UI should look real-time.
  - `{:lagging, age_ms}` — last poll is between `2×` and `5×` cadence
    old. UI shows numbers but the user should know they're stale.
  - `{:offline, since}` — beyond `5× cadence` or an explicit
    unreachable error from the client.
  - `:auth_failed` — re-authentication failed; surface a "reconfigure"
    affordance rather than a generic offline.
  - `:not_configured` — no download client configured at all.

  Explicit errors on the state always win over age-based classification.
  """

  alias MediaCentarr.Acquisition.QueueState

  @type status ::
          :initializing
          | :live
          | {:lagging, age_ms :: non_neg_integer()}
          | {:offline, since :: DateTime.t()}
          | :auth_failed
          | :not_configured

  @spec derive(QueueState.t(), pos_integer(), DateTime.t()) :: status()
  def derive(%QueueState{} = state, cadence_ms, now \\ DateTime.utc_now())
      when is_integer(cadence_ms) and cadence_ms > 0 do
    case state.last_error do
      :not_configured -> :not_configured
      :auth_failed -> :auth_failed
      {:offline, since} -> {:offline, since}
      _ -> classify_age(state.last_successful_poll_at, cadence_ms, now)
    end
  end

  defp classify_age(nil, _cadence_ms, _now), do: :initializing

  defp classify_age(%DateTime{} = ts, cadence_ms, now) do
    age = DateTime.diff(now, ts, :millisecond)

    cond do
      age <= cadence_ms * 2 -> :live
      age <= cadence_ms * 5 -> {:lagging, age}
      true -> {:offline, ts}
    end
  end
end
