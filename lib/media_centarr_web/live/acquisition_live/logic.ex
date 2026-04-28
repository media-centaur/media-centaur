defmodule MediaCentarrWeb.AcquisitionLive.Logic do
  @moduledoc """
  Pure helpers for `MediaCentarrWeb.AcquisitionLive`.

  The LiveView is thin wiring — mount, event dispatch, render. All non-trivial
  decisions (expansion preview, group construction, default selections, grab
  summarization, result lookup, group toggling) live here so they can be tested
  without rendering, mounting a socket, or exercising the Prowlarr adapter.

  Per ADR-030 (LiveView logic extraction).
  """

  alias MediaCentarr.Acquisition.{QueryExpander, Quality, QueueItem, SearchResult}

  @type status :: :loading | :ready | {:failed, term()}
  @type group :: %{
          term: String.t(),
          expanded?: boolean(),
          results: [SearchResult.t()],
          status: status()
        }

  @doc """
  Produces a UI-friendly preview of how a query will be expanded.

  Returns `:idle` for blank input, `{:ok, count}` for a syntactically valid
  query (count = 1 when no braces are present), or `{:error, :invalid_syntax}`
  when the brace syntax is malformed.
  """
  @spec expansion_preview(String.t()) ::
          :idle | {:ok, pos_integer()} | {:error, :invalid_syntax}
  def expansion_preview(query) when is_binary(query) do
    case String.trim(query) do
      "" ->
        :idle

      trimmed ->
        case QueryExpander.expand(trimmed) do
          {:ok, queries} -> {:ok, length(queries)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Builds groups from `[{term, [SearchResult]}, ...]`. Within each group,
  results are sorted by quality (highest first), then seeders (most first).
  Group order matches input order. Each group starts collapsed and `:ready`.
  """
  @spec build_groups([{String.t(), [SearchResult.t()]}]) :: [group()]
  def build_groups(term_results) when is_list(term_results) do
    Enum.map(term_results, fn {term, results} ->
      %{term: term, expanded?: false, results: sort_results(results), status: :ready}
    end)
  end

  @doc """
  Builds initial `:loading` placeholder groups, one per query, in input order.
  Used to render the result section immediately on submit so the user sees
  per-query placeholders while individual searches are still in flight.
  """
  @spec placeholder_groups([String.t()]) :: [group()]
  def placeholder_groups(queries) when is_list(queries) do
    Enum.map(queries, fn term ->
      %{term: term, expanded?: false, results: [], status: :loading}
    end)
  end

  @doc """
  Replaces the matching group's results when a single search resolves.
  `{:ok, results}` flips the group to `:ready` (sorted); `{:error, _}`
  flips it to `:failed` with empty results. Unknown terms are ignored
  (defends against stale results arriving after the user re-searched).
  """
  @spec apply_search_result([group()], String.t(), {:ok, [SearchResult.t()]} | {:error, term()}) ::
          [group()]
  def apply_search_result(groups, term, {:ok, results}) do
    sorted = sort_results(results)

    Enum.map(groups, fn
      %{term: ^term} = group -> %{group | results: sorted, status: :ready}
      group -> group
    end)
  end

  def apply_search_result(groups, term, {:error, reason}) do
    Enum.map(groups, fn
      %{term: ^term} = group -> %{group | results: [], status: {:failed, reason}}
      group -> group
    end)
  end

  @doc """
  Flips the matching group back to `:loading` and clears its results, leaving
  every other group untouched. `expanded?` is preserved so a manual retry
  doesn't collapse a group the user had open. No-op when the term is unknown.

  Used by the per-group "Retry" link and the bulk "Retry N timeouts" button
  to re-arm a search before re-dispatching `{:run_search_one, term}`.
  """
  @spec mark_group_loading([group()], String.t()) :: [group()]
  def mark_group_loading(groups, term) do
    Enum.map(groups, fn
      %{term: ^term} = group -> %{group | results: [], status: :loading}
      group -> group
    end)
  end

  @doc """
  Returns the terms of every group whose status is a Prowlarr request timeout
  (`{:failed, %Req.TransportError{reason: :timeout}}`), in group order.

  Excludes other failure reasons deliberately — `:econnrefused`, `:nxdomain`,
  HTTP 401/403, etc. are configuration problems where retrying without a fix
  won't help. The bulk "Retry N timeouts" button is offered only when
  retrying is plausibly useful.
  """
  @spec timeout_terms([group()]) :: [String.t()]
  def timeout_terms(groups) do
    for %{term: term, status: {:failed, %Req.TransportError{reason: :timeout}}} <- groups,
        do: term
  end

  @doc """
  Adds `term => top_result_guid` to selections when the group is `:ready`,
  has results, and `term` is not already selected. Used incrementally as
  each search resolves so the Grab counter ticks up live without clobbering
  any user-made selection.
  """
  @spec add_default_selection(%{String.t() => String.t()}, group()) :: %{String.t() => String.t()}
  def add_default_selection(selections, %{term: term, status: :ready, results: [first | _]}) do
    Map.put_new(selections, term, first.guid)
  end

  def add_default_selection(selections, _group), do: selections

  @doc "True when no group is still in `:loading`."
  @spec all_loaded?([group()]) :: boolean()
  def all_loaded?(groups) do
    not Enum.any?(groups, fn group -> Map.get(group, :status) == :loading end)
  end

  defp sort_results(results) do
    Enum.sort_by(results, fn r -> {Quality.rank(r.quality), r.seeders || 0} end, :desc)
  end

  @doc """
  Returns a `%{term => guid}` map selecting the top-ranked (first) result of
  every group that has any results.
  """
  @spec default_selections([group()]) :: %{String.t() => String.t()}
  def default_selections(groups) do
    groups
    |> Enum.flat_map(fn
      %{term: term, results: [first | _]} -> [{term, first.guid}]
      _ -> []
    end)
    |> Map.new()
  end

  @doc """
  Formats a Prowlarr grab error reason into a short user-facing string.
  Pulls `errorMessage` / `message` / `error` from a JSON body when present
  alongside an HTTP status; otherwise inspects the raw reason.
  """
  @spec format_grab_reason(term()) :: String.t()
  def format_grab_reason({:http_error, status, body}) do
    case body_message(body) do
      nil -> "HTTP #{status}"
      message -> "HTTP #{status}: #{message}"
    end
  end

  def format_grab_reason(reason), do: inspect(reason)

  defp body_message(%{"errorMessage" => message}) when is_binary(message), do: message
  defp body_message(%{"message" => message}) when is_binary(message), do: message
  defp body_message(%{"error" => message}) when is_binary(message), do: message
  defp body_message(_), do: nil

  @doc """
  Builds the toast tuple from `[{SearchResult, :ok | {:error, reason}}, ...]`.

  Returns `{:ok | :partial | :error, message}`. On any failure, the message
  includes the first error's reason via `format_grab_reason/1` so the user
  sees the cause without opening the console drawer.
  """
  @spec build_grab_message([{SearchResult.t(), :ok | {:error, term()}}]) ::
          {:ok | :partial | :error, String.t()}
  def build_grab_message(pairs) do
    {ok_pairs, err_pairs} = Enum.split_with(pairs, fn {_, outcome} -> match?({:ok, _}, outcome) end)
    ok_count = length(ok_pairs)
    err_count = length(err_pairs)

    cond do
      err_count == 0 ->
        {:ok, "#{ok_count} grab(s) submitted"}

      ok_count == 0 ->
        {:error, "All #{err_count} grab(s) failed — #{first_reason(err_pairs)}"}

      true ->
        {:partial, "#{ok_count} ok, #{err_count} failed — #{first_reason(err_pairs)}"}
    end
  end

  defp first_reason(err_pairs) do
    {_result, {:error, reason}} = List.first(err_pairs)
    format_grab_reason(reason)
  end

  @doc """
  Formats a search-error reason into a short user-facing string explaining
  why the search failed and what to check.
  """
  @spec format_search_error(term()) :: String.t()
  def format_search_error(%Req.TransportError{reason: :econnrefused}),
    do: "Couldn't reach Prowlarr — check that the service is running and the URL is correct"

  def format_search_error(%Req.TransportError{reason: :nxdomain}),
    do: "Prowlarr URL not found — check the URL in Settings"

  def format_search_error(%Req.TransportError{reason: :timeout}), do: "Prowlarr timed out"

  def format_search_error({:http_error, status, _body}) when status in [401, 403],
    do: "Prowlarr rejected the API key — check Settings"

  def format_search_error({:http_error, status, _body}), do: "Prowlarr returned HTTP #{status}"

  def format_search_error(_reason), do: "Search failed"

  @doc """
  Returns the result a group's collapsed header should display: the user's
  selected result if one is set for this term and still exists, otherwise
  the top-ranked result. `nil` when the group has no results.
  """
  @spec featured_result(group(), %{String.t() => String.t()}) :: SearchResult.t() | nil
  def featured_result(%{term: term, results: results}, selections) do
    fallback = List.first(results)

    case Map.get(selections, term) do
      nil -> fallback
      guid -> Enum.find(results, fallback, &(&1.guid == guid))
    end
  end

  @doc "Finds a `SearchResult` by guid across all groups, or `nil`."
  @spec find_result([group()], String.t()) :: SearchResult.t() | nil
  def find_result(groups, guid) do
    Enum.find_value(groups, fn group ->
      Enum.find(group.results, &(&1.guid == guid))
    end)
  end

  @doc "Flips `expanded?` on the group whose `term` matches; leaves others unchanged."
  @spec toggle_group([group()], String.t()) :: [group()]
  def toggle_group(groups, term) do
    Enum.map(groups, fn
      %{term: ^term} = group -> %{group | expanded?: not group.expanded?}
      group -> group
    end)
  end

  @doc """
  Buckets `QueueItem`s into `:active` (in-flight) and `:completed` lists,
  preserving input order within each bucket. Items with `state: :completed`
  go to `:completed`; everything else (including `nil` for forward-compat
  with new drivers) goes to `:active`.
  """
  @spec group_downloads_by_state([QueueItem.t()]) :: %{
          active: [QueueItem.t()],
          completed: [QueueItem.t()]
        }
  def group_downloads_by_state(items) when is_list(items) do
    {completed, active} = Enum.split_with(items, fn item -> item.state == :completed end)
    %{active: active, completed: completed}
  end

  @doc "User-facing label for a `QueueItem` state."
  @spec state_label(QueueItem.state() | nil) :: String.t()
  def state_label(:downloading), do: "Downloading"
  def state_label(:stalled), do: "Stalled"
  def state_label(:paused), do: "Paused"
  def state_label(:completed), do: "Completed"
  def state_label(:error), do: "Error"
  def state_label(:other), do: "Other"
  def state_label(_), do: "Unknown"

  @doc "daisyUI badge color class for a `QueueItem` state."
  @spec state_badge_class(QueueItem.state() | nil) :: String.t()
  def state_badge_class(:downloading), do: "badge badge-info"
  def state_badge_class(:completed), do: "badge badge-success"
  def state_badge_class(:error), do: "badge badge-error"
  def state_badge_class(:paused), do: "badge badge-warning"
  def state_badge_class(:stalled), do: "badge badge-warning"
  def state_badge_class(_), do: "badge badge-neutral"
end
