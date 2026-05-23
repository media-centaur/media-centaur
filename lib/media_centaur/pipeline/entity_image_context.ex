defmodule MediaCentaur.Pipeline.EntityImageContext do
  @moduledoc """
  Locates the two facts the image pipeline needs about an entity before
  it can (re)fetch artwork: its **TMDB id** and a **watch_dir**.

  Shared by `Pipeline.ImageRepair` (rebuilding queue rows for missing
  images) and `Pipeline.ImageRefresh` (forcing a per-entity re-fetch).
  Both lookups return `{:ok, value}` or `{:skip, reason}` so callers can
  `with`-chain them.

  TMDB ids live on `library_external_ids` (Library Schema v2 Phase 1
  Task 6) — read directly via the `(source, owner)` tuple so this stays
  a single SQL trip. WatchedFiles no longer carry per-type FKs (Phase 2
  Task B), so a watch_dir is found by walking `library_playable_items`.
  """
  import Ecto.Query

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Episode
  alias MediaCentaur.Library.Movie
  alias MediaCentaur.Library.PlayableItem
  alias MediaCentaur.Library.Season
  alias MediaCentaur.Library.WatchedFile
  alias MediaCentaur.Repo

  # -- tmdb lookup ---------------------------------------------------------
  # Returns {:ok, tmdb_id} for top-level entities, or
  # {:ok, {tmdb_id, season_number, episode_number, parent_tv_series_id}}
  # for episodes.

  def find_tmdb_context(entity_id, :movie), do: lookup_tmdb_id(entity_id, :tmdb, :movie)

  def find_tmdb_context(entity_id, :tv_series), do: lookup_tmdb_id(entity_id, :tmdb, :tv_series)

  def find_tmdb_context(entity_id, :movie_series),
    do: lookup_tmdb_id(entity_id, :tmdb_collection, :movie_series)

  def find_tmdb_context(entity_id, :video_object), do: lookup_tmdb_id(entity_id, :tmdb, :video_object)

  def find_tmdb_context(episode_id, :episode) do
    with {:ok, episode} <- Library.fetch_episode(episode_id),
         %Season{} = season <- Repo.get(Season, episode.season_id),
         {:ok, tmdb_id} <- find_tmdb_context(season.tv_series_id, :tv_series) do
      {:ok, {tmdb_id, season.season_number, episode.episode_number, season.tv_series_id}}
    else
      _ -> {:skip, :no_tmdb_id}
    end
  end

  defp lookup_tmdb_id(entity_id, source_atom, owner_type) do
    source_str = Atom.to_string(source_atom)

    result =
      Repo.one(
        from(e in MediaCentaur.Library.ExternalId,
          where:
            e.owner_id == ^entity_id and e.owner_type == ^owner_type and
              e.source == ^source_str,
          select: e.external_id,
          limit: 1
        )
      )

    case result do
      tmdb_id when is_binary(tmdb_id) and tmdb_id != "" -> {:ok, tmdb_id}
      _ -> {:skip, :no_tmdb_id}
    end
  end

  # -- watch_dir lookup ----------------------------------------------------
  #
  #   :episode      — PlayableItem(:episode, container_id=episode_id)
  #   :movie /      — PlayableItem(:movie | :video_object,
  #   :video_object   container_id=entity_id)
  #   :tv_series    — through seasons → episodes → playable_items
  #   :movie_series — through child movies → playable_items

  def find_watch_dir(episode_id, :episode) do
    # Try the Episode's own WatchedFiles first; fall back to any other
    # Episode in the same TVSeries if this one has none yet.
    direct =
      Repo.one(
        from(wf in WatchedFile,
          join: pi in PlayableItem,
          on: pi.id == wf.playable_item_id and pi.container_type == :episode,
          where: pi.container_id == ^episode_id and not is_nil(wf.watch_dir),
          select: wf.watch_dir,
          limit: 1
        )
      )

    case direct do
      watch_dir when is_binary(watch_dir) ->
        {:ok, watch_dir}

      _ ->
        with {:ok, %Episode{} = episode} <- Library.fetch_episode(episode_id),
             %Season{} = season <- Repo.get(Season, episode.season_id) do
          find_watch_dir(season.tv_series_id, :tv_series)
        else
          _ -> {:skip, :no_watch_dir}
        end
    end
  end

  def find_watch_dir(entity_id, :movie) do
    ok_or_skip(
      Repo.one(
        from(wf in WatchedFile,
          join: pi in PlayableItem,
          on: pi.id == wf.playable_item_id and pi.container_type == :movie,
          where: pi.container_id == ^entity_id and not is_nil(wf.watch_dir),
          select: wf.watch_dir,
          limit: 1
        )
      )
    )
  end

  def find_watch_dir(entity_id, :video_object) do
    ok_or_skip(
      Repo.one(
        from(wf in WatchedFile,
          join: pi in PlayableItem,
          on: pi.id == wf.playable_item_id and pi.container_type == :video_object,
          where: pi.container_id == ^entity_id and not is_nil(wf.watch_dir),
          select: wf.watch_dir,
          limit: 1
        )
      )
    )
  end

  def find_watch_dir(tv_series_id, :tv_series) do
    ok_or_skip(
      Repo.one(
        from(wf in WatchedFile,
          join: pi in PlayableItem,
          on: pi.id == wf.playable_item_id and pi.container_type == :episode,
          join: e in Episode,
          on: e.id == pi.container_id,
          join: s in Season,
          on: s.id == e.season_id,
          where: s.tv_series_id == ^tv_series_id and not is_nil(wf.watch_dir),
          select: wf.watch_dir,
          limit: 1
        )
      )
    )
  end

  def find_watch_dir(movie_series_id, :movie_series) do
    ok_or_skip(
      Repo.one(
        from(wf in WatchedFile,
          join: pi in PlayableItem,
          on: pi.id == wf.playable_item_id and pi.container_type == :movie,
          join: m in Movie,
          on: m.id == pi.container_id,
          where: m.movie_series_id == ^movie_series_id and not is_nil(wf.watch_dir),
          select: wf.watch_dir,
          limit: 1
        )
      )
    )
  end

  defp ok_or_skip(watch_dir) when is_binary(watch_dir), do: {:ok, watch_dir}
  defp ok_or_skip(_), do: {:skip, :no_watch_dir}
end
