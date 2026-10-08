defmodule MediaCentaur.WatchHistory do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.Retention],
    exports: [Event, Views, Views.PlaybackActivity, Views.Summary, Views.SummaryData]

  @moduledoc """
  Public API for the WatchHistory bounded context.

  Records a permanent, append-only `Event` for each completion (≥90%
  playback threshold). The `Recorder` GenServer drives writes; this module
  exposes queries and the `delete_event!/1` mutation.

  Every event is one profile's (ADR-078). Every reader takes a `t:scope/0`:
  a profile id for that profile's history, or `:all` for the install-wide
  view the Status page shows. The profile id is opaque here — this context
  never reads `MediaCentaur.Profiles`.
  """
  import Ecto.Query

  alias MediaCentaur.{Repo, Topics}
  alias MediaCentaur.WatchHistory.{Event, Rewatch, Stats}

  @typedoc "What a reader is asked for: one profile's history, or `:all` for the install-wide view the Status page shows."
  @type scope :: Ecto.UUID.t() | :all

  @doc "Subscribe to watch_history:events PubSub topic."
  def subscribe do
    Topics.subscribe(Topics.watch_history_events())
  end

  @doc "Insert a new Event. Called by Recorder."
  def create_event(attrs) do
    attrs
    |> Event.create_changeset()
    |> Repo.insert()
  end

  @doc "One of `profile_id`'s events by id, or nil. A delete is never install-wide, so no `:all`."
  @spec get_event(Ecto.UUID.t(), Ecto.UUID.t()) :: Event.t() | nil
  def get_event(profile_id, id) when is_binary(profile_id) and is_binary(id),
    do: Event |> scoped(profile_id) |> Repo.get(id)

  @doc """
  One profile's completion events, newest first.

  Options:
  - `:entity_type` — filter to `:movie`, `:episode`, or `:video_object`
  - `:search` — case-insensitive title substring match
  - `:date` — filter to a specific `Date`
  - `:limit` — max rows (default 100)
  - `:offset` — rows to skip (default 0)
  """
  @spec list_events(Ecto.UUID.t(), keyword()) :: [Event.t()]
  def list_events(profile_id, opts \\ []) when is_binary(profile_id) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    Event
    |> scoped(profile_id)
    |> maybe_filter_type(Keyword.get(opts, :entity_type))
    |> maybe_filter_search(Keyword.get(opts, :search))
    |> maybe_filter_date(Keyword.get(opts, :date))
    |> order_by([e], desc: e.completed_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "The N most recent completions in `scope`. Default 5."
  @spec recent_events(scope(), pos_integer()) :: [Event.t()]
  def recent_events(scope, limit \\ 5) do
    Event
    |> scoped(scope)
    |> order_by([e], desc: e.completed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Compute SVG heatmap cell sets for all entity types from a single DB query.
  Returns %{nil => cells_all, :movie => cells, :episode => cells, :video_object => cells}.
  """
  @spec heatmap_cells_by_type(scope()) :: map()
  def heatmap_cells_by_type(scope) do
    rows =
      Event
      |> scoped(scope)
      |> where([event], event.completed_at >= ^heatmap_cutoff_dt())
      |> group_by([event], [fragment("date(?)", event.completed_at), event.entity_type])
      |> select([event], {fragment("date(?)", event.completed_at), event.entity_type, count(event.id)})
      |> Repo.all()

    all_map = aggregate_rows_to_heatmap(rows, :all)

    by_type =
      Map.new([:movie, :episode, :video_object], fn type ->
        {type, aggregate_rows_to_heatmap(rows, type)}
      end)

    by_type
    |> Map.put(nil, all_map)
    |> Map.new(fn {type, heatmap} -> {type, Stats.heatmap_cells(heatmap)} end)
  end

  @doc """
  Compute aggregate stats: total count, total seconds, streak, heatmap.
  Uses DB aggregates so result-set size does not grow with event history.
  """
  @spec stats(scope()) :: map()
  def stats(scope) do
    %{
      total_count: Repo.aggregate(scoped(Event, scope), :count),
      total_seconds: Repo.aggregate(scoped(Event, scope), :sum, :duration_seconds) || 0.0,
      streak: compute_streak(scope),
      heatmap: heatmap_map(scope)
    }
  end

  defp heatmap_map(scope) do
    Event
    |> scoped(scope)
    |> where([event], event.completed_at >= ^heatmap_cutoff_dt())
    |> group_by([event], fragment("date(?)", event.completed_at))
    |> select([event], {fragment("date(?)", event.completed_at), count(event.id)})
    |> Repo.all()
    |> Map.new(fn {date_str, count} -> {Date.from_iso8601!(date_str), count} end)
  end

  defp compute_streak(scope) do
    Event
    |> scoped(scope)
    |> group_by([event], fragment("date(?)", event.completed_at))
    |> order_by([event], desc: fragment("date(?)", event.completed_at))
    |> select([event], fragment("date(?)", event.completed_at))
    |> Repo.all()
    |> Enum.map(&Date.from_iso8601!/1)
    |> Stats.streak_from_dates()
  end

  defp aggregate_rows_to_heatmap(rows, :all) do
    Enum.reduce(rows, %{}, fn {date_str, _type, count}, acc ->
      Map.update(acc, Date.from_iso8601!(date_str), count, &(&1 + count))
    end)
  end

  defp aggregate_rows_to_heatmap(rows, type) do
    rows
    |> Enum.filter(fn {_date, row_type, _count} -> row_type == type end)
    |> Map.new(fn {date_str, _type, count} -> {Date.from_iso8601!(date_str), count} end)
  end

  # Heatmap window: today minus 363 days, normalized to start-of-day UTC.
  defp heatmap_cutoff_dt do
    Date.utc_today()
    |> Date.add(-363)
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  @doc """
  Map of `entity_id => count` for all entities of the given type with at
  least one completion event. Useful when looking up many entities at once
  (e.g. annotating a list of event rows in HistoryLive).
  """
  @spec rewatch_count_map(scope(), Rewatch.entity_type()) :: %{Ecto.UUID.t() => pos_integer()}
  def rewatch_count_map(scope, type), do: Rewatch.count_per_entity(scope, type)

  @doc "Every profile with at least one completion — the profiles the summary is built for."
  @spec profile_ids_with_events() :: [Ecto.UUID.t()]
  def profile_ids_with_events,
    do: Repo.all(from(e in Event, distinct: true, select: e.profile_id, order_by: e.profile_id))

  @doc false
  @spec scoped(Ecto.Queryable.t(), scope()) :: Ecto.Queryable.t()
  def scoped(query, :all), do: query

  def scoped(query, profile_id) when is_binary(profile_id),
    do: where(query, [e], e.profile_id == ^profile_id)

  @doc """
  Delete an Event from history. The linked `WatchProgress` is left
  untouched — removing a history row is not marking the title unwatched.

  Returns `:ok`.
  """
  def delete_event!(%Event{} = event) do
    Repo.delete!(event)

    Topics.publish(
      Topics.watch_history_events(),
      {:watch_event_deleted, event}
    )

    :ok
  end

  # --- Private ---

  defp maybe_filter_type(query, nil), do: query
  defp maybe_filter_type(query, type), do: where(query, [e], e.entity_type == ^type)

  defp maybe_filter_search(query, nil), do: query
  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, search) do
    escaped =
      search
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    pattern = "%#{escaped}%"
    where(query, [e], fragment("lower(?) LIKE lower(?)", e.title, ^pattern))
  end

  defp maybe_filter_date(query, nil), do: query

  defp maybe_filter_date(query, %Date{} = date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
    where(query, [e], e.completed_at >= ^start_dt and e.completed_at <= ^end_dt)
  end
end
