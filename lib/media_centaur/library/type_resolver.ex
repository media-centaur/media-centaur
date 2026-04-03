defmodule MediaCentaur.Library.TypeResolver do
  @moduledoc """
  Resolves a UUID to its type-specific record (TVSeries, MovieSeries, Movie, or VideoObject).

  Used across playback, cascade, and browser modules that need to find a record by ID
  without knowing its type. Each caller specifies its own preload depth via options.
  """

  alias MediaCentaur.{Library, Repo}

  @doc """
  Looks up the record by trying each type table in order:
  TVSeries, MovieSeries, standalone Movie, VideoObject.

  Returns `{:ok, type, record}` or `:not_found`.

  ## Options

    * `:standalone_movie` — when `true` (default), only matches movies without a
      `movie_series_id`. Set to `false` to match any movie.
    * `:preload` — a keyword list of preloads per type:
      - `:tv_series` — preloads for TVSeries
      - `:movie_series` — preloads for MovieSeries
      - `:movie` — preloads for Movie
      - `:video_object` — preloads for VideoObject

  ## Examples

      TypeResolver.resolve(uuid)
      TypeResolver.resolve(uuid, preload: [tv_series: [:images, seasons: [episodes: [:watch_progress]]]])
      TypeResolver.resolve(uuid, standalone_movie: false)
  """
  def resolve(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])
    standalone_only = Keyword.get(opts, :standalone_movie, true)

    cond do
      record = try_get(Library.get_tv_series(id), preloads[:tv_series]) ->
        {:ok, :tv_series, record}

      record = try_get(Library.get_movie_series(id), preloads[:movie_series]) ->
        {:ok, :movie_series, record}

      record = try_movie(id, preloads[:movie], standalone_only) ->
        {:ok, :movie, record}

      record = try_get(Library.get_video_object(id), preloads[:video_object]) ->
        {:ok, :video_object, record}

      true ->
        :not_found
    end
  end

  defp try_get({:ok, record}, preloads) when is_list(preloads), do: Repo.preload(record, preloads)
  defp try_get({:ok, record}, nil), do: record
  defp try_get(_, _), do: nil

  defp try_movie(id, preloads, standalone_only) do
    case Library.get_movie(id) do
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
