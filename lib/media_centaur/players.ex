defmodule MediaCentaur.Players do
  use Boundary,
    deps: [],
    exports: [
      Events,
      Events.PairingChanged,
      Events.PlayerPaired,
      Events.PlayerRemoved,
      Pairing,
      Pairing.Code,
      Player
    ]

  @moduledoc """
  Bounded context for the players paired with this install: the devices
  on the LAN, each a `Player` row, that the gate (`MediaCentaurWeb.RemoteAccess`)
  admits because their browser session holds the row's id. Pairing is
  how a device becomes one: the owner starts it here, which mints the one
  open `Pairing.Code`; the device offers the digits with its name on the
  pairing page, and `pair/2` turns a match into a row. The host itself is
  not a row — it is admitted by address.

  Knows nothing about which player a request is from; that is the web
  layer's (`MediaCentaurWeb.RemoteAccess`, `Live.PlayerAware`), the same
  split as `Profiles` and `Live.ProfileAware`. Broadcasts typed events on
  `players:updates` (`subscribe/0`).
  """

  import Ecto.Query

  alias MediaCentaur.DisplayName
  alias MediaCentaur.Players.Events
  alias MediaCentaur.Players.Pairing
  alias MediaCentaur.Players.Player
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics

  @doc "Subscribe the caller to player and pairing events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.players_updates())

  @doc "Every paired player, oldest first."
  @spec list() :: [Player.t()]
  def list, do: Repo.all(from player in Player, order_by: [asc: player.inserted_at, asc: player.id])

  @doc "A player by id; nil for an unknown or malformed id."
  @spec get(term()) :: Player.t() | nil
  def get(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Player, uuid)
      :error -> nil
    end
  end

  def get(_not_a_string), do: nil

  @doc "Opens pairing: mints the one code, replacing any open one. Broadcasts `PairingChanged`."
  @spec start_pairing() :: Pairing.Code.t()
  def start_pairing do
    code = Pairing.start()
    Events.broadcast(%Events.PairingChanged{code: code})
    code
  end

  @doc "The open pairing code, or nil."
  @spec pairing() :: Pairing.Code.t() | nil
  def pairing, do: Pairing.current()

  @doc "Closes the open pairing code, if any. Broadcasts `PairingChanged` when one was open."
  @spec cancel_pairing() :: :ok
  def cancel_pairing do
    if Pairing.cancel(), do: Events.broadcast(%Events.PairingChanged{code: nil})
    :ok
  end

  @doc """
  A device offers `code` with its `name`. A match under
  `DisplayName.check/1` adds the player, consumes the code and broadcasts
  `PlayerPaired` then `PairingChanged` (closed). A bad name leaves the
  code open. A miss spends an attempt; the last miss closes the code and
  broadcasts the closing.
  """
  @spec pair(String.t(), String.t()) ::
          {:ok, Player.t()} | {:error, :invalid_code | :name_required | :name_too_long}
  def pair(code, name) when is_binary(code) and is_binary(name) do
    with {:ok, name} <- DisplayName.check(name),
         :ok <- redeem(code) do
      {:ok, player} = %Player{} |> Player.changeset(%{name: name}) |> Repo.insert()
      Events.broadcast(%Events.PlayerPaired{player: player})
      Events.broadcast(%Events.PairingChanged{code: nil})
      {:ok, player}
    end
  end

  defp redeem(code) do
    case Pairing.redeem(code) do
      :ok ->
        :ok

      {:error, :invalid_code, :closed} ->
        Events.broadcast(%Events.PairingChanged{code: nil})
        {:error, :invalid_code}

      {:error, :invalid_code, :open} ->
        {:error, :invalid_code}
    end
  end

  @doc "Removes a player; its sessions are unpaired on their next request. Already removed answers `:ok` and broadcasts nothing. Broadcasts `PlayerRemoved`."
  @spec remove(Player.t()) :: :ok
  def remove(%Player{} = player) do
    case Repo.delete(player, stale_error_field: :id) do
      {:ok, _deleted} ->
        Events.broadcast(%Events.PlayerRemoved{id: player.id})
        :ok

      {:error, _stale} ->
        :ok
    end
  end
end
