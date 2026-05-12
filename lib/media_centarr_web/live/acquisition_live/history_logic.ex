defmodule MediaCentarrWeb.AcquisitionLive.HistoryLogic do
  @moduledoc """
  Pure helpers for the History zone of the unified Downloads page —
  extracted per the LiveView logic-extraction policy ([ADR-030]).
  Tested in isolation with `async: true` and struct literals.

  Operates on `PursuitRow` view-models, not raw `Target` rows. The
  zone shows one row per pursuit (filtered by lifecycle bucket), so
  per-target table helpers (origin/status badges, last-attempt
  summaries) no longer live here.
  """

  alias MediaCentarr.Acquisition.ViewModels.PursuitRow

  @filter_atoms [:failed, :cancelled, :succeeded, :all]

  @doc """
  Filters a list of `PursuitRow` view-models by case-insensitive
  substring match on either the show title (`title`) or the release
  filename (`release_title`). An empty needle returns the input unchanged.
  """
  @spec filter_pursuit_rows_by_search([PursuitRow.t()], String.t()) :: [PursuitRow.t()]
  def filter_pursuit_rows_by_search(rows, ""), do: rows

  def filter_pursuit_rows_by_search(rows, search) do
    needle = String.downcase(search)

    Enum.filter(rows, fn %PursuitRow{title: title, release_title: release} ->
      contains?(title, needle) or contains?(release, needle)
    end)
  end

  defp contains?(nil, _needle), do: false
  defp contains?(value, needle), do: String.contains?(String.downcase(value), needle)

  @doc """
  Parses a `?filter=` URL value or a `phx-value-filter` event value
  into the filter atom. Unknown or absent values default to `:failed`
  — the attention-worthy bucket.
  """
  @spec parse_filter(String.t() | nil) :: :failed | :cancelled | :succeeded | :all
  def parse_filter("failed"), do: :failed
  def parse_filter("cancelled"), do: :cancelled
  def parse_filter("succeeded"), do: :succeeded
  def parse_filter("all"), do: :all
  def parse_filter(_), do: :failed

  @doc "Every filter atom in the order the chips render."
  @spec filter_atoms() :: [atom()]
  def filter_atoms, do: @filter_atoms

  @spec filter_label(atom()) :: String.t()
  def filter_label(:failed), do: "Failed"
  def filter_label(:cancelled), do: "Cancelled"
  def filter_label(:succeeded), do: "Succeeded"
  def filter_label(:all), do: "All"

  @doc """
  Maps a History filter atom to the corresponding `Pursuits.list_rows/1`
  bucket. `:all` is the only renaming — `Pursuits` calls it
  `:all_terminal` for clarity at the read-layer (where "all" without a
  qualifier is ambiguous between "every pursuit ever" and "every
  terminal pursuit").
  """
  @spec list_rows_filter(atom()) :: :failed | :cancelled | :succeeded | :all_terminal
  def list_rows_filter(:failed), do: :failed
  def list_rows_filter(:cancelled), do: :cancelled
  def list_rows_filter(:succeeded), do: :succeeded
  def list_rows_filter(:all), do: :all_terminal

  @spec empty_state(atom()) :: String.t()
  def empty_state(:failed), do: "Nothing has failed."
  def empty_state(:cancelled), do: "Nothing has been cancelled."
  def empty_state(:succeeded), do: "Nothing has finished yet."
  def empty_state(:all), do: "No past pursuits on record."
end
