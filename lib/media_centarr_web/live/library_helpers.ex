defmodule MediaCentarrWeb.LibraryHelpers do
  @moduledoc """
  Pure helper functions for the library LiveView — filtering, sorting,
  progress computation, and display formatting.

  Extracted from LibraryLive to keep the LiveView focused on state management
  and rendering.
  """

  alias MediaCentarr.{DateUtil, Images.Availability, Library.EpisodeList, Library.MovieList}

  @movie_types [:movie, :movie_series, :video_object]

  # --- Availability precomputation ---

  @doc """
  Counts entries whose backing storage is currently offline.

  Accepts an optional predicate for test injection; defaults to
  `Images.Availability.available?/1`, which is a persistent-term read.
  Computed once per entries/dir-status change rather than every render.
  """
  @spec unavailable_count(list(), (map() -> boolean())) :: non_neg_integer()
  def unavailable_count(entries, available_fn \\ &Availability.available?/1) do
    Enum.count(entries, fn entry -> not available_fn.(entry.entity) end)
  end

  @doc """
  Builds `%{entity_id => available?}` for the template's per-card lookups.

  Avoids calling `Images.Availability.available?/1` once per card on every
  render — each call digs into `entity.watched_files` to resolve the
  owning watch_dir, which is cheap individually but adds up across a full
  grid of poster cards.
  """
  @spec availability_map(list(), (map() -> boolean())) :: %{String.t() => boolean()}
  def availability_map(entries, available_fn \\ &Availability.available?/1) do
    Map.new(entries, fn entry -> {entry.entity.id, available_fn.(entry.entity)} end)
  end

  # --- Surgical entry updates ---

  @doc """
  Applies `updater` to a single entry identified by `entity_id` without
  rebuilding the `entries_by_id` map from scratch.

  Returns `{:ok, {new_entries, new_entries_by_id}}` on a hit, or
  `:not_found` when the id is absent.

  Progress and extra-progress events affect one entity; this helper keeps
  the O(n) cost bounded to a single list walk instead of the walk plus
  the `Map.new/2` map-rebuild that `assign_entries/2` performs.
  """
  @spec apply_entry_update(list(), map(), String.t(), (map() -> map())) ::
          {:ok, {list(), map()}} | :not_found
  def apply_entry_update(entries, entries_by_id, entity_id, updater) do
    case Map.get(entries_by_id, entity_id) do
      nil ->
        :not_found

      existing ->
        updated = updater.(existing)

        new_entries =
          Enum.map(entries, fn
            %{entity: %{id: ^entity_id}} -> updated
            entry -> entry
          end)

        {:ok, {new_entries, Map.put(entries_by_id, entity_id, updated)}}
    end
  end

  # --- Storage-offline banner summary ---

  @doc """
  Builds the one-line summary shown in the `storage_offline_banner`.

  Takes the per-dir state map (from `Images.Availability.dir_status/0`)
  and a count of library entries currently unavailable. Returns a
  human-readable string or `nil` when no dir is offline.
  """
  @spec offline_summary(%{String.t() => atom()}, non_neg_integer()) :: String.t() | nil
  def offline_summary(dir_status, unavailable_count) do
    offline_dirs =
      dir_status
      |> Enum.filter(fn {_dir, state} -> state == :unavailable end)
      |> Enum.map(fn {dir, _} -> dir end)

    case offline_dirs do
      [] ->
        nil

      [dir] ->
        "#{dir} is offline — #{items_phrase(unavailable_count)} temporarily unavailable."

      dirs ->
        "#{length(dirs)} storage locations offline — #{items_phrase(unavailable_count)} temporarily unavailable."
    end
  end

  defp items_phrase(1), do: "1 item"
  defp items_phrase(n), do: "#{n} items"

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
    Enum.sort_by(entries, fn entry -> String.downcase(entry.entity.name || "") end)
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

  # --- Watch Progress ---

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

  # --- Reload Strategy ---

  @doc """
  Decides whether the library grid stream needs a full reset or can be
  updated surgically after a batch of entity changes.

  Additions require a full `reset_stream` because `stream_insert/3` without
  an `:at` option appends, which misplaces new entries under any non-trivial
  sort order. Pure deletions and in-place updates are handled surgically by
  `touch_stream_entries/2` — its `entry == nil` branch issues
  `stream_delete_by_dom_id` for IDs that were removed from `entries_by_id`.

  This keeps the common case (file removed from disk → one card disappears)
  from tearing down the entire grid's DOM, which is user-visible as a
  flash across every item on screen.
  """
  @spec reload_strategy(%{new_entries: list(), changed_ids: MapSet.t()}) ::
          :reset | {:touch, list()}
  def reload_strategy(%{new_entries: [_ | _]}), do: :reset

  def reload_strategy(%{new_entries: [], changed_ids: changed_ids}),
    do: {:touch, MapSet.to_list(changed_ids)}
end
