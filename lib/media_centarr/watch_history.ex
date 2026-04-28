defmodule MediaCentarr.WatchHistory do
  use Boundary, deps: [MediaCentarr.Library], exports: []

  @moduledoc """
  Public API for the WatchHistory bounded context.

  Records a permanent, append-only `WatchEvent` for each completion (≥90%
  playback threshold). The `Recorder` GenServer drives writes; this module
  exposes queries and the `delete_event!/1` mutation.
  """
  import Ecto.Query

  alias MediaCentarr.{Library, Repo, Topics}
  alias MediaCentarr.WatchHistory.{Event, Rewatch, Stats}

  @doc "Subscribe to watch_history:events PubSub topic."
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.watch_history_events())
  end

  @doc "Insert a new WatchEvent. Called by Recorder."
  def create_event(attrs) do
    attrs
    |> Event.create_changeset()
    |> Repo.insert()
  end

  @doc "Get a single event by id, raising if not found."
  def get_event!(id), do: Repo.get!(Event, id)

  @doc "Get a single event by id, returning nil if not found."
  def get_event(id), do: Repo.get(Event, id)

  @doc """
  List completion events, newest first.

  Options:
  - `:entity_type` — filter to `:movie`, `:episode`, or `:video_object`
  - `:search` — case-insensitive title substring match
  - `:date` — filter to a specific `Date`
  - `:limit` — max rows (default 100)
  - `:offset` — rows to skip (default 0)
  """
  def list_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    entity_type = Keyword.get(opts, :entity_type)
    search = Keyword.get(opts, :search)
    date = Keyword.get(opts, :date)

    Event
    |> maybe_filter_type(entity_type)
    |> maybe_filter_search(search)
    |> maybe_filter_date(date)
    |> order_by([e], desc: e.completed_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Return the N most recent completion events. Default 5.
  """
  def recent_events(limit \\ 5) do
    Event
    |> order_by([e], desc: e.completed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Compute SVG heatmap cell sets for all entity types from a single DB query.
  Returns %{nil => cells_all, :movie => cells, :episode => cells, :video_object => cells}.
  """
  def heatmap_cells_by_type do
    rows =
      Repo.all(
        from(event in Event,
          where: event.completed_at >= ^heatmap_cutoff_dt(),
          group_by: [fragment("date(?)", event.completed_at), event.entity_type],
          select: {fragment("date(?)", event.completed_at), event.entity_type, count(event.id)}
        )
      )

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
  def stats do
    %{
      total_count: Repo.aggregate(Event, :count),
      total_seconds: Repo.aggregate(Event, :sum, :duration_seconds) || 0.0,
      streak: compute_streak(),
      heatmap: heatmap_map()
    }
  end

  defp heatmap_map do
    from(event in Event,
      where: event.completed_at >= ^heatmap_cutoff_dt(),
      group_by: fragment("date(?)", event.completed_at),
      select: {fragment("date(?)", event.completed_at), count(event.id)}
    )
    |> Repo.all()
    |> Map.new(fn {date_str, count} -> {Date.from_iso8601!(date_str), count} end)
  end

  defp compute_streak do
    from(event in Event,
      group_by: fragment("date(?)", event.completed_at),
      order_by: [desc: fragment("date(?)", event.completed_at)],
      select: fragment("date(?)", event.completed_at)
    )
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
  Count of completion events for a single entity. Returns 0 if never watched.

  Pure delegation to `Rewatch`.
  """
  @spec rewatch_count(Rewatch.entity_type(), Ecto.UUID.t()) :: non_neg_integer()
  def rewatch_count(type, entity_id) do
    type
    |> Rewatch.count_per_entity()
    |> Map.get(entity_id, 0)
  end

  @doc """
  Map of `entity_id => count` for all entities of the given type with at
  least one completion event. Useful when looking up many entities at once
  (e.g. annotating a list of event rows in HistoryLive).
  """
  @spec rewatch_count_map(Rewatch.entity_type()) :: %{Ecto.UUID.t() => pos_integer()}
  def rewatch_count_map(type), do: Rewatch.count_per_entity(type)

  @doc """
  Most-rewatched entities. See `Rewatch.top_rewatches/1` for options.
  """
  @spec top_rewatches(keyword()) :: [Rewatch.rewatch_row()]
  def top_rewatches(opts \\ []), do: Rewatch.top_rewatches(opts)

  @doc """
  Delete a WatchEvent from history.

  By default the linked `WatchProgress` is left untouched (use `remove from
  history` semantics). Pass `reset_progress: true` to also reset the linked
  progress to incomplete — used when the user wants to mark the title as
  unwatched, not just prune the history row.

  If the entity FK has been nilified (the entity was deleted), the progress
  reset is skipped silently.

  Returns `:ok`.
  """
  def delete_event!(%Event{} = event, opts \\ []) do
    Repo.delete!(event)
    if Keyword.get(opts, :reset_progress, false), do: reset_watch_progress(event)
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

  defp reset_watch_progress(%Event{movie_id: movie_id}) when not is_nil(movie_id) do
    case Library.get_watch_progress_by_fk(:movie_id, movie_id) do
      {:ok, progress} ->
        Library.mark_watch_incomplete(progress)
        Library.broadcast_entities_changed([movie_id])

      _ ->
        :ok
    end
  end

  defp reset_watch_progress(%Event{episode_id: episode_id}) when not is_nil(episode_id) do
    case Library.get_watch_progress_by_fk(:episode_id, episode_id) do
      {:ok, progress} ->
        Library.mark_watch_incomplete(progress)
        Library.broadcast_entities_changed([episode_id])

      _ ->
        :ok
    end
  end

  defp reset_watch_progress(%Event{video_object_id: video_object_id}) when not is_nil(video_object_id) do
    case Library.get_watch_progress_by_fk(:video_object_id, video_object_id) do
      {:ok, progress} ->
        Library.mark_watch_incomplete(progress)
        Library.broadcast_entities_changed([video_object_id])

      _ ->
        :ok
    end
  end

  defp reset_watch_progress(_event), do: :ok
end
