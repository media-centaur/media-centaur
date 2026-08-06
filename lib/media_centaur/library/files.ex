defmodule MediaCentaur.Library.Files do
  @moduledoc """
  The library's file rows — the link between a path on disk and the
  thing in the library it belongs to.

  Two tables, because the library has two kinds of file-bearing thing:

    * `WatchedFile`, pointing at a `PlayableItem` (Movie / Episode /
      VideoObject).
    * `ExtraFile`, pointing at an `Extra` (featurette, deleted scene),
      which is not a `PlayableItem`.

  They are deliberately adjacent — the same "upsert a row for this path,
  stamping its `FilePresence` first" shape serves both, and
  `upsert_by_path/2` is now written once. The one real difference stays
  visible at the call site: linking a `WatchedFile` triggers a media-info
  probe, linking an `ExtraFile` does not. That duplication resolves when
  `Extra` becomes a `PlayableItem`, not before.

  This module also resolves a file back to the **top-level entity** the
  user navigated to — the Movie / TVSeries / VideoObject — by climbing
  `WatchedFile → PlayableItem → container`, with episodes climbing on
  through `Season → TVSeries`.
  """

  import Ecto.Query

  alias MediaCentaur.Library.{
    Episode,
    Extra,
    ExtraFile,
    FilePresence,
    MediaInfo,
    Movie,
    PlayableItem,
    Season,
    WatchedFile,
    Writes
  }

  alias MediaCentaur.Repo

  # ---- WatchedFile ---------------------------------------------------------

  @doc "Every `WatchedFile` row."
  @spec list_all() :: [WatchedFile.t()]
  def list_all, do: Repo.all(WatchedFile)

  @doc """
  Inserts (or re-points by `file_path`) a `WatchedFile` row, then probes
  the file for media info.

  The probe is best-effort — `MediaInfo.refresh/2` returns `:skipped`
  when ffprobe is unavailable or the file is unreadable, and a later
  sweep can always retry because the data is recomputable.
  """
  @spec link(map()) :: {:ok, WatchedFile.t()} | {:error, Ecto.Changeset.t()}
  def link(attrs) do
    result = upsert_by_path(WatchedFile, attrs)

    case result do
      {:ok, %WatchedFile{} = watched_file} ->
        MediaInfo.refresh(watched_file.file_presence_id, watched_file.file_path)

      _error ->
        :ok
    end

    result
  end

  @doc "Bang variant of `link/1` — raises on changeset error."
  @spec link!(map()) :: WatchedFile.t()
  def link!(attrs), do: Repo.bang!(link(attrs))

  @doc "Watched files at any of the given paths."
  @spec list_by_paths([String.t()]) :: [WatchedFile.t()]
  def list_by_paths(file_paths), do: Repo.all(from(w in WatchedFile, where: w.file_path in ^file_paths))

  @doc "Watched files under a media directory."
  @spec list_by_media_dir(String.t()) :: [WatchedFile.t()]
  def list_by_media_dir(media_dir),
    do: Repo.all(from(w in WatchedFile, where: w.media_dir == ^media_dir))

  @doc """
  Paths of already-imported files that live under `dir` — used to check
  whether a folder is safe to delete wholesale (it isn't, if anything
  other than the files being deleted also lives there).

  Filters in Elixir rather than a SQL `LIKE` so a literal `%` or `_` in a
  real path can't be misread as a wildcard.
  """
  @spec paths_under(String.t()) :: [String.t()]
  def paths_under(dir) do
    prefix = dir <> "/"

    from(w in WatchedFile, select: w.file_path)
    |> Repo.all()
    |> Enum.filter(&String.starts_with?(&1, prefix))
  end

  @doc """
  The on-disk path for a PlayableItem's currently-present file, or `nil`
  when it has no `WatchedFile`.

  `WatchedFile.file_path` is the sole source of truth for "the file on
  disk for this playable thing" since Library Schema v2 Phase 2 Task I
  dropped the `content_url` columns. Presence is structurally guaranteed
  by the FK on `file_presence_id` (cascade-delete from `FilePresence`).

  When a PlayableItem has multiple WatchedFiles — rare, only the
  multi-cut shape produces this — the earliest by insertion order wins.
  Callers needing every variant should query `WatchedFile` directly.
  """
  @spec playable_file_path(Ecto.UUID.t() | term()) :: String.t() | nil
  def playable_file_path(playable_item_id) when is_binary(playable_item_id) do
    Repo.one(
      from(w in WatchedFile,
        where: w.playable_item_id == ^playable_item_id,
        order_by: [asc: w.inserted_at],
        limit: 1,
        select: w.file_path
      )
    )
  end

  def playable_file_path(_), do: nil

  @doc """
  An Ecto subquery selecting `file_path` from every linked WatchedFile.

  Exposed so cross-context queries (Watcher's `rescan_unlinked`) can
  compose against linked-file state without reaching into the schema.
  """
  @spec linked_paths_subquery() :: Ecto.Query.t()
  def linked_paths_subquery, do: from(w in WatchedFile, select: w.file_path)

  @doc """
  Watched files belonging to a top-level entity, whichever container type
  owns them. Used when you hold an entity UUID but don't know its type
  table (e.g. `Inbound.handle_rematch/1`).

  Resolution walks through PlayableItem: Movie / VideoObject directly,
  Episode through its season's TVSeries, MovieSeries through its child
  Movies.
  """
  @spec list_by_entity_id(Ecto.UUID.t()) :: [WatchedFile.t()]
  def list_by_entity_id(entity_id) do
    movie_or_video =
      from(p in PlayableItem,
        where: p.container_type in [:movie, :video_object] and p.container_id == ^entity_id,
        select: p.id
      )

    episodes =
      from(p in PlayableItem,
        join: e in Episode,
        on: e.id == p.container_id,
        join: s in Season,
        on: s.id == e.season_id,
        where: p.container_type == :episode and s.tv_series_id == ^entity_id,
        select: p.id
      )

    movie_series_children =
      from(p in PlayableItem,
        join: m in Movie,
        on: m.id == p.container_id,
        where: p.container_type == :movie and m.movie_series_id == ^entity_id,
        select: p.id
      )

    Repo.all(
      from(w in WatchedFile,
        where:
          w.playable_item_id in subquery(movie_or_video) or
            w.playable_item_id in subquery(episodes) or
            w.playable_item_id in subquery(movie_series_children)
      )
    )
  end

  # ---- file → entity resolution --------------------------------------------

  @doc """
  Resolves a WatchedFile to the top-level entity the user navigated to —
  the Movie / TVSeries / VideoObject.

  Walks `WatchedFile → PlayableItem → container`; `:movie` and
  `:video_object` containers already *are* the top-level entity, while
  `:episode` climbs on through `Season → TVSeries`.

  Returns `nil` when the file is dangling (no PlayableItem) or its
  container has been deleted out from under it.
  """
  @spec top_level_entity_id(WatchedFile.t()) :: Ecto.UUID.t() | nil
  def top_level_entity_id(%WatchedFile{playable_item_id: nil}), do: nil

  def top_level_entity_id(%WatchedFile{playable_item_id: playable_item_id}) do
    case Repo.get(PlayableItem, playable_item_id) do
      nil ->
        nil

      %PlayableItem{container_type: type, container_id: container_id}
      when type in [:movie, :video_object] ->
        container_id

      %PlayableItem{container_type: :episode, container_id: episode_id} ->
        Repo.one(tv_series_id_for_episodes([episode_id]))
    end
  end

  @doc """
  Batched `top_level_entity_id/1` for a set of `FilePresence` ids — two
  queries regardless of how many presences are passed.
  """
  @spec top_level_entity_ids_for_presences([Ecto.UUID.t()]) :: [Ecto.UUID.t()]
  def top_level_entity_ids_for_presences(presence_ids) do
    containers =
      Repo.all(
        from(w in WatchedFile,
          join: p in PlayableItem,
          on: p.id == w.playable_item_id,
          where: w.file_presence_id in ^presence_ids,
          select: {p.container_type, p.container_id}
        )
      )

    {episode_ids, direct_ids} =
      Enum.reduce(containers, {[], []}, fn
        {:episode, id}, {episodes, direct} -> {[id | episodes], direct}
        {_type, id}, {episodes, direct} -> {episodes, [id | direct]}
      end)

    series_ids =
      if episode_ids == [] do
        []
      else
        Repo.all(tv_series_id_for_episodes(episode_ids))
      end

    Enum.uniq(direct_ids ++ series_ids)
  end

  # ---- ExtraFile -----------------------------------------------------------

  @doc """
  Inserts (or re-points by `file_path`) an `ExtraFile` row linking a
  bonus-feature path to an `Extra`. The `ExtraFile` counterpart of
  `link/1`, minus the media-info probe.
  """
  @spec create_extra(map()) :: {:ok, ExtraFile.t()} | {:error, Ecto.Changeset.t()}
  def create_extra(attrs), do: upsert_by_path(ExtraFile, attrs)

  @doc "Bang variant of `create_extra/1` — raises on changeset error."
  @spec create_extra!(map()) :: ExtraFile.t()
  def create_extra!(attrs), do: Repo.bang!(create_extra(attrs))

  @doc "Every `ExtraFile` row for an extra."
  @spec list_for_extra(Ecto.UUID.t()) :: [ExtraFile.t()]
  def list_for_extra(extra_id) when is_binary(extra_id),
    do: Repo.all(from(f in ExtraFile, where: f.extra_id == ^extra_id))

  @doc "Deletes an `ExtraFile` row."
  @spec destroy_extra(ExtraFile.t()) :: {:ok, ExtraFile.t()} | {:error, Ecto.Changeset.t()}
  def destroy_extra(extra_file), do: Repo.delete(extra_file)

  @doc """
  Backfills `ExtraFile` rows for extras imported before the ingest path
  wrote them — those carrying a `content_url`, lacking any `ExtraFile`,
  and with a resolvable `FilePresence` for the path (the source of
  `media_dir`).

  Network-free and idempotent; runs on boot so existing extras become
  "linked" and stop being re-emitted by `rescan_unlinked`.
  """
  @spec backfill_extras() :: %{created: non_neg_integer()}
  def backfill_extras do
    extras =
      Repo.all(
        from(e in Extra,
          left_join: f in ExtraFile,
          on: f.extra_id == e.id,
          where: not is_nil(e.content_url) and is_nil(f.id),
          select: e
        )
      )

    # Resolve every media_dir in one query rather than a Repo.get_by per
    # extra — this runs on boot over the whole unlinked-extra set.
    content_urls = Enum.map(extras, & &1.content_url)

    media_dirs_by_path =
      from(f in FilePresence,
        where: f.file_path in ^content_urls,
        select: {f.file_path, f.media_dir}
      )
      |> Repo.all()
      |> Map.new()

    created =
      Enum.reduce(extras, 0, fn extra, count ->
        with media_dir when is_binary(media_dir) <- Map.get(media_dirs_by_path, extra.content_url),
             {:ok, _} <-
               create_extra(%{
                 file_path: extra.content_url,
                 media_dir: media_dir,
                 extra_id: extra.id
               }) do
          count + 1
        else
          # No FilePresence (can't resolve media_dir), or the row was
          # created concurrently by a rescan re-ingest — either way,
          # leave it.
          _ -> count
        end
      end)

    %{created: created}
  end

  # ---- internals -----------------------------------------------------------

  # Upsert a file row keyed on its path, stamping FilePresence first so
  # the row's NOT-NULL `file_presence_id` is satisfiable. Shared by
  # WatchedFile and ExtraFile, which differ only in schema.
  defp upsert_by_path(schema, attrs) do
    file_path = Writes.attr(attrs, :file_path)
    media_dir = Writes.attr(attrs, :media_dir)
    attrs = ensure_file_presence_id(attrs, file_path, media_dir)

    case Repo.get_by(schema, file_path: file_path) do
      nil -> Repo.insert(schema.create_changeset(attrs))
      existing -> Repo.update(schema.update_changeset(existing, attrs))
    end
  end

  # Stamps FilePresence for the path so the upcoming insert satisfies its
  # NOT-NULL changeset validation and FK constraint. Falls through
  # unchanged when either input is missing or blank, so the downstream
  # changeset surfaces the missing-field error rather than crashing
  # inside `FilePresence.stamp/3`.
  defp ensure_file_presence_id(attrs, file_path, media_dir)
       when is_binary(file_path) and byte_size(file_path) > 0 and is_binary(media_dir) and
              byte_size(media_dir) > 0 do
    presence = FilePresence.stamp(file_path, media_dir)
    Map.put(attrs, :file_presence_id, presence.id)
  end

  defp ensure_file_presence_id(attrs, _file_path, _media_dir), do: attrs

  defp tv_series_id_for_episodes(episode_ids) do
    from(e in Episode,
      join: s in Season,
      on: s.id == e.season_id,
      where: e.id in ^episode_ids,
      select: s.tv_series_id
    )
  end
end
