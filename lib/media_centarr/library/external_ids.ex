defmodule MediaCentarr.Library.ExternalIds do
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

  alias MediaCentarr.Library.{ExternalId, Movie, MovieSeries, TVSeries, VideoObject}
  alias MediaCentarr.Repo

  @type source :: :tmdb | :imdb | :tvdb | :tmdb_collection

  @type owner :: %Movie{} | %TVSeries{} | %MovieSeries{} | %VideoObject{}

  @type owner_type :: :movie | :tv_series | :movie_series | :video_object

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

  @doc """
  Finds the container that owns the given `(source, external_id)` pair,
  returning `{:ok, owner_type, record}` or `:not_found`.

  Tries each owner type in order — `tmdb` and `imdb` sources may legitimately
  attach to multiple container types (a movie and a TV series can share
  TMDB id 12345 — different namespaces in the TMDB API). The first match
  wins; callers needing type-specific lookup should call
  `MediaCentarr.Library.find_by_external_id/3` with the owner type.
  """
  @spec find_owner(source(), String.t()) :: {:ok, owner_type(), owner()} | :not_found
  def find_owner(source, external_id) when source in @sources and is_binary(external_id) do
    source_str = Atom.to_string(source)

    row =
      Repo.one(
        from(e in ExternalId,
          where: e.source == ^source_str and e.external_id == ^external_id,
          limit: 1
        )
      )

    case row do
      nil -> :not_found
      %ExternalId{owner_type: type, owner_id: id} -> {:ok, type, Repo.get!(schema_for(type), id)}
    end
  end

  defp owner_type(%Movie{}), do: :movie
  defp owner_type(%TVSeries{}), do: :tv_series
  defp owner_type(%MovieSeries{}), do: :movie_series
  defp owner_type(%VideoObject{}), do: :video_object

  defp schema_for(:movie), do: Movie
  defp schema_for(:tv_series), do: TVSeries
  defp schema_for(:movie_series), do: MovieSeries
  defp schema_for(:video_object), do: VideoObject
end
