defmodule MediaCentaur.Acquisition.CoverageGuard do
  @moduledoc """
  The physical-containment guard behind cour-aware acquisition: a
  release cannot contain an episode that aired *after* the release was
  published. Comparing a candidate's `publish_date` (a Prowlarr string)
  against each wanted episode's `air_date` is what stops a first-run
  "Season 01 COMPLETE" pack — encoded before a later cour aired — from
  being credited with that later cour's episodes.

  **Monotonic opt-in**, mirroring the planner's fit gate: a missing or
  unparseable `publish_date`, or a `nil` `air_date`, never trims (we do
  not block on data we do not have). The guard only ever *removes*
  coverage a release demonstrably cannot deliver.

  Pure module — no I/O, no DB. The impure caller (`Jobs.RunPlan`) holds
  the units' air dates and feeds `coverable_units/2` into
  `Planner.Option.coverable`.
  """

  alias MediaCentaur.Search.ReleaseCoverage

  @doc """
  Whether a release published at `publish_date` (ISO8601 string, may be
  `nil`) can physically contain an episode that aired on `air_date`
  (`Date`, may be `nil`). Unknown data on either side → `true`.
  """
  @spec can_contain?(String.t() | nil, Date.t() | nil) :: boolean()
  def can_contain?(publish_date, air_date) do
    case {parse_date(publish_date), air_date} do
      {nil, _air_date} -> true
      {_published, nil} -> true
      {published, %Date{} = aired} -> Date.compare(aired, published) != :gt
    end
  end

  @doc """
  The `Planner.Option.coverable` cap for a candidate published on
  `publish_date`, given `units` as `[{{season, episode}, air_date}]`.

  Returns `:all` (no cap) when `publish_date` is missing or unparseable,
  otherwise the `MapSet` of units the release can physically contain.
  """
  @spec coverable_units([{ReleaseCoverage.unit(), Date.t() | nil}], String.t() | nil) ::
          :all | MapSet.t(ReleaseCoverage.unit())
  def coverable_units(units, publish_date) do
    case parse_date(publish_date) do
      nil ->
        :all

      _published ->
        for {unit, air_date} <- units, can_contain?(publish_date, air_date), into: MapSet.new() do
          unit
        end
    end
  end

  # Prowlarr ships `publishDate` as a full ISO8601 timestamp; tolerate a
  # bare date too. Anything we cannot parse reads as "unknown" (no cap).
  defp parse_date(nil), do: nil

  defp parse_date(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, datetime, _offset} ->
        DateTime.to_date(datetime)

      {:error, _reason} ->
        case Date.from_iso8601(string) do
          {:ok, date} -> date
          {:error, _reason} -> nil
        end
    end
  end
end
