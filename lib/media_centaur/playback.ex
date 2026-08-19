defmodule MediaCentaur.Playback do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.Preferences, MediaCentaur.Settings],
    exports: [
      Iso639,
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
  Smart play for any UUID — resolves the target and starts playback.
  """
  def play(uuid) do
    Log.info(:playback, "play requested — #{Format.short_id(uuid)}")

    case Resolver.resolve(uuid) do
      {:ok, play_params} ->
        Sessions.play(play_params)

      {:error, reason} ->
        Log.info(:playback, "play failed — #{Format.short_id(uuid)}, #{reason}")
        {:error, reason}
    end
  end
end
