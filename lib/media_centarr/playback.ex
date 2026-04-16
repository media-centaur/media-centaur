defmodule MediaCentarr.Playback do
  @moduledoc """
  Public facade for the playback context — subscriptions and top-level queries.

  Implementation details (sessions, mpv, progress tracking) live in the
  `MediaCentarr.Playback.*` submodules.
  """

  alias MediaCentarr.Topics

  @doc "Subscribe the caller to playback state and progress events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.playback_events())
  end
end
