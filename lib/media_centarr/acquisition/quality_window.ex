defmodule MediaCentarr.Acquisition.QualityWindow do
  @moduledoc """
  Pure function module computing the effective minimum quality for a grab
  at a given moment, accounting for the 4K-patience window.

  The patience window is the lever that turns "prefer 4K when present"
  into "wait for 4K to seed before settling for 1080p." While a grab is
  younger than `quality_4k_patience_hours` AND its `max_quality` includes
  4K, the effective floor is forced to `"uhd_4k"` — search filters to
  4K-only and snoozes on no-results. After patience expires, the floor
  relaxes to `min_quality`.

  No I/O, no DB. Takes a grab struct and a `DateTime` so tests can
  freeze time without touching `DateTime.utc_now/0`.
  """

  alias MediaCentarr.Acquisition.Grab

  @uhd_4k "uhd_4k"

  @spec min_at(Grab.t(), DateTime.t()) :: String.t()
  def min_at(%Grab{} = grab, %DateTime{} = now) do
    if patience_active?(grab, now), do: @uhd_4k, else: grab.min_quality
  end

  defp patience_active?(%Grab{max_quality: max}, _now) when max != @uhd_4k, do: false
  defp patience_active?(%Grab{quality_4k_patience_hours: 0}, _now), do: false

  defp patience_active?(%Grab{quality_4k_patience_hours: hours, inserted_at: inserted_at}, now) do
    elapsed_hours = DateTime.diff(now, inserted_at, :hour)
    elapsed_hours < hours
  end
end
