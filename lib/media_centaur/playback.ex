defmodule MediaCentaur.Playback do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.Settings.Preferences, MediaCentaur.Settings],
    exports: [
      LanguagePolicy,
      ProgressBroadcaster,
      ResumeTarget,
      SessionRegistry,
      Sessions
    ]

  @moduledoc """
  Public facade for the playback context — subscriptions and top-level queries.

  Implementation details (sessions, mpv, progress tracking) live in the
  `MediaCentaur.Playback.*` submodules.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Playback.{Resolver, Sessions}
  alias MediaCentaur.Topics

  @doc "Subscribe the caller to playback state and progress events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Topics.subscribe(Topics.playback_events())
  end

  @doc """
  Starts playback of `uuid` for `profile_id`, the session's active profile
  (ADR-078). The profile is captured here and held by the session for its
  life: a switch mid-film does not re-home the progress.
  """
  @spec play(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def play(profile_id, uuid) when is_binary(profile_id) and is_binary(uuid) do
    Log.info(:playback, "play requested — #{Format.short_id(uuid)} for #{Format.short_id(profile_id)}")

    case Resolver.resolve(profile_id, uuid) do
      {:ok, play_params} ->
        Sessions.play(play_params)

      {:error, reason} ->
        Log.info(:playback, "play failed — #{Format.short_id(uuid)}, #{reason}")
        {:error, reason}
    end
  end
end
