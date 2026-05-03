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

  alias MediaCentarr.Acquisition.{Health, QueueItem, SearchResult}

  # How long after a user-initiated cancel we keep suppressing the
  # affected row from incoming snapshots. qBittorrent's DELETE typically
  # propagates within one polling cycle; the window is intentionally
  # generous so a slow client doesn't ghost the row, while short enough
  # that a *failed* cancel surfaces visibly to the user.
  @cancel_grace_seconds 15

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
  Suppresses snapshot rows the user just cancelled, for a short grace
  window (`#{@cancel_grace_seconds}s`).

  Returns `{visible_items, active_pending_cancels}` — the second element
  is the pending-cancel map with expired entries dropped, ready to be
  written back to the socket. After the window elapses, a row that's
  still in the snapshot reappears, surfacing a cancel that didn't take.
  """
  @spec apply_pending_cancels(
          [QueueItem.t()],
          %{String.t() => integer()},
          integer()
        ) :: {[QueueItem.t()], %{String.t() => integer()}}
  def apply_pending_cancels(items, pending_cancels, now_seconds) do
    active =
      pending_cancels
      |> Enum.filter(fn {_id, cancelled_at} ->
        now_seconds - cancelled_at < @cancel_grace_seconds
      end)
      |> Map.new()

    visible = Enum.reject(items, &Map.has_key?(active, &1.id))
    {visible, active}
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

  # Activity ranking — lower number sorts to the top of the queue list. Errors
  # surface first (rare, signal-rich), then in-flight downloads, then stalls
  # that need attention, then user-paused, then the passive queue, then
  # everything else. `nil` is treated as `:other` for forward-compat.
  @state_rank %{
    error: 0,
    downloading: 1,
    stalled: 2,
    paused: 3,
    queued: 4,
    completed: 5,
    other: 6
  }

  # Number of items always rendered inline within a collapsible group before
  # the "+ N more" disclosure. See `partition_collapsible_group/3`.
  @collapsible_head_size 2

  # Within `:downloading`, surface items that need attention before
  # items that are merely slow before items that are healthy. Tier 0
  # captures degraded health (`:soft_stall`, `:frozen`, `:meta_stuck`),
  # tier 1 is `:slow`, tier 2 is everything else.
  @health_tier_degraded 0
  @health_tier_slow 1
  @health_tier_normal 2

  @doc """
  Sorts a queue list by activity priority, with downloading items
  sub-sorted by health tier (degraded → slow → normal) and then by
  ascending ETA within each tier so the closest-to-done sits at the
  top of its tier.

  Order: `:error` → `:downloading` (degraded → slow → normal, each by
  ETA) → `:stalled` → `:paused` → `:queued` → `:other`. Items with
  `nil` state are treated as `:other`. Items with `nil` `timeleft`
  within `:downloading` sort after items with a known ETA.
  """
  @spec sort_downloads([QueueItem.t()]) :: [QueueItem.t()]
  def sort_downloads(items) when is_list(items) do
    items
    |> Enum.with_index()
    |> Enum.sort_by(fn {item, idx} ->
      {state_rank(item.state), health_tier(item), eta_seconds(item), idx}
    end)
    |> Enum.map(fn {item, _idx} -> item end)
  end

  defp state_rank(state), do: Map.get(@state_rank, state, @state_rank.other)

  defp health_tier(%QueueItem{state: :downloading, health: health}) do
    cond do
      Health.degraded?(health) -> @health_tier_degraded
      Health.slow?(health) -> @health_tier_slow
      true -> @health_tier_normal
    end
  end

  defp health_tier(_), do: @health_tier_normal

  # Used as a secondary sort key — only meaningful for :downloading items
  # (where ETA orders closest-to-done first). For other states, every item
  # gets the same key so the original-order tiebreaker (the index) wins.
  # `nil` ETA sorts after any concrete ETA via {1, 0} > {0, secs}.
  defp eta_seconds(%QueueItem{state: :downloading, timeleft: nil}), do: {1, 0}
  defp eta_seconds(%QueueItem{state: :downloading, timeleft: timeleft}), do: {0, parse_eta(timeleft)}
  defp eta_seconds(_), do: {0, 0}

  # Re-parse the human ETA back into seconds so we can sort. The original
  # integer ETA is dropped during QueueItem construction; if that ever
  # changes, this helper goes away.
  defp parse_eta(nil), do: 0

  defp parse_eta(text) when is_binary(text) do
    case Regex.run(~r/^(\d+)([smhd])(?:\s+(\d+)m)?$/, text) do
      [_, num, "s"] -> String.to_integer(num)
      [_, num, "m"] -> String.to_integer(num) * 60
      [_, num, "h"] -> String.to_integer(num) * 3600
      [_, hours, "h", minutes] -> String.to_integer(hours) * 3600 + String.to_integer(minutes) * 60
      [_, num, "d"] -> String.to_integer(num) * 86_400
      _ -> 0
    end
  end

  @typedoc "Summary returned by `partition_collapsible_group/3` for groups large enough to collapse."
  @type group_summary :: %{
          kind: :collapsed | :expanded,
          state: QueueItem.state(),
          # only present when collapsed
          hidden: [QueueItem.t()],
          hidden_count: non_neg_integer(),
          total: non_neg_integer()
        }

  @doc """
  Splits a per-state group of queue items into a head (always rendered)
  and an optional summary describing the collapsed tail.

  When `length(items) <= @collapsible_head_size`, returns `{items, nil}` —
  no collapse is needed, render every item inline.

  When the group is larger:

  - With `expanded? = false` (default), returns `{head, %{kind: :collapsed,
    hidden: tail, hidden_count: N, ...}}` — the template renders the head
    plus a "+ N more" disclosure row.
  - With `expanded? = true`, returns `{full_list, %{kind: :expanded, ...}}`
    so the template can render every item plus a "Show fewer" affordance.

  Used for `:queued` and `:error` groups, where a long list adds noise
  without per-item value.
  """
  @spec partition_collapsible_group([QueueItem.t()], QueueItem.state(), boolean()) ::
          {[QueueItem.t()], group_summary() | nil}
  def partition_collapsible_group([], _state, _expanded?), do: {[], nil}

  def partition_collapsible_group(items, state, expanded?) when is_list(items) do
    total = length(items)

    if total <= @collapsible_head_size do
      {items, nil}
    else
      {head, tail} = Enum.split(items, @collapsible_head_size)

      if expanded? do
        {items, %{kind: :expanded, state: state, hidden: [], hidden_count: 0, total: total}}
      else
        {head,
         %{
           kind: :collapsed,
           state: state,
           hidden: tail,
           hidden_count: length(tail),
           total: total
         }}
      end
    end
  end

  @doc "Module attribute accessor — head size used by `partition_collapsible_group/3`."
  @spec collapsible_head_size() :: pos_integer()
  def collapsible_head_size, do: @collapsible_head_size

  # States whose groups are collapsible when they exceed the head size.
  # Other groups render every item inline regardless of count.
  @collapsible_states [:error, :queued]

  @typedoc "One render instruction emitted by `prepare_queue_for_render/2`."
  @type render_op :: {:item, QueueItem.t()} | {:summary, group_summary()}

  @doc """
  Sorts and groups a queue list into a flat sequence of render
  instructions. The template walks the result and renders each op:
  `{:item, item}` is a regular row; `{:summary, group_summary}` is the
  collapse/expand disclosure row.

  `expanded_states` is a `MapSet` of states the user has clicked open.
  States not in the set render in collapsed form.
  """
  @spec prepare_queue_for_render([QueueItem.t()], MapSet.t(QueueItem.state())) :: [render_op()]
  def prepare_queue_for_render(items, expanded_states) when is_list(items) do
    items
    |> sort_downloads()
    |> Enum.chunk_by(&group_state/1)
    |> Enum.flat_map(&prepare_chunk(&1, expanded_states))
  end

  defp group_state(item), do: item.state || :other

  defp prepare_chunk([] = _chunk, _expanded), do: []

  defp prepare_chunk([%QueueItem{} = first | _] = chunk, expanded_states) do
    state = group_state(first)

    if state in @collapsible_states do
      expanded? = MapSet.member?(expanded_states, state)
      {visible, summary} = partition_collapsible_group(chunk, state, expanded?)
      item_ops = Enum.map(visible, &{:item, &1})

      if summary, do: item_ops ++ [{:summary, summary}], else: item_ops
    else
      Enum.map(chunk, &{:item, &1})
    end
  end

  @doc "User-facing label for a `QueueItem` state."
  @spec state_label(QueueItem.state() | nil) :: String.t()
  def state_label(:downloading), do: "Downloading"
  def state_label(:queued), do: "Queued"
  def state_label(:stalled), do: "Stalled"
  def state_label(:paused), do: "Paused"
  def state_label(:completed), do: "Completed"
  def state_label(:error), do: "Error"
  def state_label(:other), do: "Other"
  def state_label(_), do: "Unknown"

  @doc """
  Maps a `QueueItem` state to a `<.badge>` variant (UIDR-002 /
  `MediaCentarrWeb.CoreComponents.badge/1`).
  """
  @spec state_badge_variant(QueueItem.state() | nil) :: String.t()
  def state_badge_variant(:downloading), do: "info"
  def state_badge_variant(:completed), do: "success"
  def state_badge_variant(:error), do: "error"
  def state_badge_variant(:paused), do: "warning"
  def state_badge_variant(:stalled), do: "warning"
  # :queued reads as passive "waiting in qBittorrent's queue" — neutral, not warning
  def state_badge_variant(:queued), do: "ghost"
  def state_badge_variant(_), do: "metric"

  @doc """
  Whether the Downloads page should render a health-secondary line for
  this item. Suppresses the line for items where `Acquisition.Health`
  has nothing actionable to add (`:healthy`, `:warming_up`, or `nil`).
  """
  @spec render_health_line?(QueueItem.t()) :: boolean()
  def render_health_line?(%QueueItem{health: health}) do
    health not in [nil, :healthy, :warming_up]
  end

  @doc """
  Tailwind text-color class for the Downloads page health-secondary
  line. Translates the semantic variant from
  `Health.badge_variant/1` to a project CSS
  class.
  """
  @spec health_text_class(Health.status() | nil) :: String.t()
  def health_text_class(nil), do: "text-base-content/40"

  def health_text_class(status) do
    case Health.badge_variant(status) do
      "warning" -> "text-warning"
      "ghost" -> "text-base-content/60"
      _ -> "text-base-content/40"
    end
  end
end
