defmodule MediaCentarrWeb.LibraryProgress do
  @moduledoc """
  Pure helpers for watch-progress rendering — resume buttons, completion
  percentages, FK resolution for progress lookups, and the merge logic
  the LiveView uses to fold in incoming `:progress_changed` events
  without rebuilding the full entries list.
  """

  alias MediaCentarr.Library.{EpisodeList, MovieList}

  # --- Progress fraction + completion ---

  def compute_progress_fraction(nil), do: 0

  def compute_progress_fraction(%{
        episode_position_seconds: position,
        episode_duration_seconds: duration
      })
      when duration > 0 do
    Float.round(position / duration * 100, 1)
  end

  def compute_progress_fraction(_), do: 0

  @doc """
  Formats the completion percentage of a progress record for display.
  Returns `"42%"` or `"unknown"` when the duration is missing or zero.
  """
  @spec completion_percentage(map() | nil) :: String.t()
  def completion_percentage(%{position_seconds: position, duration_seconds: duration})
      when is_number(duration) and duration > 0 and is_number(position) do
    "#{trunc(Float.round(position / duration * 100, 0))}%"
  end

  def completion_percentage(_), do: "unknown"

  # --- Resume button labels ---

  def format_resume_parts(nil, _entry), do: {nil, nil}

  def format_resume_parts(%{"action" => "resume"} = resume, entry) do
    label =
      case resume do
        %{"seasonNumber" => season, "episodeNumber" => episode} ->
          "Season #{season} episode #{episode}"

        _ ->
          nil
      end

    time_remaining =
      case resume do
        %{"positionSeconds" => position, "durationSeconds" => duration}
        when is_number(duration) and duration > 0 ->
          remaining = max(trunc(duration - position), 0)
          MediaCentarrWeb.LibraryFormatters.format_human_duration(remaining) <> " remaining"

        _ ->
          episodes_remaining_label(entry.entity, entry.progress_records)
      end

    {label, time_remaining}
  end

  def format_resume_parts(%{"action" => "begin"} = resume, entry) do
    label =
      case resume do
        %{"seasonNumber" => season, "episodeNumber" => episode} ->
          "Play season #{season} episode #{episode}"

        _ ->
          "Play"
      end

    {label, episodes_remaining_label(entry.entity, entry.progress_records)}
  end

  def format_resume_parts(_resume, _entry), do: {nil, nil}

  def episodes_remaining_label(entity, progress_records) do
    total =
      case entity.type do
        :tv_series -> length(EpisodeList.list_available(entity))
        :movie_series -> length(MovieList.list_available(entity))
        _ -> 0
      end

    completed = Enum.count(progress_records, & &1.completed)
    remaining = total - completed

    case remaining do
      n when n > 1 -> "#{n} episodes remaining"
      1 -> "1 episode remaining"
      _ -> nil
    end
  end

  # --- Entry status ---

  def in_progress?(%{progress: nil}), do: false

  def in_progress?(%{progress: summary}) do
    summary.episodes_completed < summary.episodes_total
  end

  # --- Progress record merging ---

  def merge_progress_record(records, nil), do: records

  def merge_progress_record(records, changed) do
    key = progress_record_key(changed)

    case Enum.find_index(records, &(progress_record_key(&1) == key)) do
      nil -> records ++ [changed]
      index -> List.replace_at(records, index, changed)
    end
  end

  defp progress_record_key(record) do
    {Map.get(record, :episode_id), Map.get(record, :movie_id), Map.get(record, :video_object_id)}
  end

  def merge_extra_progress(records, nil), do: records

  def merge_extra_progress(records, changed) do
    case Enum.find_index(records, &(&1.extra_id == changed.extra_id)) do
      nil -> [changed | records]
      index -> List.replace_at(records, index, changed)
    end
  end

  @doc """
  Returns the most recent `last_watched_at` across an entry's progress records,
  or `nil` if the entry has none. Used to sort the Continue Watching list.
  """
  def max_last_watched_at(%{progress_records: []}), do: nil

  def max_last_watched_at(%{progress_records: records}) do
    records
    |> Enum.map(& &1.last_watched_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  # --- Progress FK resolution ---

  @doc """
  Resolves `{fk_key, fk_id}` for a watch-progress lookup from the cached
  `entries_by_id` map. Called from LibraryLive before dispatching progress
  updates — pure, no DB access.

  `season_number == 0` selects a movie (standalone or an entry within a
  movie series, indexed by `ordinal`). Any non-zero `season_number`
  selects an episode within a TV series.
  """
  @spec resolve_progress_fk(map(), String.t(), non_neg_integer(), non_neg_integer()) ::
          {:movie_id, String.t() | nil} | {:episode_id, String.t() | nil}
  def resolve_progress_fk(entries_by_id, entity_id, 0, ordinal) do
    case Map.get(entries_by_id, entity_id) do
      %{entity: %{type: :movie_series, movies: movies}} when is_list(movies) ->
        {:movie_id, find_movie_in_series(movies, ordinal)}

      %{entity: %{type: :movie, id: id}} ->
        {:movie_id, id}

      _ ->
        {:movie_id, entity_id}
    end
  end

  def resolve_progress_fk(entries_by_id, entity_id, season_number, episode_number) do
    case Map.get(entries_by_id, entity_id) do
      %{entity: %{type: :tv_series, seasons: seasons}} when is_list(seasons) ->
        {:episode_id, find_episode_in_seasons(seasons, season_number, episode_number)}

      _ ->
        {:episode_id, nil}
    end
  end

  defp find_movie_in_series(movies, ordinal) do
    available = MovieList.list_available(%{movies: movies})

    case Enum.find(available, fn {ord, _id, _url} -> ord == ordinal end) do
      {_ord, movie_id, _url} -> movie_id
      nil -> nil
    end
  end

  defp find_episode_in_seasons(seasons, season_number, episode_number) do
    with %{episodes: episodes} when is_list(episodes) <-
           Enum.find(seasons, &(&1.season_number == season_number)),
         %{id: id} <- Enum.find(episodes, &(&1.episode_number == episode_number)) do
      id
    else
      _ -> nil
    end
  end
end
