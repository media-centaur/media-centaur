defmodule MediaCentarr.Profile.Loader do
  @moduledoc """
  Deterministic fixture seeding for profile runs (ADR-041).

  Calls only the public Library write API so we don't drag
  `test/support/factory.ex` into the dev compile path. Determinism
  comes from a single `:rand.seed/2` keyed on the scale name —
  re-runs at the same scale produce byte-identical row counts and
  values, so an unexpected diff in the report points at code, not
  RNG drift.

  ## Scales

  | Scale  | Movies | Series × Episodes | In-progress |
  |--------|--------|-------------------|-------------|
  | small  |   100  | 20 × 5  =   100   |     12      |
  | medium |  1000  | 100 × 10 = 1000   |     50      |
  | large  |  5000  | 300 × 15 = 4500   |    100      |

  In-progress count is the dimension that matters for
  `Library.Views.ContinueWatching` — the new
  `(completed, last_watched_at)` index makes total table size
  largely irrelevant. We grow it anyway so Library queries that
  scan more rows (recently_added, browser, etc., once projected)
  see a representative load.
  """

  alias MediaCentarr.Library
  alias MediaCentarr.Watcher.FilePresence

  @type scale :: :small | :medium | :large

  @scale_configs %{
    small: %{
      seed: 11,
      movies: 100,
      series: 20,
      episodes_per_series: 5,
      in_progress_movies: 8,
      in_progress_episodes: 4
    },
    medium: %{
      seed: 42,
      movies: 1000,
      series: 100,
      episodes_per_series: 10,
      in_progress_movies: 35,
      in_progress_episodes: 15
    },
    large: %{
      seed: 73,
      movies: 5000,
      series: 300,
      episodes_per_series: 15,
      in_progress_movies: 70,
      in_progress_episodes: 30
    }
  }

  @doc "Returns the named scale config (movies, series, in-progress counts, RNG seed)."
  @spec config(scale()) :: map()
  def config(scale), do: Map.fetch!(@scale_configs, scale)

  @doc """
  Seeds the database with deterministic fixtures for the given scale.

  Idempotency note: this assumes the DB starts empty. The
  `scripts/profile` entry point wipes `priv/profile/` before each
  run; if you call `amplify!/1` against a non-empty DB you'll get
  duplicates and (likely) constraint failures.
  """
  @spec amplify!(scale()) :: %{movies: [pos_integer()], episodes: [pos_integer()]}
  def amplify!(scale) do
    cfg = config(scale)
    :rand.seed(:exsplus, {cfg.seed, 0, 0})

    movie_ids = seed_movies(cfg.movies)
    episode_ids = seed_series(cfg.series, cfg.episodes_per_series)

    seed_in_progress_for_movies(movie_ids, cfg.in_progress_movies)
    seed_in_progress_for_episodes(episode_ids, cfg.in_progress_episodes)

    %{movies: movie_ids, episodes: episode_ids}
  end

  defp seed_movies(count) do
    Enum.map(1..count, fn i ->
      movie =
        Library.create_movie!(%{
          name: "Profile Movie #{i}",
          position: 0
        })

      file_path = Path.join("priv/profile/media", "movie_#{i}.mkv")
      Library.link_file!(%{movie_id: movie.id, file_path: file_path, watch_dir: "priv/profile/media"})
      :ok = FilePresence.record_file(file_path, "priv/profile/media")

      movie.id
    end)
  end

  defp seed_series(count, episodes_per_series) do
    Enum.flat_map(1..count, fn series_index ->
      series = Library.create_tv_series!(%{name: "Profile Series #{series_index}"})
      file_path = Path.join("priv/profile/media", "series_#{series_index}.mkv")

      Library.link_file!(%{
        tv_series_id: series.id,
        file_path: file_path,
        watch_dir: "priv/profile/media"
      })

      :ok = FilePresence.record_file(file_path, "priv/profile/media")

      season =
        Library.create_season!(%{
          tv_series_id: series.id,
          season_number: 1,
          name: "Season 1"
        })

      Enum.map(1..episodes_per_series, fn episode_number ->
        episode =
          Library.create_episode!(%{
            season_id: season.id,
            episode_number: episode_number,
            name: "S01E#{episode_number}",
            content_url: "/profile/series_#{series_index}_s01e#{episode_number}.mkv"
          })

        episode.id
      end)
    end)
  end

  defp seed_in_progress_for_movies(movie_ids, count) do
    movie_ids
    |> deterministic_sample(count)
    |> Enum.with_index()
    |> Enum.each(fn {movie_id, index} ->
      {:ok, _} =
        Library.find_or_create_watch_progress_for_movie(%{
          movie_id: movie_id,
          position_seconds: 30.0 + index * 1.5,
          duration_seconds: 100.0,
          completed: false
        })
    end)
  end

  defp seed_in_progress_for_episodes(episode_ids, count) do
    episode_ids
    |> deterministic_sample(count)
    |> Enum.with_index()
    |> Enum.each(fn {episode_id, index} ->
      {:ok, _} =
        Library.find_or_create_watch_progress_for_episode(%{
          episode_id: episode_id,
          position_seconds: 60.0 + index * 1.5,
          duration_seconds: 1000.0,
          completed: false
        })
    end)
  end

  defp deterministic_sample(list, n) when length(list) <= n, do: list

  defp deterministic_sample(list, n) do
    list
    |> Enum.map(fn item -> {:rand.uniform(), item} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.take(n)
    |> Enum.map(&elem(&1, 1))
  end
end
