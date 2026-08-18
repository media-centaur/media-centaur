defmodule MediaCentaur.Library.ExternalIds do
  @moduledoc """
  Canonical accessors for external identifiers across containers.

  Library Schema v2 Phase 1 Task 6 made `Library.ExternalId` the sole
  source of truth for TMDB / IMDB / TVDB ids on every container
  (`Movie`, `TVSeries`, `MovieSeries`, `VideoObject`). The previous
  scheme — `tmdb_id` / `imdb_id` columns on each container row — has
  been dropped.

  Library Schema v2 Phase 2 Task F collapsed the per-type owner FKs
  (`movie_id`, `tv_series_id`, `movie_series_id`, `video_object_id`)
  into a single `(owner_type, owner_id)` discriminator pair on the
  `ExternalId` row. This module hides that detail so callers continue
  to think in terms of container structs.

  Reads always go through a preloaded `:external_ids` association
  (`get/2`); writes always go through `put/3`. The helper resolves the
  owner type/id from the parent's struct module so callers don't repeat
  the type-dispatch.

  ## Sources

  | Atom              | Stored as          | Used for            |
  |-------------------|--------------------|---------------------|
  | `:tmdb`           | `"tmdb"`           | Movie, TVSeries, VideoObject TMDB ids |
  | `:imdb`           | `"imdb"`           | Movie, TVSeries IMDB ids |
  | `:tvdb`           | `"tvdb"`           | TVSeries TVDB ids   |
  | `:tmdb_collection`| `"tmdb_collection"`| MovieSeries (TMDB collection) ids |
  """

  import Ecto.Query

  alias MediaCentaur.Library.{
    Containers,
    Episode,
    ExternalId,
    Movie,
    MovieSeries,
    OwnerRef,
    PlayableItem,
    Season,
    TVSeries,
    VideoObject,
    WatchedFile
  }

  alias MediaCentaur.Repo

  @type source :: :tmdb | :imdb | :tvdb | :tmdb_collection

  @type owner :: %Movie{} | %TVSeries{} | %MovieSeries{} | %VideoObject{}

  @sources ~w(tmdb imdb tvdb tmdb_collection)a

  @doc """
  Inserts an `ExternalId` row pointing the given source/external_id pair at
  the given container record. Idempotent — returns the existing row on
  conflict (same `(source, external_id, owner_type, owner_id)`) without
  raising.

  Passing `nil` for the external_id is a no-op (`:ok`) — call sites can
  unconditionally forward optional ids without a guard.
  """
  @spec put(source(), owner(), String.t() | nil) :: {:ok, ExternalId.t()} | :ok | {:error, term()}
  def put(_source, _container, nil), do: :ok

  def put(source, container, external_id) when source in @sources and is_binary(external_id) do
    owner_type = owner_type(container)
    source_str = Atom.to_string(source)

    case Repo.one(
           from(e in ExternalId,
             where:
               e.source == ^source_str and e.external_id == ^external_id and
                 e.owner_type == ^owner_type and e.owner_id == ^container.id,
             limit: 1
           )
         ) do
      %ExternalId{} = existing ->
        {:ok, existing}

      nil ->
        %{
          source: source_str,
          external_id: external_id,
          owner_type: owner_type,
          owner_id: container.id
        }
        |> ExternalId.create_changeset()
        |> Repo.insert()
    end
  end

  @doc """
  Returns the external_id string for the given source from a container
  record whose `:external_ids` association has been preloaded, or `nil`
  if no matching row exists.

  Crashes if `:external_ids` is not preloaded — callers must preload
  explicitly so the access pattern stays explicit.
  """
  @spec get(owner(), source()) :: String.t() | nil
  def get(%{external_ids: ids}, source) when source in @sources and is_list(ids) do
    source_str = Atom.to_string(source)

    Enum.find_value(ids, fn
      %{source: ^source_str, external_id: value} -> value
      _ -> nil
    end)
  end

  def create(attrs) do
    Repo.insert(ExternalId.create_changeset(OwnerRef.normalise(attrs, :external_id)))
  end

  def create!(attrs), do: Repo.bang!(create(attrs))

  @doc """
  Returns the container of the given type that owns the given TMDB id
  (via `library_external_ids`), or `nil`.

  Library Schema v2 Phase 2 Task F collapsed the per-type FKs on
  `ExternalId` into a single `(owner_type, owner_id)` discriminator
  pair. This helper joins on the discriminator to fetch the typed
  container in a single query.

  Pass `:tmdb_collection` for MovieSeries; everything else uses
  `:tmdb`.
  """
  @spec find_by_external_id(Containers.t(), String.t()) :: owner() | nil
  def find_by_external_id(owner_type, external_id) when is_atom(owner_type) and is_binary(external_id) do
    source = if owner_type == :movie_series, do: "tmdb_collection", else: "tmdb"
    schema = schema_for_owner_type(owner_type)

    Repo.one(
      from(r in schema,
        join: e in ExternalId,
        on: e.owner_id == r.id and e.owner_type == ^owner_type,
        where: e.source == ^source and e.external_id == ^external_id,
        limit: 1
      )
    )
  end

  defp schema_for_owner_type(:movie), do: Movie
  defp schema_for_owner_type(:tv_series), do: TVSeries
  defp schema_for_owner_type(:movie_series), do: MovieSeries
  defp schema_for_owner_type(:video_object), do: VideoObject

  @doc """
  Returns `{:ok, file_path}` if the library has a movie with this TMDB
  id whose file has been linked (a `WatchedFile` exists for the movie's
  `PlayableItem`), otherwise `:not_found`. Used by
  `Acquisition.Pursuits.LibraryReconciler` as the safety-net check
  against the PubSub-driven completion path.

  After Library Schema v2 Phase 2 Task I the on-disk path lives on
  `library_watched_files.file_path` via `PlayableItem`; this query
  walks `Movie → PlayableItem → WatchedFile` rather than reading a
  former `content_url` column on Movie.
  """
  @spec find_present_movie(String.t()) :: {:ok, String.t()} | :not_found
  def find_present_movie(tmdb_id) when is_binary(tmdb_id) do
    case Repo.one(
           from(m in Movie,
             join: e in ExternalId,
             on: e.owner_id == m.id and e.owner_type == :movie,
             join: pi in PlayableItem,
             on: pi.container_id == m.id and pi.container_type == :movie,
             join: w in WatchedFile,
             on: w.playable_item_id == pi.id,
             where: e.source == "tmdb" and e.external_id == ^tmdb_id,
             select: w.file_path,
             limit: 1
           )
         ) do
      nil -> :not_found
      url -> {:ok, url}
    end
  end

  @doc """
  Returns `{:ok, file_path}` if the library has an episode for the
  given `(tmdb_id, season_number, episode_number)` tuple whose file has
  been linked, otherwise `:not_found`. Joins through
  `TVSeries → Season → Episode → PlayableItem → WatchedFile` in a
  single query.
  """
  @spec find_present_episode(String.t(), integer(), integer()) ::
          {:ok, String.t()} | :not_found
  def find_present_episode(tmdb_id, season_number, episode_number)
      when is_binary(tmdb_id) and is_integer(season_number) and is_integer(episode_number) do
    case Repo.one(
           from(e in Episode,
             join: s in Season,
             on: s.id == e.season_id,
             join: t in TVSeries,
             on: t.id == s.tv_series_id,
             join: ext in ExternalId,
             on: ext.owner_id == t.id and ext.owner_type == :tv_series,
             join: pi in PlayableItem,
             on: pi.container_id == e.id and pi.container_type == :episode,
             join: w in WatchedFile,
             on: w.playable_item_id == pi.id,
             where:
               ext.source == "tmdb" and ext.external_id == ^tmdb_id and
                 s.season_number == ^season_number and
                 e.episode_number == ^episode_number,
             select: w.file_path,
             limit: 1
           )
         ) do
      nil -> :not_found
      url -> {:ok, url}
    end
  end

  @doc """
  Returns the set of `{season_number, episode_number}` pairs for a TV
  series whose episode has a linked file on disk — the "present-set" used
  by reconciliation to mark which canonical spine nodes are already filled.
  """
  @spec present_episode_keys(Ecto.UUID.t()) :: MapSet.t({integer(), integer()})
  def present_episode_keys(tv_series_id) when is_binary(tv_series_id) do
    from(e in Episode,
      join: s in Season,
      on: s.id == e.season_id,
      join: pi in PlayableItem,
      on: pi.container_id == e.id and pi.container_type == :episode,
      join: w in WatchedFile,
      on: w.playable_item_id == pi.id,
      where: s.tv_series_id == ^tv_series_id,
      distinct: true,
      select: {s.season_number, e.episode_number}
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Returns every on-disk file path currently linked to a `PlayableItem`
  (i.e. present in the library).

  Used by `Acquisition.Pursuits.LibraryReconciler` to satisfy
  prowlarr-query pursuits, which carry no TMDB id to match on — the only
  binding back to the library is the downloaded file's name, so the
  reconciler matches the pursuit's release title against these basenames.
  """
  @spec list_present_file_paths() :: [String.t()]
  def list_present_file_paths do
    Repo.all(from(w in WatchedFile, select: w.file_path))
  end

  @doc """
  Returns `{tv_series_id, tmdb_id}` pairs for TV series in the given list
  that have a TMDB ExternalId row.
  """
  def tmdb_ids_for_tv_series(tv_series_ids) when is_list(tv_series_ids) do
    Repo.all(
      from(t in TVSeries,
        join: e in ExternalId,
        on: e.owner_id == t.id and e.owner_type == :tv_series,
        where: t.id in ^tv_series_ids and e.source == "tmdb",
        select: {t.id, e.external_id}
      )
    )
  end

  @doc """
  Returns `{movie_id, tmdb_id}` pairs for movies in the given list that
  have a TMDB ExternalId row. Mirror of `tmdb_ids_for_tv_series/1` —
  release tracking uses this to detect when a tracked movie has just
  landed in the library so it can close out the tracking item.
  """
  def tmdb_ids_for_movies(movie_ids) when is_list(movie_ids) do
    Repo.all(
      from(m in Movie,
        join: e in ExternalId,
        on: e.owner_id == m.id and e.owner_type == :movie,
        where: m.id in ^movie_ids and e.source == "tmdb",
        select: {m.id, e.external_id}
      )
    )
  end

  @doc """
  Bulk "does the library know this TMDB title" — maps each
  `{tmdb_id, media_type}` ref to the owning container's id; refs the
  library has no container for are absent from the result.

  Semantics: *container exists* — deliberately looser than
  `find_present_movie/1`'s file-linked check. Detail pages render
  containers regardless of files, so this is the right authority for
  "link to it" decorations (watchlist, search rows).
  """
  @spec tmdb_owners([{integer(), :movie | :tv_series}]) ::
          %{{integer(), :movie | :tv_series} => Ecto.UUID.t()}
  def tmdb_owners([]), do: %{}

  def tmdb_owners(refs) when is_list(refs) do
    ids = refs |> Enum.map(fn {tmdb_id, _type} -> to_string(tmdb_id) end) |> Enum.uniq()

    lookup =
      from(e in ExternalId,
        where: e.source == "tmdb" and e.owner_type in [:movie, :tv_series] and e.external_id in ^ids,
        select: {e.external_id, e.owner_type, e.owner_id}
      )
      |> Repo.all()
      |> Map.new(fn {external_id, owner_type, owner_id} -> {{external_id, owner_type}, owner_id} end)

    refs
    |> Enum.flat_map(fn {tmdb_id, media_type} = ref ->
      case Map.get(lookup, {to_string(tmdb_id), media_type}) do
        nil -> []
        owner_id -> [{ref, owner_id}]
      end
    end)
    |> Map.new()
  end

  @doc """
  Returns every entity in the library that has a TMDB ExternalId,
  tagged with its type. Used by ReleaseTracking to scan for tracking
  candidates.

  Each row is `%{source: String.t(), external_id: String.t(),
  owner_type: atom(), owner_id: Ecto.UUID.t()}`. The `:source` is
  `"tmdb"` for movies / TV / video objects and `"tmdb_collection"` for
  movie series; `:owner_type` is the canonical container type atom.

  Standalone movies (no `movie_series_id`) are surfaced; movies that
  belong to a movie_series are skipped — release tracking handles them
  through the collection.
  """
  def list_tmdb_entities do
    tv_and_movie_series =
      Repo.all(
        from(e in ExternalId,
          where:
            (e.owner_type == :tv_series and e.source == "tmdb") or
              (e.owner_type == :movie_series and e.source == "tmdb_collection"),
          select: %{
            source: e.source,
            external_id: e.external_id,
            owner_type: e.owner_type,
            owner_id: e.owner_id
          }
        )
      )

    standalone_movies =
      Repo.all(
        from(m in Movie,
          join: e in ExternalId,
          on: e.owner_id == m.id and e.owner_type == :movie,
          where: e.source == "tmdb" and is_nil(m.movie_series_id),
          select: %{
            source: e.source,
            external_id: e.external_id,
            owner_type: e.owner_type,
            owner_id: e.owner_id
          }
        )
      )

    tv_and_movie_series ++ standalone_movies
  end

  defp owner_type(%Movie{}), do: :movie
  defp owner_type(%TVSeries{}), do: :tv_series
  defp owner_type(%MovieSeries{}), do: :movie_series
  defp owner_type(%VideoObject{}), do: :video_object
end
