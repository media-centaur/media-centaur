defmodule MediaCentarr.Playback do
  use Boundary,
    deps: [MediaCentarr.Library],
    exports: [Sessions, ProgressBroadcaster, ResumeTarget]

  @moduledoc """
  Public facade for the playback context — subscriptions and top-level queries.

  Implementation details (sessions, mpv, progress tracking) live in the
  `MediaCentarr.Playback.*` submodules.
  """

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Format
  alias MediaCentarr.Playback.{Resolver, Sessions}
  alias MediaCentarr.Topics

  @doc "Subscribe the caller to playback state and progress events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.playback_events())
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
