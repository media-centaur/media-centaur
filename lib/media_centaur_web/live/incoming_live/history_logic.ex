defmodule MediaCentaurWeb.IncomingLive.HistoryLogic do
  @moduledoc """
  Pure helpers for the History zone of the unified Downloads page —
  extracted per the LiveView logic-extraction policy ([ADR-030]).
  Tested in isolation with `async: true` and struct literals.

  Operates on `PursuitRow` view-models, not raw `Target` rows. The
  zone shows one row per pursuit (filtered by lifecycle bucket), so
  per-target table helpers (origin/status badges, last-attempt
  summaries) no longer live here.
  """

  alias MediaCentaur.Acquisition.ViewModels.PursuitRow

  # :all leads — it is the History tab's default face; the lifecycle
  # slices follow.
  @filter_atoms [:all, :failed, :cancelled, :succeeded]

  # One "Show older" click's worth of archive rows. The window keeps the
  # tab's load bounded as the terminal table grows; search and filter
  # narrow in SQL across the whole archive, so the window never hides a
  # match — only defers it behind Show older.
  @page_size 50

  # The first window is also time-boxed, adaptively: the past week if it
  # has enough to show, else the past month, else the past quarter, else
  # the whole fetched page. The week boundary mirrors `section_label/2`'s
  # "This week"; the wider scopes exist so a quiet stretch never renders
  # as a near-empty view with everything real hidden behind a button.
  @window_scopes_days [7, 30, 90]
  @min_window_entries 5

  @doc "Rows per archive window — the initial load and each Show older step."
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  @doc """
  Time-boxes an ordered (newest-first) row list to the smallest scope
  that holds at least #{@min_window_entries} rows — past week, past
  month, past quarter, then the whole list — returning
  `{kept, trimmed_any?}`. Rows with no timestamp only appear in the
  whole-list fallback (they section as "Earlier"). `trimmed_any?` feeds
  `history_has_older?` so Show older renders whenever the time box hid
  something, even with the count window not yet full.
  """
  @spec adaptive_window([PursuitRow.t()], Date.t()) :: {[PursuitRow.t()], boolean()}
  def adaptive_window(rows, today) do
    @window_scopes_days
    |> Enum.find_value(fn days ->
      kept = Enum.filter(rows, &within_days?(&1.updated_at, today, days))
      if length(kept) >= @min_window_entries, do: {kept, length(kept) < length(rows)}
    end)
    |> Kernel.||({rows, false})
  end

  defp within_days?(nil, _today, _days), do: false

  defp within_days?(%DateTime{} = at, today, days), do: Date.diff(today, DateTime.to_date(at)) < days

  @typedoc """
  One grouped archive entry, in the `Logic.group_pursuit_rows/2` shape:
  a lone pursuit or an episode cluster.
  """
  @type entry :: {:single, PursuitRow.t()} | {:group, %{vms: [PursuitRow.t()]}}

  @doc """
  Splits an ordered (newest-first) entry list into date sections —
  `[{label, entries}]` — so a long archive reads by time landmark
  instead of per-row relative-time fine print. Labels: `"Today"`,
  `"Yesterday"`, `"This week"` (within the past 7 days), then
  `"July 2026"`-style month names; entries without a timestamp fall
  into `"Earlier"`. A group is placed by its newest member — the same
  time its disclosure row displays.

  Consecutive entries sharing a label share a section; the input's
  order is preserved, so a query-ordered list yields chronologically
  descending sections.
  """
  @spec section_entries([entry()], Date.t()) :: [{String.t(), [entry()]}]
  def section_entries(entries, today) do
    entries
    |> Enum.chunk_by(&section_label(entry_time(&1), today))
    |> Enum.map(fn [first | _rest] = chunk ->
      {section_label(entry_time(first), today), chunk}
    end)
  end

  @doc """
  The newest `updated_at` among a group's members — `nil` when none
  carry one. Shared by the section bucketing here and the group row's
  displayed time in `Ledger`, so a cluster is always placed by the same
  instant it shows.
  """
  @spec latest_time([PursuitRow.t()]) :: DateTime.t() | nil
  def latest_time(view_models) do
    view_models
    |> Enum.map(& &1.updated_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp entry_time({:single, %PursuitRow{updated_at: updated_at}}), do: updated_at
  defp entry_time({:group, %{vms: view_models}}), do: latest_time(view_models)

  defp section_label(nil, _today), do: "Earlier"

  defp section_label(%DateTime{} = at, today) do
    days_ago = Date.diff(today, DateTime.to_date(at))

    cond do
      days_ago <= 0 -> "Today"
      days_ago == 1 -> "Yesterday"
      days_ago < 7 -> "This week"
      true -> Calendar.strftime(at, "%B %Y")
    end
  end

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
  # Unrecognized/absent means the whole archive — the History tab shows
  # everything until the user narrows it.
  def parse_filter(_), do: :all

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
