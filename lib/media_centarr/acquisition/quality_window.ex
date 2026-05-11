defmodule MediaCentarr.Acquisition.QualityWindow do
  @moduledoc """
  Pure function module computing the effective minimum quality for a
  pursuit at a given moment, accounting for the 4K-patience window.

  The patience window is the lever that turns "prefer 4K when present"
  into "wait for 4K to seed before settling for 1080p." While a pursuit
  is younger than `quality_4k_patience_hours` AND its `max_quality`
  includes 4K, the effective floor is forced to `"uhd_4k"` — search
  filters to 4K-only and snoozes on no-results. After patience expires,
  the floor relaxes to `min_quality`.

  No I/O, no DB. Takes a snapshot map (`%{min_quality, max_quality,
  quality_4k_patience_hours, inserted_at}`) and a `DateTime` so tests
  can freeze time without touching `DateTime.utc_now/0`. The worker
  constructs the snapshot from the pursuit's `criteria` map; callers
  in other surfaces (audit displays, settings preview) construct it
  in-line.
  """

  @uhd_4k "uhd_4k"

  @type snapshot :: %{
          required(:min_quality) => String.t() | nil,
          required(:max_quality) => String.t() | nil,
          required(:quality_4k_patience_hours) => integer() | nil,
          required(:inserted_at) => DateTime.t() | NaiveDateTime.t()
        }

  @spec min_at(snapshot(), DateTime.t()) :: String.t() | nil
  def min_at(snapshot, %DateTime{} = now) when is_map(snapshot) do
    if patience_active?(snapshot, now), do: @uhd_4k, else: Map.get(snapshot, :min_quality)
  end

  defp patience_active?(%{max_quality: max}, _now) when max != @uhd_4k, do: false
  defp patience_active?(%{quality_4k_patience_hours: nil}, _now), do: false
  defp patience_active?(%{quality_4k_patience_hours: 0}, _now), do: false

  defp patience_active?(%{quality_4k_patience_hours: hours, inserted_at: inserted_at}, now) do
    elapsed_hours = DateTime.diff(now, inserted_at, :hour)
    elapsed_hours < hours
  end
end
