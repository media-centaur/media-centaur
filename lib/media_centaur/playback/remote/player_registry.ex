defmodule MediaCentaur.Playback.Remote.PlayerRegistry do
  @moduledoc """
  The connected remote players: one entry per player id, held by the
  process that owns that player's channel (the WebSocket handler), with
  the player's **locators** as the entry's value — the two functions the
  web layer captured at connect that turn a presence id into a media URL
  and a media URL back into a presence id. A transport reads them here, so
  Playback never names a web module and never composes a URL itself.

  An entry dies with its process; a reconnecting player's new channel
  evicts the old one first (`Channel.replace/1`).
  """

  @type locators :: %{locate: (String.t() -> String.t()), identify: (String.t() -> String.t() | nil)}

  @doc "Registers the calling process as `player_id`'s channel."
  @spec register(String.t(), locators()) :: :ok | {:error, {:already_registered, pid()}}
  def register(player_id, locators) do
    case Registry.register(__MODULE__, player_id, locators) do
      {:ok, _owner} -> :ok
      {:error, {:already_registered, pid}} -> {:error, {:already_registered, pid}}
    end
  end

  @doc "The channel process and locators for a connected player, or nil."
  @spec lookup(String.t()) :: {pid(), locators()} | nil
  def lookup(player_id) do
    case Registry.lookup(__MODULE__, player_id) do
      [{pid, locators}] -> {pid, locators}
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
