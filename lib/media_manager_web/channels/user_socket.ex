defmodule MediaManagerWeb.UserSocket do
  use Phoenix.Socket

  channel "library", MediaManagerWeb.LibraryChannel
  channel "playback", MediaManagerWeb.PlaybackChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
