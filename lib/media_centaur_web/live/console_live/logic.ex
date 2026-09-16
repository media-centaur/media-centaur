defmodule MediaCentaurWeb.ConsoleLive.Logic do
  @moduledoc """
  Pure helper functions for the console LiveViews — filter mutations, entry
  visibility, payload formatting, and DOM id generation.

  Shared by `MediaCentaurWeb.ConsoleLive` (sticky drawer) and
  `MediaCentaurWeb.ConsolePageLive` (full-page `/console` route) so both
  views agree on every filter/entry decision without copy-pasted logic.

  No `Phoenix.LiveView`, no `Phoenix.Component`, no database access — follows
  the LiveView logic extraction rule in ADR-030 and enables `async: true`
  unit tests without mocking a socket.
  """

  alias MediaCentaur.Console.{Entry, Filter, View}

  @doc """
  Decides whether a newly broadcast entry should be streamed given the
  current `filter` and `paused` state. Pause always wins; otherwise the
  filter's `matches?/2` governs visibility.
  """
  @spec should_insert_entry?(Filter.t(), boolean(), Entry.t()) :: boolean()
  def should_insert_entry?(%Filter{}, true, _entry), do: false

  def should_insert_entry?(%Filter{} = filter, false, %Entry{} = entry) do
    Filter.matches?(entry, filter)
  end

  @doc """
  Returns the subset of `entries` matching the filter's search term, preserving
  order. Component and level are applied by `Console.read/2` as a read selector,
  so search is the one dimension left at the call site.
  """
  @spec visible_entries([Entry.t()], Filter.t()) :: [Entry.t()]
  def visible_entries(entries, %Filter{} = filter) when is_list(entries) do
    Enum.filter(entries, &Filter.search_passes?(&1, filter))
  end

  @doc """
  Formats the visible entries as a multi-line plain-text payload suitable for
  download or clipboard copy. Shares one notion of "visible" with
  `visible_entries/2` — the caller reads through `Console.read/2`, which has
  already applied component and level — then delegates to `View.format_lines/1`.
  """
  @spec format_visible_payload([Entry.t()], Filter.t()) :: String.t()
  def format_visible_payload(entries, %Filter{} = filter) do
    entries
    |> visible_entries(filter)
    |> View.format_lines()
  end

  @doc """
  Builds the timestamped filename for a downloaded log buffer. Accepts an
  explicit `DateTime` so tests can assert deterministic output; production
  callers pass `DateTime.utc_now/0`.
  """
  @spec download_filename(DateTime.t()) :: String.t()
  def download_filename(%DateTime{} = now \\ DateTime.utc_now()) do
    "media-centaur-#{Calendar.strftime(now, "%Y-%m-%dT%H-%M-%S")}.log"
  end

  @doc """
  Toggles the visibility of a component on the filter. Unknown strings
  fall through `safe_to_existing_atom/1` → `:system` so a stray phx-value
  can never crash the atom table.
  """
  @spec toggle_component(Filter.t(), String.t()) :: Filter.t()
  def toggle_component(%Filter{} = filter, component_string) when is_binary(component_string) do
    Filter.toggle_component(filter, safe_to_existing_atom(component_string))
  end

  @doc """
  Sets the given component to `:show` and all other known components to `:hide`.
  """
  @spec solo_component(Filter.t(), String.t()) :: Filter.t()
  def solo_component(%Filter{} = filter, component_string) when is_binary(component_string) do
    Filter.solo_component(filter, safe_to_existing_atom(component_string))
  end

  @doc """
  Sets the given component to `:hide` and all other known components to `:show`.
  """
  @spec mute_component(Filter.t(), String.t()) :: Filter.t()
  def mute_component(%Filter{} = filter, component_string) when is_binary(component_string) do
    Filter.mute_component(filter, safe_to_existing_atom(component_string))
  end

  @doc """
  Sets the filter's level to the atom matching `level_string`. Unknown
  strings become `:system` via `safe_to_existing_atom/1` — this preserves
  the pre-refactor behavior where a stray form value is absorbed rather
  than crashing.
  """
  @spec set_level(Filter.t(), String.t()) :: Filter.t()
  def set_level(%Filter{} = filter, level_string) when is_binary(level_string) do
    %{filter | level: safe_to_existing_atom(level_string)}
  end

  @doc """
  Sets the filter's search string verbatim. The filter applies case-insensitive
  substring matching on read, so the caller need not normalize here.
  """
  @spec set_search(Filter.t(), String.t()) :: Filter.t()
  def set_search(%Filter{} = filter, query) when is_binary(query) do
    %{filter | search: query}
  end

  @doc """
  Parses the `resize_buffer` form value into a positive integer. Returns
  `{:ok, n}` on success and `:invalid` for anything `Integer.parse/1` rejects.
  Preserves pre-refactor behavior where "2000abc" is accepted as `2000` — the
  downstream `Buffer.resize/1` validates against the allowed range.
  """
  @spec parse_buffer_size(String.t()) :: {:ok, pos_integer()} | :invalid
  def parse_buffer_size(size_string) when is_binary(size_string) do
    case Integer.parse(size_string) do
      {size, _rest} -> {:ok, size}
      :error -> :invalid
    end
  end

  @doc """
  Stable DOM id for a log entry — used by `stream_configure/3` in both LVs
  so morphdom keys remain consistent across patches.
  """
  @spec entry_dom_id(%{id: integer()}) :: String.t()
  def entry_dom_id(%{id: id}), do: "console-log-#{id}"

  @doc """
  Safely converts a string from a phx-value-* binding or form field to an
  atom that already exists in the atom table. Returns `:system` on any
  failure so stray input falls into the default "system" bucket rather than
  raising.
  """
  @spec safe_to_existing_atom(String.t()) :: atom()
  def safe_to_existing_atom(string) when is_binary(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> :system
  end
end
