defmodule MediaCentarr.Acquisition.Pursuits do
  @moduledoc """
  Read-side queries over the pursuit aggregate.

  Write-side operations live in `Acquisition.Pursuits.Commands.*`. This
  module is intentionally read-only — it never mutates state, never
  broadcasts, never enqueues jobs. Callers that want to change the
  world go through a command. ViewModel assemblers also live here
  because shaping rows for the UI is a read concern.
  """

  import Ecto.Query

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit, State}
  alias MediaCentarr.Acquisition.{QueryBuilder, QueueMatcher, Target}

  alias MediaCentarr.Acquisition.ViewModels.{
    PursuitHeader,
    PursuitRow,
    PursuitStatus,
    Recipe,
    Timeline,
    TimelineEntry
  }

  alias MediaCentarr.Downloads.QueueItem
  alias MediaCentarr.Downloads.QueueMonitor
  alias MediaCentarr.Repo

  @spec get(Ecto.UUID.t()) :: {:ok, Pursuit.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Pursuit, id) do
      nil -> {:error, :not_found}
      %Pursuit{} = pursuit -> {:ok, pursuit}
    end
  end

  @doc "Lists every in-flight pursuit (`active` or `needs_decision`), newest-updated first."
  @spec list_active() :: [Pursuit.t()]
  def list_active do
    Pursuit
    |> where([p], p.state in ^State.in_flight())
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Like `list_active/0` but also returns each pursuit's `current_target`
  in a single batched lookup, paired as `[{pursuit, target_or_nil}]`.
  Used by `Pursuits.Watcher` so its per-tick pass costs 2 queries total
  (pursuits + targets) instead of `1 + N` (pursuits + N current_target
  fetches).
  """
  @spec list_active_with_current_targets() :: [{Pursuit.t(), Target.t() | nil}]
  def list_active_with_current_targets do
    pursuits = list_active()

    targets =
      pursuits
      |> Enum.map(& &1.current_target_id)
      |> Enum.reject(&is_nil/1)
      |> fetch_targets_by_id()

    Enum.map(pursuits, fn p -> {p, Map.get(targets, p.current_target_id)} end)
  end

  @doc """
  Returns a map of `pursuit_id => latest_release_title` for every pursuit
  in `pursuit_ids` that has a target with a non-nil `release_title`.
  Pursuits with no acquired releases are absent from the map.

  Used by `Pursuits.Watcher` so the per-tick pass does one batched query
  for release-title lookups rather than one query per pursuit.
  """
  @spec latest_release_titles_for([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => String.t()}
  def latest_release_titles_for([]), do: %{}

  def latest_release_titles_for(pursuit_ids) when is_list(pursuit_ids) do
    Target
    |> where([t], t.pursuit_id in ^pursuit_ids and not is_nil(t.release_title))
    |> order_by([t], desc: t.inserted_at)
    |> select([t], {t.pursuit_id, t.release_title})
    |> Repo.all()
    # Newest-first ordering + `put_new` keeps only the latest release
    # title per pursuit_id without an O(n log n) group_by.
    |> Enum.reduce(%{}, fn {pid, title}, acc -> Map.put_new(acc, pid, title) end)
  end

  @doc "Lists active pursuits as `PursuitRow` view-models for the Downloads index."
  @spec list_active_rows() :: [PursuitRow.t()]
  def list_active_rows, do: list_rows(:active)

  @doc """
  Lists pursuits as `PursuitRow` view-models, filtered by lifecycle bucket.

  - `:active`       — `state in [:active, :needs_decision]` (in-flight)
  - `:failed`       — `state == :exhausted`
  - `:cancelled`    — `state == :cancelled`
  - `:succeeded`    — `state == :satisfied`
  - `:all_terminal` — every non-in-flight state (satisfied + exhausted + cancelled)

  Ordered newest-updated first. Each row pairs the pursuit with its
  `current_target` via `fetch_targets_by_id/1`, so `release_title` and
  `target_status` come from the most recent attempt.
  """
  @spec list_rows(:active | :failed | :cancelled | :succeeded | :all_terminal) :: [PursuitRow.t()]
  def list_rows(filter) do
    states = states_for_filter(filter)

    pursuits =
      Pursuit
      |> where([p], p.state in ^states)
      |> order_by([p], desc: p.updated_at)
      |> Repo.all()

    current_targets =
      pursuits
      |> Enum.map(& &1.current_target_id)
      |> Enum.reject(&is_nil/1)
      |> fetch_targets_by_id()

    Enum.map(pursuits, fn pursuit ->
      target = Map.get(current_targets, pursuit.current_target_id)
      build_row(pursuit, target)
    end)
  end

  defp states_for_filter(:active), do: State.in_flight()
  defp states_for_filter(:failed), do: ["exhausted"]
  defp states_for_filter(:cancelled), do: ["cancelled"]
  defp states_for_filter(:succeeded), do: ["satisfied"]
  defp states_for_filter(:all_terminal), do: State.terminal()

  @doc "Returns a `PursuitHeader` view-model for the detail page."
  @spec header_for(Ecto.UUID.t()) :: {:ok, PursuitHeader.t()} | {:error, :not_found}
  def header_for(id) do
    case get(id) do
      {:ok, pursuit} -> {:ok, header_from(pursuit)}
      {:error, :not_found} = error -> error
    end
  end

  @doc """
  Like `header_for/1` but skips the DB read — for callers that already
  hold the `%Pursuit{}`. Used by `load_pursuit_detail/1` to assemble all
  three view-models from one fetch instead of three.
  """
  @spec header_from(Pursuit.t()) :: PursuitHeader.t()
  def header_from(%Pursuit{} = pursuit), do: build_header(pursuit)

  @doc """
  Returns the full `PursuitStatus` view-model for the detail page —
  identity + current activity + available manual triggers + staleness.
  """
  @spec status_for(Ecto.UUID.t()) :: {:ok, PursuitStatus.t()} | {:error, :not_found}
  def status_for(id) do
    case get(id) do
      {:error, :not_found} = error -> error
      {:ok, pursuit} -> {:ok, status_from(pursuit)}
    end
  end

  @doc """
  Refreshes only the queue-derived fields of an existing `PursuitStatus`
  view-model against a fresh queue snapshot, without re-reading the
  pursuit, target, or last-event row from the DB.

  Used on the LiveView's queue-tick path (1.5 s when subscribed) so the
  modal's download progress updates without firing three Repo queries on
  every snapshot. The static block (state, recipe, staleness, last
  activity) is unchanged — pursuit-lifecycle events still trigger a
  full reload via `status_for/1`.
  """
  @spec refresh_status_download(PursuitStatus.t(), [MediaCentarr.Downloads.QueueItem.t()]) ::
          PursuitStatus.t()
  def refresh_status_download(%PursuitStatus{pursuit: nil} = status, _items), do: status

  def refresh_status_download(%PursuitStatus{} = status, queue_items) when is_list(queue_items) do
    queue_item = find_queue_match(status.target, queue_items)
    download = QueueMatcher.to_download(queue_item)

    if status.download == download do
      status
    else
      {current_action, next_step, actions} =
        PursuitStatus.derive(status.pursuit, status.target, queue_item)

      %{
        status
        | current_action: current_action,
          next_step: next_step,
          available_actions: actions,
          download: download
      }
    end
  end

  @doc """
  Like `status_for/1` but skips the DB read for the pursuit — for callers
  that already hold the `%Pursuit{}`. Uses the cached `QueueMonitor`
  snapshot for the live download field; pass a queue items list as the
  second argument to reuse a snapshot the caller already has (saves an
  ETS read on the LiveView's queue-tick path).

  The returned struct stashes the loaded pursuit + target so
  `refresh_status_download/2` can re-derive the dynamic fields without
  a second DB round-trip when a queue snapshot ticks in.
  """
  @spec status_from(Pursuit.t(), [MediaCentarr.Downloads.QueueItem.t()] | :persistent_term) ::
          PursuitStatus.t()
  def status_from(%Pursuit{} = pursuit, queue_items \\ :persistent_term) do
    target = current_target(pursuit)
    queue_item = find_queue_match(target, queue_items)
    {current_action, next_step, actions} = PursuitStatus.derive(pursuit, target, queue_item)
    last_activity_at = latest_event_at(pursuit.id)

    %PursuitStatus{
      pursuit_id: pursuit.id,
      title: pursuit.title,
      state: String.to_existing_atom(pursuit.state),
      origin: String.to_existing_atom(pursuit.origin),
      recipe: build_recipe(pursuit),
      criteria_summary: summarize_criteria(pursuit.criteria),
      current_action: current_action,
      next_step: next_step,
      download: QueueMatcher.to_download(queue_item),
      staleness: staleness_for(last_activity_at),
      last_activity_at: last_activity_at,
      available_actions: actions,
      pursuit: pursuit,
      target: target
    }
  end

  @doc "Returns a `Timeline` view-model containing every event for a pursuit."
  @spec timeline_for(Ecto.UUID.t()) :: Timeline.t()
  def timeline_for(pursuit_id) do
    entries =
      pursuit_id
      |> events_for()
      |> Enum.map(&TimelineEntry.from_event/1)

    %Timeline{pursuit_id: pursuit_id, entries: entries}
  end

  @doc """
  Returns events for a pursuit, newest first. Empty list for unknown
  pursuit_id — events with nilified `pursuit_id` are not surfaced here.
  """
  @spec events_for(Ecto.UUID.t()) :: [Event.t()]
  def events_for(pursuit_id) do
    Event
    |> where([e], e.pursuit_id == ^pursuit_id)
    |> order_by([e], desc: e.occurred_at)
    |> Repo.all()
  end

  @doc """
  Returns active pursuits whose TMDB recipe matches the given map.

  Accepts `%{tmdb_id, tmdb_type}` and optional `:season_number` /
  `:episode_number`. TV pursuits without a season pin (e.g.,
  season-pack pursuits) match any episode for that series; movie
  pursuits match by `tmdb_id` alone.

  Only matches pursuits with `recipe_type = "tmdb"` — query-recipe
  pursuits have no TMDB metadata to match against. Used by
  `Pursuits.InboundListener` to dispatch identity verification when a
  file lands for a tracked target.
  """
  @spec find_active_for_target(map()) :: [Pursuit.t()]
  def find_active_for_target(%{tmdb_id: tmdb_id, tmdb_type: "movie"}) when is_binary(tmdb_id) do
    Pursuit
    |> where([p], p.state == "active" and p.recipe_type == "tmdb")
    |> where([p], p.tmdb_id == ^tmdb_id and p.tmdb_type == "movie")
    |> Repo.all()
  end

  def find_active_for_target(%{tmdb_id: tmdb_id, tmdb_type: "tv"} = target) when is_binary(tmdb_id) do
    season = Map.get(target, :season_number)
    episode = Map.get(target, :episode_number)

    Pursuit
    |> where([p], p.state == "active" and p.recipe_type == "tmdb")
    |> where([p], p.tmdb_id == ^tmdb_id and p.tmdb_type == "tv")
    |> match_season(season)
    |> match_episode(episode)
    |> Repo.all()
  end

  def find_active_for_target(_), do: []

  defp match_season(query, nil), do: query

  defp match_season(query, season) do
    where(query, [p], is_nil(p.season_number) or p.season_number == ^season)
  end

  defp match_episode(query, nil), do: query

  defp match_episode(query, episode) do
    where(query, [p], is_nil(p.episode_number) or p.episode_number == ^episode)
  end

  @doc """
  Returns the pursuit's current target (the row pointed at by
  `pursuit.current_target_id`), if any.
  """
  @spec current_target(Pursuit.t()) :: Target.t() | nil
  def current_target(%Pursuit{current_target_id: nil}), do: nil
  def current_target(%Pursuit{current_target_id: id}), do: Repo.get(Target, id)

  @doc """
  Idempotency lookup — exact match on a pursuit's TMDB recipe tuple,
  regardless of pursuit state. Returns one pursuit or nil.

  Unlike `find_active_for_target/1`, this is "exact" — a `season_number: nil`
  match-arg only matches pursuits with `season_number IS NULL`. Used by
  `Acquisition` to find-or-create pursuits on the auto-acquisition path
  where re-using an existing (possibly terminal) row is the desired
  idempotency.

  Requires `tmdb_id` and `tmdb_type` in the target map; `season_number`
  and `episode_number` are optional (nil → matches NULL exactly).
  """
  @spec find_by_tmdb_recipe(map()) :: Pursuit.t() | nil
  def find_by_tmdb_recipe(%{tmdb_id: tmdb_id, tmdb_type: tmdb_type} = target)
      when is_binary(tmdb_id) and is_binary(tmdb_type) do
    season = Map.get(target, :season_number)
    episode = Map.get(target, :episode_number)

    Pursuit
    |> where([p], p.recipe_type == "tmdb" and p.tmdb_id == ^tmdb_id and p.tmdb_type == ^tmdb_type)
    |> exact_match(:season_number, season)
    |> exact_match(:episode_number, episode)
    |> Repo.one()
  end

  defp exact_match(query, field, nil), do: where(query, [p], is_nil(field(p, ^field)))
  defp exact_match(query, field, value), do: where(query, [p], field(p, ^field) == ^value)

  @doc """
  Returns the most recently inserted target linked to a pursuit
  (regardless of which is the pursuit's `current_target_id` — useful
  for history queries that want "the latest attempt").
  """
  @spec latest_target(Ecto.UUID.t()) :: {:ok, Target.t()} | {:error, :not_found}
  def latest_target(pursuit_id) do
    target =
      Target
      |> where([t], t.pursuit_id == ^pursuit_id)
      |> order_by([t], desc: t.inserted_at)
      |> limit(1)
      |> Repo.one()

    case target do
      nil -> {:error, :not_found}
      %Target{} = target -> {:ok, target}
    end
  end

  @doc "Returns all targets for a pursuit, newest-inserted first."
  @spec targets_for(Ecto.UUID.t()) :: [Target.t()]
  def targets_for(pursuit_id) do
    Target
    |> where([t], t.pursuit_id == ^pursuit_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  # --- ViewModel assembly ----------------------------------------------------

  defp fetch_targets_by_id([]), do: %{}

  defp fetch_targets_by_id(ids) do
    Target
    |> where([t], t.id in ^ids)
    |> Repo.all()
    |> Map.new(fn target -> {target.id, target} end)
  end

  defp build_row(%Pursuit{} = pursuit, target) do
    {release_title, target_status} =
      case target do
        %Target{release_title: rt, status: status} -> {rt, status_to_atom(status)}
        nil -> {nil, nil}
      end

    # Status line for the index card. Queue-state-aware status takes
    # over at render time inside the row component when a download
    # footer is paired — derive here without a queue item so the row
    # is independent of QueueMonitor cadence.
    {status, _next_step, _actions} = PursuitStatus.derive(pursuit, target, nil)

    %PursuitRow{
      id: pursuit.id,
      title: pursuit.title,
      state: state_to_atom(pursuit.state),
      season_number: pursuit.season_number,
      episode_number: pursuit.episode_number,
      release_title: release_title,
      target_status: target_status,
      status: status,
      normalized_release_title: release_title && QueueMatcher.normalize_title(release_title)
    }
  end

  # Explicit string→atom mapping for the row VM so the function doesn't
  # depend on atom-loading side effects from other modules being
  # compiled into the same release. The pursuit `state` column is
  # constrained by `Pursuits.State` to these five values.
  defp state_to_atom("active"), do: :active
  defp state_to_atom("needs_decision"), do: :needs_decision
  defp state_to_atom("satisfied"), do: :satisfied
  defp state_to_atom("exhausted"), do: :exhausted
  defp state_to_atom("cancelled"), do: :cancelled

  defp status_to_atom(nil), do: nil
  defp status_to_atom("seeking"), do: :seeking
  defp status_to_atom("acquired"), do: :acquired
  defp status_to_atom("succeeded"), do: :succeeded
  defp status_to_atom("failed"), do: :failed
  defp status_to_atom("cancelled"), do: :cancelled

  defp build_header(%Pursuit{} = pursuit) do
    %PursuitHeader{
      id: pursuit.id,
      title: pursuit.title,
      state: String.to_existing_atom(pursuit.state),
      recipe: build_recipe(pursuit),
      criteria_summary: summarize_criteria(pursuit.criteria)
    }
  end

  defp summarize_criteria(nil), do: nil
  defp summarize_criteria(map) when map_size(map) == 0, do: nil

  defp summarize_criteria(map) when is_map(map) do
    map
    |> Enum.sort()
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{v}" end)
  end

  # --- status_for helpers ----------------------------------------------------

  defp build_recipe(%Pursuit{recipe_type: "tmdb"} = p) do
    %Recipe{
      recipe_type: :tmdb,
      tmdb_type: p.tmdb_type,
      tmdb_id: p.tmdb_id,
      season_number: p.season_number,
      episode_number: p.episode_number,
      year: p.year,
      search_queries: search_queries_for(p)
    }
  end

  defp build_recipe(%Pursuit{recipe_type: "prowlarr_query"} = p) do
    %Recipe{
      recipe_type: :prowlarr_query,
      manual_query: p.manual_query,
      search_queries: search_queries_for(p)
    }
  end

  # `QueryBuilder.build/1` returns `[{query, opts}]` ordered best-to-worst.
  # The UI only needs the query strings, so we strip the opts here. Kept
  # pure (no DB, no Prowlarr) — the same list the worker iterates over.
  defp search_queries_for(%Pursuit{} = pursuit) do
    pursuit
    |> QueryBuilder.build()
    |> Enum.map(fn {query, _opts} -> query end)
  end

  defp find_queue_match(nil, _items), do: nil
  defp find_queue_match(%Target{release_title: nil}, _items), do: nil

  defp find_queue_match(%Target{release_title: title}, items) do
    queue = resolve_queue_items(items)
    normalized = QueueMatcher.normalize_title(title)

    Enum.find(queue, fn %QueueItem{} = item ->
      QueueMatcher.normalize_title(item.title) == normalized
    end)
  end

  defp resolve_queue_items(:persistent_term), do: QueueMonitor.snapshot()
  defp resolve_queue_items(items) when is_list(items), do: items

  defp latest_event_at(pursuit_id) do
    Event
    |> where([e], e.pursuit_id == ^pursuit_id)
    |> order_by([e], desc: e.occurred_at)
    |> limit(1)
    |> select([e], e.occurred_at)
    |> Repo.one()
  end

  defp staleness_for(nil), do: :very_stale

  defp staleness_for(%DateTime{} = ts) do
    diff_seconds = DateTime.diff(DateTime.utc_now(:second), ts)

    cond do
      diff_seconds < 3600 -> :fresh
      diff_seconds < 86_400 -> :stale
      true -> :very_stale
    end
  end
end
