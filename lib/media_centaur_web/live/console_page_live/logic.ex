defmodule MediaCentaurWeb.ConsolePageLive.Logic do
  @moduledoc """
  Pure helper functions for `MediaCentaurWeb.ConsolePageLive` — the
  subsystem scope, filter mutations, the text search over copy/download, payload formatting, and
  DOM id generation.

  No `Phoenix.LiveView`, no `Phoenix.Component`, no database access — follows
  the LiveView logic extraction rule in ADR-030 and enables `async: true`
  unit tests without mocking a socket.
  """

  alias MediaCentaur.Console.{Entry, Filter, View}
  alias MediaCentaurWeb.StatusLive.HealthBoard

  @doc """
  The subsystem a `/console?subsystem=<name>` visit is scoped to, or nil.

  A scope names a Status board subsystem that has log components — the
  link each drill-in's log preview carries. Anything else (no parameter, an
  unknown name, a subsystem with no logs of its own) is the unscoped console.
  Names are matched against the board, never converted, so a stray parameter
  cannot mint an atom.
  """
  @spec scope(map()) :: atom() | nil
  def scope(%{"subsystem" => name}) when is_binary(name) do
    Enum.find(HealthBoard.board_subsystems(), fn subsystem ->
      Atom.to_string(subsystem) == name and HealthBoard.components_for(subsystem) != []
    end)
  end

  def scope(_params), do: nil

  @doc """
  The entries whose message contains `query`, case-insensitively, in order.
  An empty query matches everything. The query is the browser's: the
  ConsolePage hook hides non-matching rows and sends the same query with
  copy and download, trimmed and lowercased the same way here.
  """
  @spec matching([Entry.t()], String.t()) :: [Entry.t()]
  def matching(entries, query) when is_list(entries) and is_binary(query) do
    query
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> entries
      needle -> Enum.filter(entries, &String.contains?(String.downcase(&1.message), needle))
    end
  end

  @doc """
  Formats the entries matching `query` as a multi-line plain-text payload
  for download or clipboard copy. The caller reads through `Console.read/2`,
  which has already applied component and level.
  """
  @spec format_visible_payload([Entry.t()], String.t()) :: String.t()
  def format_visible_payload(entries, query) do
    entries
    |> matching(query)
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
