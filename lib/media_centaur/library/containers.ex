defmodule MediaCentaur.Library.Containers do
  @moduledoc """
  Records and lifecycle for the four library container types —
  `TVSeries`, `MovieSeries`, `Movie`, `VideoObject`.

  A *container* is a top-level addressable library entity: the thing a
  user browses to, that carries artwork, external ids, and extras. Two
  of the four (`Movie`, `VideoObject`) are also playable *leaves* and so
  carry a virtual `:content_url`; `TVSeries` and `MovieSeries` hold
  their playable leaves beneath them (`seasons → episodes`, `movies`).

  This module owns the answer to *what a container is* — `types/0` is
  the canonical list, and `ExternalId` and `TypeResolver` defer to it
  rather than each keeping their own copy.

  Operations are dispatched on an explicit type atom
  (`fetch(:tv_series, id)`) rather than baked into per-type function
  names. The four types previously carried a byte-identical eight-
  function CRUD surface each; the type is data, so it belongs in an
  argument.

  Reads that return a leaf, or a container holding preloaded leaves,
  run through `Library.ContentUrls.populate/1` so the virtual
  `:content_url` is materialised before the struct escapes.
  """

  import Ecto.Query

  alias MediaCentaur.Library.{
    ContentUrls,
    ExternalId,
    ExternalIds,
    Movie,
    MovieSeries,
    PlayableItem,
    TVSeries,
    VideoObject,
    WatchedFile,
    Writes
  }

  alias MediaCentaur.Repo

  @types [:tv_series, :movie_series, :movie, :video_object]

  # The two container types that are *also* playable leaves — they carry
  # the virtual `:content_url` and so need the file chain preloaded even
  # on a plain fetch. TVSeries/MovieSeries have no content_url of their
  # own; theirs lives on the leaves beneath them.
  @leaf_types [:movie, :video_object]

  @type t :: :tv_series | :movie_series | :movie | :video_object

  # Leaf preload chain for materialising the virtual `content_url` field
  # (Library Schema v2 Phase 2 Task I). Owned by ContentUrls — the module
  # that consumes it — so the two can't drift apart.
  @leaf_file_path_preload ContentUrls.required_preload()

  @tv_series_full_preloads [
    :images,
    :external_ids,
    :extras,
    :watched_files,
    seasons: [:extras, episodes: [:images, :watch_progress] ++ @leaf_file_path_preload]
  ]

  @movie_series_full_preloads [
    :images,
    :external_ids,
    :extras,
    :watched_files,
    movies: [:images, :watch_progress] ++ @leaf_file_path_preload
  ]

  @movie_full_preloads [
    :images,
    :external_ids,
    :extras,
    :watched_files,
    :watch_progress,
    {:playable_items, :watched_files}
  ]

  @video_object_full_preloads [
    :images,
    :external_ids,
    :watched_files,
    :watch_progress,
    {:playable_items, :watched_files}
  ]

  @doc "The canonical list of container types."
  @spec types() :: [t()]
  def types, do: @types

  @doc "The Ecto schema backing `type`."
  @spec schema(t()) :: module()
  def schema(:tv_series), do: TVSeries
  def schema(:movie_series), do: MovieSeries
  def schema(:movie), do: Movie
  def schema(:video_object), do: VideoObject

  @doc "The full association preload list for `type`."
  @spec full_preloads(t()) :: keyword()
  def full_preloads(:tv_series), do: @tv_series_full_preloads
  def full_preloads(:movie_series), do: @movie_series_full_preloads
  def full_preloads(:movie), do: @movie_full_preloads
  def full_preloads(:video_object), do: @video_object_full_preloads

  @doc """
  Returns a `[type: preloads]` keyword list covering all four container
  types. Used by `TypeResolver.resolve_container/2` and other multi-type
  lookups that preload across all four tables in one call.
  """
  @spec full_preloads_by_type() :: keyword()
  def full_preloads_by_type, do: Enum.map(@types, &{&1, full_preloads(&1)})

  @doc "Every record of `type`."
  @spec list(t()) :: [Ecto.Schema.t()]
  def list(type) when type in @types, do: Repo.all(schema(type))

  @doc """
  Fetches a container by id, materialising `:content_url` for the leaf
  types.
  """
  @spec fetch(t(), Ecto.UUID.t()) :: {:ok, Ecto.Schema.t()} | {:error, :not_found}
  def fetch(type, id) when type in @types do
    case Repo.get(schema(type), id) do
      nil -> {:error, :not_found}
      record -> {:ok, materialise_leaf(type, record)}
    end
  end

  @doc "Fetches a container with its full association graph preloaded."
  @spec fetch_with_associations(t(), Ecto.UUID.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, :not_found}
  def fetch_with_associations(type, id) when type in @types do
    case Repo.get(schema(type), id) do
      nil -> {:error, :not_found}
      record -> {:ok, preload_full(type, record)}
    end
  end

  @doc "As `fetch_with_associations/2`, raising when the id is absent."
  @spec get_with_associations!(t(), Ecto.UUID.t()) :: Ecto.Schema.t()
  def get_with_associations!(type, id) when type in @types do
    preload_full(type, Repo.get!(schema(type), id))
  end

  @doc "Inserts a container of `type` from `attrs`."
  @spec create(t(), map()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def create(type, attrs) when type in @types do
    Repo.insert(schema(type).create_changeset(attrs))
  end

  @doc "As `create/2`, raising on a rejected changeset."
  @spec create!(t(), map()) :: Ecto.Schema.t()
  def create!(type, attrs) when type in @types, do: Repo.bang!(create(type, attrs))

  @doc """
  Updates a container from its struct.

  `Movie` has no `update_changeset` — a Movie's mutable metadata is
  written through the ingestion pipeline, not edited in place — so it
  has no clause here.
  """
  @spec update(Ecto.Schema.t(), map()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def update(%TVSeries{} = record, attrs), do: Repo.update(TVSeries.update_changeset(record, attrs))

  def update(%MovieSeries{} = record, attrs),
    do: Repo.update(MovieSeries.update_changeset(record, attrs))

  def update(%VideoObject{} = record, attrs),
    do: Repo.update(VideoObject.update_changeset(record, attrs))

  @doc "Deletes a container record."
  @spec destroy(Ecto.Schema.t()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def destroy(record), do: Repo.delete(record)

  @doc "As `destroy/1`, raising on failure and returning `:ok`."
  @spec destroy!(Ecto.Schema.t()) :: :ok
  def destroy!(record), do: Writes.destroy!(record)

  @doc """
  Finds the child movie of a `MovieSeries` whose TMDB ExternalId matches
  the supplied `:tmdb_id`, or creates one. The TMDB id is written as a
  separate ExternalId row on success — the Movie row itself no longer
  carries the id column.

  Used by `Library.Inbound` when ingesting a collection event with a
  child-movie payload.
  """
  @spec find_or_create_movie_for_series(map()) ::
          {:ok, Movie.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_movie_for_series(attrs) do
    movie_series_id = Writes.attr(attrs, :movie_series_id)
    tmdb_id = Writes.attr(attrs, :tmdb_id)
    imdb_id = Writes.attr(attrs, :imdb_id)

    case find_child_movie_by_tmdb_id(movie_series_id, tmdb_id) do
      %Movie{} = movie ->
        {:ok, movie}

      nil ->
        attrs_without_id = Map.drop(attrs, [:tmdb_id, "tmdb_id", :imdb_id, "imdb_id"])

        with {:ok, movie} <- create(:movie, attrs_without_id),
             {:ok, _} <- maybe_put_external_id(movie, :tmdb, tmdb_id),
             {:ok, _} <- maybe_put_external_id(movie, :imdb, imdb_id) do
          {:ok, movie}
        end
    end
  end

  @doc """
  The child movies of a collection, with `:content_url` materialised.
  Extra preloads may be passed as `load:`.
  """
  @spec list_child_movies(Ecto.UUID.t(), keyword()) :: [Movie.t()]
  def list_child_movies(movie_series_id, opts \\ []) do
    preloads = List.flatten([ContentUrls.required_preload() | Keyword.get(opts, :load, [])])

    from(m in Movie, where: m.movie_series_id == ^movie_series_id)
    |> Repo.all()
    |> Repo.preload(preloads)
    |> Enum.map(&ContentUrls.populate/1)
  end

  @doc """
  The child movie under `movie_series_id` linked to `file_path` via its
  `PlayableItem → WatchedFile` chain, or `nil`. The collection-child
  counterpart of `Library.Episodes.find_by_path/2`.
  """
  @spec find_child_movie_by_path(Ecto.UUID.t(), String.t()) :: Movie.t() | nil
  def find_child_movie_by_path(movie_series_id, file_path)
      when is_binary(movie_series_id) and is_binary(file_path) do
    Repo.one(
      from(m in Movie,
        join: pi in PlayableItem,
        on: pi.container_id == m.id and pi.container_type == :movie,
        join: w in WatchedFile,
        on: w.playable_item_id == pi.id,
        where: m.movie_series_id == ^movie_series_id and w.file_path == ^file_path,
        limit: 1
      )
    )
  end

  defp preload_full(type, record) when type in @types do
    record
    |> Repo.preload(full_preloads(type))
    |> ContentUrls.populate()
  end

  defp materialise_leaf(type, record) when type in @leaf_types do
    record
    |> Repo.preload(@leaf_file_path_preload)
    |> ContentUrls.populate()
  end

  defp materialise_leaf(_type, record), do: record

  defp find_child_movie_by_tmdb_id(_movie_series_id, nil), do: nil

  defp find_child_movie_by_tmdb_id(movie_series_id, tmdb_id)
       when is_binary(movie_series_id) and is_binary(tmdb_id) do
    Repo.one(
      from(m in Movie,
        join: e in ExternalId,
        on: e.owner_id == m.id and e.owner_type == :movie,
        where:
          m.movie_series_id == ^movie_series_id and
            e.source == "tmdb" and e.external_id == ^tmdb_id,
        limit: 1
      )
    )
  end

  defp maybe_put_external_id(_movie, _source, nil), do: {:ok, :no_id}

  defp maybe_put_external_id(movie, source, external_id) when is_binary(external_id) do
    ExternalIds.put(source, movie, external_id)
  end
end
