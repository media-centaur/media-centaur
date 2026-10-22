defmodule MediaCentaur.Playback.SessionRecovery do
  @moduledoc """
  Recovers playback sessions from mpvs that outlived their session (ADR-023).

  Two doors, one procedure. On boot, `recover_all/0` scans the socket
  directory for the host player's orphaned mpv processes
  (`media-centaur-{entity_id}.sock`) and probes each. When a remote
  player's channel connects and no session holds that player,
  `recover_player/1` asks the mpv on the device the same questions over
  the channel. Either way the mpv is asked for its `path`, `time-pos` and
  `script-opts`, the file is resolved to its entity, and the caller starts
  a session that reattaches instead of loading.

  The profile the session records under (ADR-078) is read back from mpv's
  `script-opts`, where `LaunchFlags` pinned it at launch under
  `LaunchFlags.profile_script_opt/0`. A session mpv reports without that
  option was started by the outgoing release: it is skipped rather than
  recovered under a guessed profile — mpv keeps playing, and its socket
  goes when mpv exits or on the next boot's dead-socket sweep.

  A remote mpv reports the media URL the host handed it; the channel's
  locators turn it back into the presence row, whose path names the
  watched file and, through it, the entity.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Library.{EntityShape, FilePresence, TypeResolver}
  alias MediaCentaur.Playback.{LaunchFlags, PlayableFks}
  alias MediaCentaur.Playback.Remote.{Channel, PlayerRegistry}

  @socket_prefix "media-centaur-"
  @socket_suffix ".sock"
  @connect_timeout_ms 500

  @typedoc "Reads one mpv property by name from whatever carries the IPC."
  @type property_reader :: (String.t() -> {:ok, term()} | {:error, term()})

  @doc """
  Scans the socket directory for orphaned mpv sockets and returns a list of
  play_params maps for each live session found, each carrying its
  `profile_id` and `reattach?: true`. Dead socket files are cleaned up.
  """
  @spec recover_all() :: [map()]
  def recover_all do
    socket_dir = MediaCentaur.Settings.Config.get(:mpv_socket_dir)
    pattern = Path.join(socket_dir, "#{@socket_prefix}*#{@socket_suffix}")

    Enum.flat_map(Path.wildcard(pattern), fn socket_path ->
      entity_id = extract_entity_id(socket_path)

      case recover_from_socket(socket_path, entity_id) do
        {:ok, params} ->
          Log.info(:playback, "recovery: found live session for #{params[:entity_name] || entity_id}")
          [params]

        :skip ->
          []
      end
    end)
  end

  @doc """
  Asks the connected remote player what it is playing and resolves it to
  play_params (with `profile_id` and `reattach?: true`), or `:skip` when it
  plays nothing this install handed it, has no profile pinned, or has no
  channel. Runs in the caller's process, which must not be the channel's.
  """
  @spec recover_player(String.t()) :: {:ok, map()} | :skip
  def recover_player(player_id) do
    case PlayerRegistry.lookup(player_id) do
      nil ->
        :skip

      {channel, locators} ->
        reader = fn name ->
          case Channel.request(channel, ["get_property", name]) do
            {:ok, %{"error" => "success", "data" => data}} -> {:ok, data}
            {:ok, %{"error" => error}} -> {:error, error}
            {:error, reason} -> {:error, reason}
          end
        end

        with {:ok, path} when is_binary(path) <- reader.("path"),
             presence_id when is_binary(presence_id) <- locators.identify.(path),
             {:ok, presence} <- FilePresence.fetch(presence_id),
             entity_id when is_binary(entity_id) <- entity_id_for_path(presence.file_path) do
          query_and_resolve(reader, entity_id, presence.file_path, "player #{player_id}")
        else
          _nothing_ours ->
            Log.info(:playback, "recovery: player #{player_id} plays nothing of ours")
            :skip
        end
    end
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
        reader = &get_property(socket, &1)

        result =
          case reader.("path") do
            {:ok, path} when is_binary(path) -> query_and_resolve(reader, entity_id, path, entity_id)
            _no_path -> :skip
          end

        :gen_tcp.close(socket)
        result

      {:error, reason} ->
        Log.info(:playback, "no mpv at socket — #{entity_id} (#{reason})")
        File.rm(socket_path)
        :skip
    end
  end

  # The shared half: position and profile from the mpv, the entity from the
  # host path, as play_params a session reattaches with.
  defp query_and_resolve(reader, entity_id, content_url, who) do
    with {:ok, position} <- reader.("time-pos"),
         {:ok, script_opts} <- reader.("script-opts"),
         {:ok, profile_id} <- session_profile(script_opts),
         {:ok, params} <- build_params(entity_id, content_url, position) do
      {:ok, Map.merge(params, %{profile_id: profile_id, reattach?: true})}
    else
      :no_profile ->
        Log.info(
          :playback,
          "recovery: skipping session without a profile — mpv was started by the outgoing release (#{who})"
        )

        :skip

      {:error, reason} ->
        Log.info(:playback, "recovery: could not resolve entity for #{who} (#{inspect(reason)})")
        :skip
    end
  end

  # One-release edge: mpv launched by the outgoing release has no profile
  # option, so the session is not recovered (see the moduledoc).
  defp session_profile(script_opts) when is_map(script_opts) do
    case Map.get(script_opts, LaunchFlags.profile_script_opt()) do
      nil -> :no_profile
      profile_id -> {:ok, profile_id}
    end
  end

  defp session_profile(_not_a_map), do: :no_profile

  defp entity_id_for_path(path) do
    case Library.Files.list_by_paths([path]) do
      [watched_file | _] -> Library.Files.top_level_entity_id(watched_file)
      [] -> nil
    end
  end

  defp get_property(socket, name) do
    command = Jason.encode!(%{"command" => ["get_property", name]}) <> "\n"

    case :gen_tcp.send(socket, command) do
      :ok ->
        case :gen_tcp.recv(socket, 0, @connect_timeout_ms) do
          {:ok, line} ->
            case Jason.decode(line) do
              {:ok, %{"error" => "success", "data" => data}} -> {:ok, data}
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
    case Library.Files.list_by_paths([content_url]) do
      [_watched_file | _] ->
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
          PlayableFks.context_by_url(entity, content_url)

        direct_fks = PlayableFks.resolve(entity, content_url)

        {:ok,
         Map.merge(
           %{
             entity_id: entity_id,
             entity_name: entity.name,
             season_number: season_number,
             episode_number: episode_number,
             episode_name: episode_name,
             content_url: content_url,
             start_position: position
           },
           direct_fks
         )}

      :not_found ->
        {:ok,
         %{
           entity_id: entity_id,
           content_url: content_url,
           start_position: position
         }}
    end
  end

  defp resolve_typed_entity(id) do
    case TypeResolver.resolve_container(id,
           standalone_movie: false,
           preload: Library.Containers.full_preloads_by_type()
         ) do
      {:ok, type, record} -> {:ok, EntityShape.to_entity_view(record, type)}
      :not_found -> :not_found
    end
  end
end
