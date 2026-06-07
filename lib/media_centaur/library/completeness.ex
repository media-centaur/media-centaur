defmodule MediaCentaur.Library.Completeness do
  @moduledoc """
  Read-only "library quality" gap queries for the Status page overview.

  Surfaces *where the library is thin or broken* in ways the owner can act
  on: containers with no TMDB metadata, and TV series with episode-number
  gaps inside a season. Missing-artwork is a separate disk-backed concern
  owned by `MediaCentaur.Library.ImageHealth` (surfaced via
  `MediaCentaur.Maintenance.missing_images_summary/0`); it is intentionally
  not duplicated here.

  Pure DB reads, no side effects. Gap *detection* is factored into the pure
  `detect_season_gaps/1` so it is unit-testable without a database.
  """
  import Ecto.Query

  alias MediaCentaur.Library.{Episode, ExternalId, Movie, MovieSeries, Season, TVSeries, VideoObject}
  alias MediaCentaur.Repo

  @doc """
  Count of library containers (movies, TV series, movie series, video
  objects) with no TMDB `ExternalId` row. Movies, series and video objects
  use the `"tmdb"` source; movie series use `"tmdb_collection"`.
  """
  @spec missing_metadata_count() :: non_neg_integer()
  def missing_metadata_count do
    count_without_tmdb(Movie, :movie, "tmdb") +
      count_without_tmdb(TVSeries, :tv_series, "tmdb") +
      count_without_tmdb(VideoObject, :video_object, "tmdb") +
      count_without_tmdb(MovieSeries, :movie_series, "tmdb_collection")
  end

  defp count_without_tmdb(schema, owner_type, source) do
    Repo.one(
      from(r in schema,
        as: :container,
        where:
          not exists(
            from(e in ExternalId,
              where:
                e.owner_id == parent_as(:container).id and
                  e.owner_type == ^owner_type and e.source == ^source,
              select: 1
            )
          ),
        select: count(r.id)
      )
    )
  end

  @doc """
  Count of TV series that have at least one episode-number gap within a
  single season. Delegates the detection to `detect_season_gaps/1`.
  """
  @spec incomplete_season_count() :: non_neg_integer()
  def incomplete_season_count do
    from(e in Episode,
      join: s in Season,
      on: s.id == e.season_id,
      select: %{
        tv_series_id: s.tv_series_id,
        season_number: s.season_number,
        episode_number: e.episode_number
      }
    )
    |> Repo.all()
    |> detect_season_gaps()
  end

  @doc """
  Counts distinct TV series that have an *internal* episode-number gap in
  any one season — a number missing inside the observed `min..max` range
  (e.g. episodes `[1, 2, 4]`). A series is counted at most once regardless
  of how many of its seasons are gapped. Missing leading episodes (a season
  that starts above 1) are not treated as a gap, since the true first
  episode number is not knowable from presence alone.

  `rows` is a list of `%{tv_series_id, season_number, episode_number}` maps.
  """
  @spec detect_season_gaps([
          %{tv_series_id: term(), season_number: term(), episode_number: integer() | nil}
        ]) ::
          non_neg_integer()
  def detect_season_gaps(rows) do
    rows
    |> Enum.group_by(&{&1.tv_series_id, &1.season_number})
    |> Enum.filter(fn {_key, episodes} ->
      season_has_gap?(Enum.map(episodes, & &1.episode_number))
    end)
    |> Enum.map(fn {{tv_series_id, _season_number}, _episodes} -> tv_series_id end)
    |> Enum.uniq()
    |> length()
  end

  defp season_has_gap?(episode_numbers) do
    numbers = episode_numbers |> Enum.reject(&is_nil/1) |> Enum.uniq()

    case numbers do
      [] ->
        false

      _ ->
        {min, max} = Enum.min_max(numbers)
        length(numbers) < max - min + 1
    end
  end
end
