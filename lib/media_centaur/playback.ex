defmodule MediaCentaur.Playback do
  use Boundary,
    deps: [
      MediaCentaur.Library,
      MediaCentaur.Settings.Preferences,
      MediaCentaur.Settings,
      MediaCentaur.Subtitles
    ],
    exports: [
      Command,
      LanguagePolicy,
      ProgressBroadcaster,
      Remote.Channel,
      Remote.PlayerRegistry,
      ResumeTarget,
      SessionRegistry,
      Sessions,
      TrackResolver.Track,
      Viewing
    ]

  @moduledoc """
  Public facade for the playback context — subscriptions and top-level queries.

  Implementation details (sessions, mpv, progress tracking) live in the
  `MediaCentaur.Playback.*` submodules.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Playback.{Command, Resolver, SessionRecovery, Sessions}
  alias MediaCentaur.Topics

  @doc """
  A remote player's channel just connected and no session holds the player:
  ask the device what it plays and reattach a session to it
  (`SessionRecovery.recover_player/1`), off the channel's own process.
  """
  @spec recover_player(Ecto.UUID.t()) :: :ok
  def recover_player(player_id) when is_binary(player_id) do
    {:ok, _pid} =
      Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
        case SessionRecovery.recover_player(player_id) do
          {:ok, params} ->
            case Sessions.resume(params, player_id) do
              :ok ->
                Log.info(:playback, "recovered session on player #{Format.short_id(player_id)}")

              {:error, reason} ->
                Log.warning(:playback, "could not reattach to player: #{inspect(reason)}")
            end

          :skip ->
            :ok
        end
      end)

    :ok
  end

  @doc "Subscribe the caller to playback state and progress events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Topics.subscribe(Topics.playback_events())
  end

  @doc """
  Subscribe the caller to one player's viewing stream: `{:viewing, %Playback.Viewing{}}`
  on attach, on every discrete change and on position once a second, then
  `{:viewing_ended, %Playback.Events.ViewingEnded{}}` when the session ends.
  """
  @spec subscribe_viewing(player()) :: :ok | {:error, term()}
  def subscribe_viewing(player) do
    Topics.subscribe(Topics.playback_viewing(player))
  end

  @doc """
  Sends a reader's command (`Playback.Command`) to `player`'s viewing of
  `uuid`: pause, a seek, the prompt's action, a track. The session renders
  it and sends it to the player; a viewing that does not exist refuses it.
  """
  @spec command(player(), Ecto.UUID.t(), Command.t()) :: :ok | {:error, :no_session | :invalid_command}
  def command(player, uuid, command) do
    if Command.valid?(command),
      do: Sessions.command(player, uuid, command),
      else: {:error, :invalid_command}
  end

  @typedoc "Where a viewing shows: this computer's mpv, or a paired player by id (`Players.Player.id/0`)."
  @type player :: MediaCentaur.Players.Player.id()

  @doc """
  Starts playback of `uuid` for `profile_id`, the session's active profile
  (ADR-078), on `player`: `:host` for an mpv this computer spawns, or a
  paired player's id for the mpv on that device. The profile is captured
  here and held by the session for its life: a switch mid-film does not
  re-home the progress.
  """
  @spec play(Ecto.UUID.t(), Ecto.UUID.t(), player()) :: :ok | {:error, atom()}
  def play(profile_id, uuid, player) when is_binary(profile_id) and is_binary(uuid) do
    Log.info(
      :playback,
      "play requested — #{Format.short_id(uuid)} for #{Format.short_id(profile_id)} on #{inspect(player)}"
    )

    case Resolver.resolve(profile_id, uuid) do
      {:ok, play_params} ->
        Sessions.play(play_params, player)

      {:error, reason} ->
        Log.info(:playback, "play failed — #{Format.short_id(uuid)}, #{reason}")
        {:error, reason}
    end
  end
end
