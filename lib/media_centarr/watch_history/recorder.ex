defmodule MediaCentarr.WatchHistory.Recorder do
  @moduledoc """
  GenServer that subscribes to `"library:watch_completed"` and records a
  `WatchEvent` for each transition-to-completed.

  `Library.mark_watch_completed/1` broadcasts `{:entity_watch_completed, record}`
  exactly once per transition (pre-update record had `completed: false`), so no
  dedup is needed here.
  """
  use GenServer

  require MediaCentarr.Log, as: Log

  import Ecto.Query

  alias MediaCentarr.{Repo, Topics, WatchHistory}
  alias MediaCentarr.Library.{Episode, Movie, VideoObject}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_watch_completed())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:entity_watch_completed, record}, state) do
    record_completion(record)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp record_completion(record) do
    case build_event_attrs(record) do
      {:ok, attrs} ->
        case WatchHistory.create_event(attrs) do
          {:ok, event} ->
            Phoenix.PubSub.broadcast(
              MediaCentarr.PubSub,
              Topics.watch_history_events(),
              {:watch_event_created, event}
            )

            Log.info(:playback, "watch history: recorded — #{attrs.title}")

          {:error, reason} ->
            Log.error(:playback, "watch history: insert failed — #{inspect(reason)}")
        end

      {:error, reason} ->
        Log.error(:playback, "watch history: could not resolve title — #{inspect(reason)}")
    end
  end

  defp build_event_attrs(%{movie_id: movie_id} = record) when not is_nil(movie_id) do
    case Repo.get(Movie, movie_id) do
      nil ->
        {:error, :movie_not_found}

      movie ->
        {:ok,
         %{
           entity_type: :movie,
           movie_id: movie_id,
           title: movie.name,
           duration_seconds: record.duration_seconds,
           completed_at: DateTime.utc_now(:second)
         }}
    end
  end

  defp build_event_attrs(%{episode_id: episode_id} = record) when not is_nil(episode_id) do
    # Single JOIN query instead of Repo.get + Repo.preload(season: :tv_series),
    # which fanned out to three round trips. All we need is four strings
    # for the title — no reason to hydrate full schemas.
    query =
      from e in Episode,
        join: s in assoc(e, :season),
        join: tv in assoc(s, :tv_series),
        where: e.id == ^episode_id,
        select: %{
          episode_name: e.name,
          episode_number: e.episode_number,
          season_number: s.season_number,
          series_name: tv.name
        }

    case Repo.one(query) do
      nil ->
        {:error, :episode_not_found}

      parts ->
        {:ok,
         %{
           entity_type: :episode,
           episode_id: episode_id,
           title: format_episode_title(parts),
           duration_seconds: record.duration_seconds,
           completed_at: DateTime.utc_now(:second)
         }}
    end
  end

  defp build_event_attrs(%{video_object_id: video_object_id} = record)
       when not is_nil(video_object_id) do
    case Repo.get(VideoObject, video_object_id) do
      nil ->
        {:error, :video_object_not_found}

      video_object ->
        {:ok,
         %{
           entity_type: :video_object,
           video_object_id: video_object_id,
           title: video_object.name,
           duration_seconds: record.duration_seconds,
           completed_at: DateTime.utc_now(:second)
         }}
    end
  end

  defp format_episode_title(%{
         series_name: series,
         season_number: season_number,
         episode_number: episode_number,
         episode_name: episode_name
       }) do
    season_num = String.pad_leading("#{season_number}", 2, "0")
    ep_num = String.pad_leading("#{episode_number}", 2, "0")
    code = "S#{season_num}E#{ep_num}"

    if episode_name && episode_name != "" do
      "#{series} #{code} — #{episode_name}"
    else
      "#{series} #{code}"
    end
  end
end
