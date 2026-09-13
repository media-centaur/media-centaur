defmodule MediaCentaur.Library.Completeness do
  @moduledoc """
  Read-only "library quality" gap queries for the Status page overview.

  Surfaces *where the library is thin or broken* in ways the owner can act
  on: containers with no TMDB metadata, and TV seasons holding aired
  episodes the library has no file for. Missing-artwork is a separate disk-backed concern
  owned by `MediaCentaur.Library.ImageHealth` (surfaced via
  `MediaCentaur.Maintenance.missing_images_summary/0`); it is intentionally
  not duplicated here.

  Pure DB reads, no side effects.
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
  Count of seasons holding at least one episode TMDB lists that has aired
  and that the library has no file for.

  A season whose `episode_list` is empty never counts: the list is a
  snapshot of TMDB, and its absence is not evidence of a gap. Run *Refresh
  episode lists* under Settings → Maintenance to populate it. An entry TMDB
  has not dated counts as aired, matching how the detail modal renders it.

  This replaced an episode-number-gap heuristic on 2026-09-13. That version
  counted *series* under a label reading "Incomplete seasons", missed a
  season that simply stops early, and could not tell an unaired episode
  from an absent one.
  """
  @spec incomplete_season_count() :: non_neg_integer()
  def incomplete_season_count do
    today = Date.utc_today()
    owned = owned_episode_numbers()

    from(s in Season, select: %{id: s.id, episode_list: s.episode_list})
    |> Repo.all()
    |> Enum.count(&season_short?(&1, owned, today))
  end

  # `%{season_id => MapSet.t(episode_number)}` over every library episode.
  defp owned_episode_numbers do
    from(e in Episode, select: {e.season_id, e.episode_number})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {season_id, numbers} -> {season_id, MapSet.new(numbers)} end)
  end

  defp season_short?(season, owned, today) do
    have = Map.get(owned, season.id, MapSet.new())

    Enum.any?(season.episode_list || [], fn entry ->
      aired?(entry.air_date, today) and not MapSet.member?(have, entry.episode_number)
    end)
  end

  defp aired?(nil, _today), do: true
  defp aired?(air_date, today), do: Date.compare(air_date, today) != :gt
end
