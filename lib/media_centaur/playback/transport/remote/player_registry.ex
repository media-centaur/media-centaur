defmodule MediaCentaur.Playback.Transport.Remote.PlayerRegistry do
  @moduledoc """
  The connected remote players: one entry per player id, held by the
  process that owns that player's channel (the WebSocket handler), with
  the player's **media URLs** as the entry's value — the functions the
  web layer captured at connect that compose a presence's media URL, a
  sidecar's URL beside it, and read a presence id back out of a media
  URL. A transport reads them here, so
  Playback never names a web module and never composes a URL itself.

  An entry dies with its process; a reconnecting player's new channel
  evicts the old one first (`Channel.replace/1`).
  """

  @typedoc """
  How a channel's player reaches the host's files: `for_file` composes
  the media URL of a presence, `for_sidecar` the URL of one sidecar beside
  that presence's file (by its basename, under the same token), and
  `presence_id` reads a presence id back out of a media URL — nil for a
  sidecar URL or anything else.
  """
  @type media_urls :: %{
          for_file: (String.t() -> String.t()),
          for_sidecar: (String.t(), String.t() -> String.t()),
          presence_id: (String.t() -> String.t() | nil)
        }

  @doc "Registers the calling process as `player_id`'s channel."
  @spec register(String.t(), media_urls()) :: :ok | {:error, {:already_registered, pid()}}
  def register(player_id, media_urls) do
    case Registry.register(__MODULE__, player_id, media_urls) do
      {:ok, _owner} -> :ok
      {:error, {:already_registered, pid}} -> {:error, {:already_registered, pid}}
    end
  end

  @doc "The channel process and media URLs for a connected player, or nil."
  @spec lookup(String.t()) :: {pid(), media_urls()} | nil
  def lookup(player_id) do
    case Registry.lookup(__MODULE__, player_id) do
      [{pid, media_urls}] -> {pid, media_urls}
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Every connected player's id."
  @spec connected() :: [String.t()]
  def connected do
    Registry.select(__MODULE__, [{{:"$1", :_, :_}, [], [:"$1"]}])
  rescue
    ArgumentError -> []
  end
end
