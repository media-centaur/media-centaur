defmodule MediaCentarr.Playback.SessionRecovery do
  @moduledoc """
  Recovers playback sessions from orphaned mpv processes (ADR-023).

  On backend restart, mpv instances may still be running with entity-scoped
  sockets (`media-centarr-{entity_id}.sock`). This module scans the socket
  directory, probes each socket, queries mpv for the current file path and
  position, then resolves the entity so a new MpvSession can reconnect.
  """
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Library
  alias MediaCentarr.Library.{EntityShape, TypeResolver}

  @socket_prefix "media-centarr-"
  @socket_suffix ".sock"
  @connect_timeout_ms 500

  @doc """
  Scans the socket directory for orphaned mpv sockets and returns
  a list of play_params maps for each live session found.

  Dead socket files are cleaned up automatically.
  """
  @spec recover_all() :: [map()]
  def recover_all do
    socket_dir = MediaCentarr.Config.get(:mpv_socket_dir)
    pattern = Path.join(socket_dir, "#{@socket_prefix}*#{@socket_suffix}")

    Path.wildcard(pattern)
    |> Enum.flat_map(fn socket_path ->
      entity_id = extract_entity_id(socket_path)

      case recover_from_socket(socket_path, entity_id) do
        {:ok, params} ->
          Log.info(
            :playback,
            "recovery: found live session for #{params[:entity_name] || entity_id}"
          )

          [params]

        :skip ->
          []
      end
    end)
  end

  defp extract_entity_id(socket_path) do
    socket_path
    |> Path.basename()
    |> String.trim_leading(@socket_prefix)
    |> String.trim_trailing(@socket_suffix)
  end

  defp recover_from_socket(socket_path, entity_id) do
    socket_charlist = to_charlist(socket_path)

    case :gen_tcp.connect(
           {:local, socket_charlist},
           0,
           [:binary, packet: :line, active: false],
           @connect_timeout_ms
         ) do
      {:ok, socket} ->
        result = query_and_resolve(socket, entity_id)
        :gen_tcp.close(socket)
        result

      {:error, reason} ->
        Log.info(:playback, "no mpv at socket — #{entity_id} (#{reason})")
        File.rm(socket_path)
        :skip
    end
  end

  defp query_and_resolve(socket, entity_id) do
    with {:ok, path} <- get_property(socket, "path"),
         {:ok, position} <- get_property(socket, "time-pos"),
         {:ok, params} <- build_params(entity_id, path, position) do
      {:ok, params}
    else
      {:error, reason} ->
        Log.info(
          :playback,
          "recovery: could not resolve entity #{entity_id} (#{inspect(reason)})"
        )

        :skip
    end
  end

  defp get_property(socket, name) do
    command = Jason.encode!(%{"command" => ["get_property", name]}) <> "\n"

    case :gen_tcp.send(socket, command) do
      :ok ->
        case :gen_tcp.recv(socket, 0, 1000) do
          {:ok, data} ->
            case Jason.decode(String.trim(data)) do
              {:ok, %{"data" => value}} when not is_nil(value) -> {:ok, value}
              {:ok, %{"error" => "success", "data" => nil}} -> {:error, :no_data}
              {:ok, %{"error" => error}} -> {:error, error}
              _ -> {:error, :decode_failed}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_params(entity_id, content_url, position) when is_binary(content_url) do
    case Library.list_files_by_paths([content_url]) do
      {:ok, [_watched_file | _]} ->
        resolve_entity(entity_id, content_url, position)

      _ ->
        # File not in library but mpv is running — provide minimal params
        {:ok,
         %{
           entity_id: entity_id,
           content_url: content_url,
           start_position: position
         }}
    end
  end

  defp build_params(_entity_id, _path, _position), do: {:error, :invalid_path}

  defp resolve_entity(entity_id, content_url, position) do
    case resolve_typed_entity(entity_id) do
      {:ok, entity} ->
        {season_number, episode_number, episode_name} =
          resolve_episode_context(entity, content_url)

        direct_fks = resolve_direct_fks(entity, content_url)

        {:ok,
         %{
           entity_id: entity_id,
           entity_name: entity.name,
           season_number: season_number,
           episode_number: episode_number,
           episode_name: episode_name,
           content_url: content_url,
           start_position: position
         }
         |> Map.merge(direct_fks)}

      :not_found ->
        {:ok,
         %{
           entity_id: entity_id,
           content_url: content_url,
           start_position: position
         }}
    end
  end

  @with_associations_preloads [
    tv_series: Library.tv_series_full_preloads(),
    movie_series: Library.movie_series_full_preloads(),
    movie: Library.movie_full_preloads(),
    video_object: Library.video_object_full_preloads()
  ]

  defp resolve_typed_entity(id) do
    case TypeResolver.resolve(id,
           standalone_movie: false,
           preload: @with_associations_preloads
         ) do
      {:ok, type, record} -> {:ok, EntityShape.normalize(record, type)}
      :not_found -> :not_found
    end
  end

  defp resolve_direct_fks(%{type: :movie} = entity, _content_url),
    do: %{movie_id: entity.id}

  defp resolve_direct_fks(%{type: :video_object} = entity, _content_url),
    do: %{video_object_id: entity.id}

  defp resolve_direct_fks(%{type: :tv_series} = entity, content_url) do
    alias MediaCentarr.Playback.EpisodeList

    episode_id =
      Enum.find_value(entity.seasons || [], fn season ->
        Enum.find_value(season.episodes || [], fn episode ->
          if episode.content_url == content_url, do: episode.id
        end)
      end)

    %{episode_id: episode_id}
  end

  defp resolve_direct_fks(%{type: :movie_series} = entity, content_url) do
    alias MediaCentarr.Playback.MovieList

    movie_id =
      case MovieList.find_by_content_url(entity, content_url) do
        {_ordinal, id, _name} -> id
        nil -> nil
      end

    %{movie_id: movie_id}
  end

  defp resolve_direct_fks(_entity, _content_url), do: %{}

  defp resolve_episode_context(entity, content_url) do
    alias MediaCentarr.Playback.{EpisodeList, MovieList}

    case entity.type do
      :movie_series ->
        case MovieList.find_by_content_url(entity, content_url) do
          {ordinal, _movie_id, movie_name} -> {0, ordinal, movie_name}
          nil -> {nil, nil, nil}
        end

      :tv_series ->
        case EpisodeList.find_by_content_url(entity, content_url) do
          {season, episode} ->
            episode_name = EpisodeList.find_episode_name(entity, season, episode)
            {season, episode, episode_name}

          nil ->
            {nil, nil, nil}
        end

      _ ->
        {nil, nil, nil}
    end
  end
end
