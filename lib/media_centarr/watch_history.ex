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
  alias MediaCentarr.WatchHistory.{Event, Stats}

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
    events = Repo.all(Event)

    Map.new([nil, :movie, :episode, :video_object], fn type ->
      filtered = if type, do: Enum.filter(events, &(&1.entity_type == type)), else: events
      cells = filtered |> Stats.heatmap() |> Stats.heatmap_cells()
      {type, cells}
    end)
  end

  @doc """
  Compute aggregate stats from all events.
  Returns %{total_count, total_seconds, streak, heatmap}.
  """
  def stats do
    events = Repo.all(Event)
    Stats.compute(events)
  end

  @doc """
  Remove a WatchEvent from history. Does not affect library watch progress.
  """
  def remove_event!(%Event{} = event) do
    Repo.delete!(event)
    event
  end

  @doc """
  Delete a WatchEvent and reset the associated WatchProgress to incomplete.

  If the entity FK has been nilified (entity was deleted), the WatchProgress
  reset is skipped. Always returns the deleted event.
  """
  def delete_event!(%Event{} = event) do
    Repo.delete!(event)
    reset_watch_progress(event)
    event
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
