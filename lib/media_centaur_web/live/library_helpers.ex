defmodule MediaCentaurWeb.LibraryHelpers do
  @moduledoc """
  Pure helper functions for the library LiveView — filtering, sorting,
  progress computation, and display formatting.

  Extracted from LibraryLive to keep the LiveView focused on state management
  and rendering.
  """

  alias MediaCentaur.{DateUtil, Playback.EpisodeList, Playback.MovieList}

  @movie_types [:movie, :movie_series, :video_object]

  # --- Filtering ---

  def filtered_by_tab(entries, :all), do: entries

  def filtered_by_tab(entries, :movies) do
    Enum.filter(entries, fn %{entity: entity} ->
      entity.type in @movie_types
    end)
  end

  def filtered_by_tab(entries, :tv) do
    Enum.filter(entries, fn %{entity: entity} -> entity.type == :tv_series end)
  end

  def filtered_by_text(entries, ""), do: entries

  def filtered_by_text(entries, text) do
    needle = String.downcase(text)

    Enum.filter(entries, fn %{entity: entity} ->
      name_matches?(entity.name, needle) || nested_matches?(entity, needle)
    end)
  end

  defp name_matches?(nil, _needle), do: false
  defp name_matches?(name, needle), do: String.contains?(String.downcase(name), needle)

  defp nested_matches?(%{type: :tv_series, seasons: seasons}, needle) when is_list(seasons) do
    Enum.any?(seasons, fn season ->
      Enum.any?(season.episodes || [], fn episode -> name_matches?(episode.name, needle) end)
    end)
  end

  defp nested_matches?(%{type: :movie_series, movies: movies}, needle) when is_list(movies) do
    Enum.any?(movies, fn movie -> name_matches?(movie.name, needle) end)
  end

  defp nested_matches?(_entity, _needle), do: false

  # --- Sorting ---

  def sorted_by(entries, :alpha) do
    Enum.sort_by(entries, fn entry -> (entry.entity.name || "") |> String.downcase() end)
  end

  def sorted_by(entries, :year) do
    Enum.sort_by(
      entries,
      fn entry -> entry.entity.date_published || "" end,
      :desc
    )
  end

  def sorted_by(entries, :recent) do
    Enum.sort_by(
      entries,
      fn entry -> entry.entity.inserted_at || ~U[2000-01-01 00:00:00Z] end,
      {:desc, DateTime}
    )
  end

  # --- Tab Counts ---

  def tab_counts(entries) do
    Enum.reduce(entries, %{all: 0, movies: 0, tv: 0}, fn %{entity: entity}, counts ->
      counts = %{counts | all: counts.all + 1}

      cond do
        entity.type in @movie_types ->
          %{counts | movies: counts.movies + 1}

        entity.type == :tv_series ->
          %{counts | tv: counts.tv + 1}

        true ->
          counts
      end
    end)
  end

  # --- Progress ---

  def compute_progress_fraction(nil), do: 0

  def compute_progress_fraction(%{
        episode_position_seconds: position,
        episode_duration_seconds: duration
      })
      when duration > 0 do
    Float.round(position / duration * 100, 1)
  end

  def compute_progress_fraction(_), do: 0

  # --- Resume Formatting ---

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
          format_human_duration(remaining) <> " remaining"

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

  def format_human_duration(seconds) when seconds >= 3600 do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    if minutes > 0,
      do: "#{hours}h #{minutes}m",
      else: "#{hours}h"
  end

  def format_human_duration(seconds) when seconds >= 60 do
    "#{div(seconds, 60)}m"
  end

  def format_human_duration(_seconds), do: "< 1m"

  # --- Display ---

  def format_type(:movie), do: "Movie"
  def format_type(:movie_series), do: "Movie Series"
  def format_type(:tv_series), do: "TV Series"
  def format_type(:video_object), do: "Video"
  def format_type(type), do: type |> to_string() |> String.capitalize()

  def extract_year(date_string), do: DateUtil.extract_year(date_string) || ""

  # --- Progress Record Merging ---

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

  def merge_extra_progress(records, nil), do: records

  def merge_extra_progress(records, changed) do
    case Enum.find_index(records, &(&1.extra_id == changed.extra_id)) do
      nil -> [changed | records]
      index -> List.replace_at(records, index, changed)
    end
  end

  # --- Entry Status ---

  def in_progress?(%{progress: nil}), do: false

  def in_progress?(%{progress: summary}) do
    summary.episodes_completed < summary.episodes_total
  end
end
