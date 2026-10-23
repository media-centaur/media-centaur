defmodule MediaCentaur.Playback.SessionRecovery do
  @moduledoc """
  The shared half of recovering a session from an mpv that outlived it
  (ADR-023).

  Each transport finds its own orphaned mpvs and reads their properties:
  `Transport.Local.recover/1` scans the socket directory at boot,
  `Transport.Remote.recover/1` asks a player's mpv over its channel when
  the channel connects and no session holds the player. Each hands one
  mpv here as a **property reader**; `reattach_params/4` asks it for the
  position and the profile, resolves the host path to its entity, and
  answers with the params `Sessions.resume/2` reattaches with.
  `Sessions.recover/1` is the one door, keyed by player.

  The profile the session records under (ADR-078) is read back from mpv's
  `script-opts`, where `LaunchFlags` pinned it at launch under
  `LaunchFlags.profile_script_opt/0`. A session mpv reports without that
  option was started by the outgoing release: it is skipped rather than
  recovered under a guessed profile — mpv keeps playing, and its socket
  goes when mpv exits or on the next boot's dead-socket sweep.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Library.{EntityShape, TypeResolver}
  alias MediaCentaur.Playback.{Entry, LaunchFlags, PlayableFks}

  @typedoc "Reads one mpv property by name from whatever carries the IPC."
  @type property_reader :: (String.t() -> {:ok, term()} | {:error, term()})

  @doc """
  The params a session reattaches to this mpv with: the profile read
  through `reader` and the `Playback.Entry` for the file (`content_url`,
  the host path the mpv plays) at the position read the same way — with
  the entity's name and identity when the library knows the file, an
  unattributed entry when it does not. `:skip` when the mpv carries no
  profile or the reads fail; `who` names the mpv in the log line.
  """
  @spec reattach_params(property_reader(), String.t(), String.t(), String.t()) ::
          {:ok, %{profile_id: String.t(), entry: Entry.t(), reattach?: true}} | :skip
  def reattach_params(reader, entity_id, content_url, who) when is_binary(content_url) do
    with {:ok, position} <- reader.("time-pos"),
         {:ok, script_opts} <- reader.("script-opts"),
         {:ok, profile_id} <- session_profile(script_opts) do
      entry = build_entry(entity_id, content_url, position)
      {:ok, %{profile_id: profile_id, entry: entry, reattach?: true}}
    else
      :no_profile ->
        Log.info(
          :playback,
          "recovery: skipping session without a profile — mpv was started by the outgoing release (#{who})"
        )

        :skip

      {:error, reason} ->
        Log.info(:playback, "recovery: could not read the mpv for #{who} (#{inspect(reason)})")
        :skip
    end
  end

  @doc "The top-level entity of the library file at `path`, or nil for a file the library does not know."
  @spec entity_id_for_path(String.t()) :: String.t() | nil
  def entity_id_for_path(path) do
    case Library.Files.list_by_paths([path]) do
      [watched_file | _] -> Library.Files.top_level_entity_id(watched_file)
      [] -> nil
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

  defp build_entry(entity_id, content_url, position) do
    unattributed = %Entry{entity_id: entity_id, content_url: content_url, start_position: position}

    with [_watched_file | _] <- Library.Files.list_by_paths([content_url]),
         {:ok, entity} <- resolve_typed_entity(entity_id) do
      {season_number, episode_number, episode_name} = PlayableFks.context_by_url(entity, content_url)

      struct!(
        %{
          unattributed
          | entity_name: entity.name,
            season_number: season_number,
            episode_number: episode_number,
            episode_name: episode_name
        },
        PlayableFks.resolve(entity, content_url)
      )
    else
      # The file is not in the library, or its entity is gone, but mpv is
      # playing it: the session observes it without attributing progress.
      _unknown -> unattributed
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
