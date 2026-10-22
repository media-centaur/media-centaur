defmodule MediaCentaur.Players.Events do
  @moduledoc """
  Typed payloads for `players:updates` (ADR-060): one struct per
  message, a single `broadcast/1`. The one `Topics.publish` in the
  Players context.
  """

  alias MediaCentaur.Players.Pairing
  alias MediaCentaur.Players.Player
  alias MediaCentaur.Topics

  defmodule PlayerPaired do
    @moduledoc "A device redeemed the pairing code and is now a player."
    @enforce_keys [:player]
    defstruct [:player]

    @type t :: %__MODULE__{player: Player.t()}
  end

  defmodule PlayerRemoved do
    @moduledoc "A player was removed; a session holding it is unpaired on its next request."
    @enforce_keys [:id]
    defstruct [:id]

    @type t :: %__MODULE__{id: Ecto.UUID.t()}
  end

  defmodule PairingChanged do
    @moduledoc "The open pairing code: a new one was minted, or the open one closed (`nil`) by redemption, cancellation or too many misses."
    @enforce_keys [:code]
    defstruct [:code]

    @type t :: %__MODULE__{code: Pairing.Code.t() | nil}
  end

  @type t :: PlayerPaired.t() | PlayerRemoved.t() | PairingChanged.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%PlayerPaired{} = event), do: publish({:player_paired, event})
  def broadcast(%PlayerRemoved{} = event), do: publish({:player_removed, event})
  def broadcast(%PairingChanged{} = event), do: publish({:pairing_changed, event})

  defp publish(message), do: Topics.publish(Topics.players_updates(), message)
end
