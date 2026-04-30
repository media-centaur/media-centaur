defmodule MediaCentarrWeb.AcquisitionLive.Logic do
  @moduledoc """
  Pure helpers for `MediaCentarrWeb.AcquisitionLive`.

  The LiveView is thin wiring — mount, event dispatch, render. View-only
  helpers (group loading predicates, error formatting, result lookup, grab
  message construction, queue-state labels) live here so they can be tested
  without rendering or mounting a socket.

  Search session mutators (build/toggle/record/select) moved to
  `MediaCentarr.Acquisition.SearchSession` — the LiveView calls those
  through the `MediaCentarr.Acquisition` facade.

  Per ADR-030 (LiveView logic extraction).
  """

  alias MediaCentarr.Acquisition.{QueueItem, SearchResult}

  @type status :: :loading | :ready | {:failed, term()} | :abandoned
  @type group :: %{
          term: String.t(),
          expanded?: boolean(),
          results: [SearchResult.t()],
          status: status()
        }

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

  @doc "True when no group is still in `:loading`."
  @spec all_loaded?([group()]) :: boolean()
  def all_loaded?(groups) do
    not Enum.any?(groups, fn group -> Map.get(group, :status) == :loading end)
  end

  @doc "True when any group is still in `:loading`."
  @spec any_loading?([group()]) :: boolean()
  def any_loading?(groups), do: not all_loaded?(groups)

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
