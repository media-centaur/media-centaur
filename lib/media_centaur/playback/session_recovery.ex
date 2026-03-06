defmodule MediaCentaur.Playback.SessionRecovery do
  @moduledoc """
  Recovers playback session params from an orphaned mpv process (ADR-023).

  On backend restart, mpv may still be running with the well-known socket.
  This module probes the socket, queries mpv for the current file path and
  position, then resolves the entity so a new MpvSession can reconnect.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library

  @well_known_socket_name "media-centaur-mpv.sock"
  @connect_timeout_ms 500

  @spec recover_params() :: {:ok, map()} | :skip
  def recover_params do
    socket_dir = MediaCentaur.Config.get(:mpv_socket_dir)
    socket_path = Path.join(socket_dir, @well_known_socket_name)

    if File.exists?(socket_path) do
      recover_from_socket(socket_path)
    else
      :skip
    end
  end

  defp recover_from_socket(socket_path) do
    socket_charlist = to_charlist(socket_path)

    case :gen_tcp.connect(
           {:local, socket_charlist},
           0,
           [:binary, packet: :line, active: false],
           @connect_timeout_ms
         ) do
      {:ok, socket} ->
        result = query_and_resolve(socket)
        :gen_tcp.close(socket)
        result

      {:error, reason} ->
        Log.info(:playback, "session recovery: no mpv at socket (#{reason})")
        File.rm(socket_path)
        :skip
    end
  end

  defp query_and_resolve(socket) do
    with {:ok, path} <- get_property(socket, "path"),
         {:ok, position} <- get_property(socket, "time-pos"),
         {:ok, params} <- resolve_entity_from_path(path, position) do
      {:ok, params}
    else
      {:error, reason} ->
        Log.info(:playback, "session recovery: could not resolve entity (#{inspect(reason)})")
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

  defp resolve_entity_from_path(content_url, position) when is_binary(content_url) do
    case Library.list_files_by_paths([content_url]) do
      {:ok, [watched_file | _]} ->
        build_params(watched_file.entity_id, content_url, position)

      _ ->
        {:error, :no_watched_file}
    end
  end

  defp resolve_entity_from_path(_path, _position), do: {:error, :invalid_path}

  defp build_params(entity_id, content_url, position) do
    case Library.get_entity_with_progress(entity_id) do
      {:ok, entity} ->
        {season_number, episode_number, episode_name} =
          resolve_episode_context(entity, content_url)

        {:ok,
         %{
           entity_id: entity_id,
           entity_name: entity.name,
           season_number: season_number,
           episode_number: episode_number,
           episode_name: episode_name,
           content_url: content_url,
           start_position: position
         }}

      {:error, _} ->
        {:ok,
         %{
           entity_id: entity_id,
           content_url: content_url,
           start_position: position
         }}
    end
  end

  defp resolve_episode_context(entity, content_url) do
    alias MediaCentaur.Playback.{EpisodeList, MovieList}

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
