defmodule MediaCentaur.WatchHistory.Recorder do
  @moduledoc """
  GenServer that subscribes to `"playback:events"` and records a `WatchEvent`
  whenever a movie, episode, or video object is completed (≥90% threshold).

  The `MpvSession.maybe_mark_completed/3` guard (`not record.completed`) ensures
  this broadcast fires exactly once per physical viewing — no dedup needed here.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.{Repo, Topics, WatchHistory}
  alias MediaCentaur.Library.{Episode, Movie, VideoObject}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.playback_events())
    {:ok, %{}}
  end

  @impl true
  def handle_info(
        {:entity_progress_updated, %{changed_record: %{completed: true} = record}},
        state
      ) do
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
              MediaCentaur.PubSub,
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
           completed_at: DateTime.truncate(DateTime.utc_now(), :second)
         }}
    end
  end

  defp build_event_attrs(%{episode_id: episode_id} = record) when not is_nil(episode_id) do
    case Repo.get(Episode, episode_id) do
      nil ->
        {:error, :episode_not_found}

      episode ->
        episode = Repo.preload(episode, season: :tv_series)
        title = format_episode_title(episode)

        {:ok,
         %{
           entity_type: :episode,
           episode_id: episode_id,
           title: title,
           duration_seconds: record.duration_seconds,
           completed_at: DateTime.truncate(DateTime.utc_now(), :second)
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
           completed_at: DateTime.truncate(DateTime.utc_now(), :second)
         }}
    end
  end

  defp format_episode_title(episode) do
    season_num = String.pad_leading("#{episode.season.season_number}", 2, "0")
    ep_num = String.pad_leading("#{episode.episode_number}", 2, "0")
    code = "S#{season_num}E#{ep_num}"
    series = episode.season.tv_series.name

    if episode.name && episode.name != "" do
      "#{series} #{code} — #{episode.name}"
    else
      "#{series} #{code}"
    end
  end
end
