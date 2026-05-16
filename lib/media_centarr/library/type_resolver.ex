defmodule MediaCentarr.Library.TypeResolver do
  @moduledoc """
  Resolves a UUID to either a `PlayableItem` (the canonical leaf — see
  `MediaCentarr.Library.PlayableItem`) or a container record (`TVSeries`,
  `MovieSeries`, `Movie`, `VideoObject`).

  Library Schema v2 Phase 2 split the historical "resolve any UUID" call
  into two explicit shapes so callers state the kind of UUID they hold:

    * `resolve_by_playable_item/2` — for UUIDs that identify a
      `PlayableItem` (e.g. WatchProgress / WatchedFile lookups via the FK
      column added in Phase 2 Task B/C). Returns `{:ok, container_type,
      playable_item, container}`.
    * `resolve_container/2` — for UUIDs that identify a container
      (e.g. detail-modal `?selected=` query params, EntityCascade
      destruction). Returns `{:ok, type, record}`.

  Callers that don't know the kind of UUID they hold should try
  `resolve_by_playable_item/2` first and fall back to `resolve_container/2`
  — but the smell is in the call site, not the resolver. Library Schema v2
  introduces PlayableItem as a separate identity precisely so callers
  *can* be explicit.
  """

  alias MediaCentarr.{Library, Repo}
  alias MediaCentarr.Library.PlayableItem

  @doc """
  Resolves a container UUID to its type-specific record by trying each
  type table in order: TVSeries, MovieSeries, standalone Movie, VideoObject.

  Returns `{:ok, type, record}` or `:not_found`.

  ## Options

    * `:standalone_movie` — when `true` (default), only matches movies
      without a `movie_series_id`. Set to `false` to match any movie.
    * `:preload` — a keyword list of preloads per type:
      - `:tv_series` — preloads for TVSeries
      - `:movie_series` — preloads for MovieSeries
      - `:movie` — preloads for Movie
      - `:video_object` — preloads for VideoObject

  ## Examples

      TypeResolver.resolve_container(uuid)
      TypeResolver.resolve_container(uuid, preload: [tv_series: [:images, seasons: [episodes: [:watch_progress]]]])
      TypeResolver.resolve_container(uuid, standalone_movie: false)
  """
  @spec resolve_container(Ecto.UUID.t(), keyword()) ::
          {:ok, :tv_series | :movie_series | :movie | :video_object, struct()} | :not_found
  def resolve_container(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])
    standalone_only = Keyword.get(opts, :standalone_movie, true)

    cond do
      record = try_get(Library.fetch_tv_series(id), preloads[:tv_series]) ->
        {:ok, :tv_series, record}

      record = try_get(Library.fetch_movie_series(id), preloads[:movie_series]) ->
        {:ok, :movie_series, record}

      record = try_movie(id, preloads[:movie], standalone_only) ->
        {:ok, :movie, record}

      record = try_get(Library.fetch_video_object(id), preloads[:video_object]) ->
        {:ok, :video_object, record}

      true ->
        :not_found
    end
  end

  @doc """
  Resolves a `PlayableItem` UUID to `{:ok, container_type, playable_item,
  container}`. The container is fetched from the type table named by
  `playable_item.container_type`.

  Returns `:not_found` when the PlayableItem doesn't exist, OR when it
  exists but its container row has been deleted (orphan — the
  discriminator FK has no DB-level enforcement, see `PlayableItem`
  moduledoc).

  ## Options

    * `:container_preload` — preloads to apply to the resolved container
      struct, regardless of its type. Example: `[:images, :external_ids]`.
  """
  @spec resolve_by_playable_item(Ecto.UUID.t(), keyword()) ::
          {:ok, PlayableItem.container_type(), PlayableItem.t(), struct()} | :not_found
  def resolve_by_playable_item(id, opts \\ []) do
    case Repo.get(PlayableItem, id) do
      nil ->
        :not_found

      %PlayableItem{container_type: type, container_id: container_id} = item ->
        case fetch_container(type, container_id, opts[:container_preload]) do
          {:ok, container} -> {:ok, type, item, container}
          :not_found -> :not_found
        end
    end
  end

  defp fetch_container(:movie, id, preloads), do: fetch_with_preload(Library.fetch_movie(id), preloads)

  defp fetch_container(:episode, id, preloads),
    do: fetch_with_preload(Library.fetch_episode(id), preloads)

  defp fetch_container(:video_object, id, preloads),
    do: fetch_with_preload(Library.fetch_video_object(id), preloads)

  defp fetch_with_preload({:ok, record}, nil), do: {:ok, record}
  defp fetch_with_preload({:ok, record}, preloads), do: {:ok, Repo.preload(record, preloads)}
  defp fetch_with_preload({:error, :not_found}, _), do: :not_found

  defp try_get({:ok, record}, preloads) when is_list(preloads), do: Repo.preload(record, preloads)
  defp try_get({:ok, record}, nil), do: record
  defp try_get(_, _), do: nil

  defp try_movie(id, preloads, standalone_only) do
    case Library.fetch_movie(id) do
      {:ok, %{movie_series_id: nil} = movie} ->
        apply_preloads(movie, preloads)

      {:ok, movie} when not standalone_only ->
        apply_preloads(movie, preloads)

      _ ->
        nil
    end
  end

  defp apply_preloads(record, preloads) when is_list(preloads), do: Repo.preload(record, preloads)
  defp apply_preloads(record, nil), do: record
end
