defmodule MediaCentaurWeb.UserSocket do
  @moduledoc """
  Single WebSocket endpoint for the user-interface. Routes to library
  and playback channels. Unauthenticated (local-only v1).
  """
  use Phoenix.Socket

  channel "library", MediaCentaurWeb.LibraryChannel
  channel "playback", MediaCentaurWeb.PlaybackChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
